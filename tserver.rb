# $Id: tserver.rb,v 1.21 2004/03/02 12:49:53 tommy Exp $
#
# Copyright (C) 2003-2004 TOMITA Masahiro
# tommy@tmtm.org
#

require "socket"
require "tempfile"

class TServer

  @@children = []
  @@already_setup_signal = false
  @@already_setup_sigchld = false

  def initialize(*args)
    @handle_signal = true
    @min_servers = 5
    @max_servers = 50
    @max_request_per_child = 50
    @max_idle = 100
    @connections = []
    @exited_pids = []
    if args[0].is_a? BasicSocket then
      args.each do |s|
	raise "Socket required" unless s.is_a? BasicSocket
      end
      @socks = args
    else
      @socks = [TCPServer.new(*args)]
    end
    f = Tempfile.new(".tserver")
    @lockf = f.path
    f.close
  end

  def setup_signal_handler()
    return if @@already_setup_signal
    @old_trap = {}
    @old_trap["TERM"] = trap "TERM" do
      terminate
      if @old_trap["TERM"].is_a? Proc then
	@old_trap["TERM"].call
      else
	exit
      end
    end
    @old_trap["HUP"] = trap "HUP" do
      terminate
      @old_trap["HUP"].call if @old_trap["HUP"].is_a? Proc
    end
    @old_trap["INT"] = trap "INT" do
      interrupt
      if @old_trap["INT"].is_a? Proc then
	@old_trap["INT"].call
      else
	exit
      end
    end
    @@already_setup_signal = true
  end

  def sock()
    @socks[0]
  end

  attr_reader :socks
  attr_accessor :min_servers, :max_servers, :max_request_per_child, :max_idle
  alias max_use max_request_per_child
  alias max_use= max_request_per_child=
  attr_writer :on_child_start, :on_child_exit

  def handle_signal=(f)
    @handle_signal = f
  end

  def start(&block)
    if block == nil then
      raise "block required"
    end
    setup_signal_handler if @handle_signal
    unless @@already_setup_sigchld then
      old_chld_trap = trap "CHLD" do
        @@children.delete_if do |pid|
          Process.waitpid(pid, Process::WNOHANG) rescue nil
        end
        old_chld_trap.call if old_chld_trap.is_a? Proc
      end
      @@already_setup_sigchld = true
    end
    @from_child = {}
    @to_child = {}
    @min_servers.times do
      make_child block
    end
    @flag = :in_loop
    while @flag == :in_loop do
      r, = IO.select(@from_child.values, nil, nil, 1)
      if r then
        r.each do |fc|
          pid = @from_child.invert[fc]
          l = fc.gets
          if l then
            from_child pid, l.chomp
          else
            @connections.delete pid
            @to_child[pid].close rescue nil
            @to_child.delete pid
            @from_child[pid].close rescue nil
            @from_child.delete pid
          end
        end
      end
      cs = @@children.size
      if cs < @min_servers then
	n = @min_servers-cs
      elsif @connections.size >= cs-1 and cs < @max_servers then
	n = @connections.size - cs + 2
	if cs + n > @max_servers then
	  n = @max_servers - cs
	end
      else
	n = 0
      end
      n.times do
	make_child block
      end
    end
    @flag = :out_of_loop
    terminate
    @from_child.each_value do |p|
      p.close
    end
    @to_child.each_value do |p|
      p.close
    end
  end

  def close()
    if @flag != :out_of_loop then
      raise "close() must be call out of start loop"
    end
    @socks.each do |s|
      s.close
    end
  end

  def stop()
    @flag = :exit_loop
  end

  def terminate()
    @to_child.each_value do |f| f.close rescue nil end
  end

  def interrupt()
    Process.kill "TERM", *@@children rescue nil
  end

  private

  def from_child(pid, str)
    case str
    when "connect"
      @connections << pid
    when "disconnect"
      @connections.delete pid
    end
  end

  def exit_child()
    @on_child_exit.call if defined? @on_child_exit
    exit!
  end

  def make_child(block)
    to_child = IO.pipe
    to_parent = IO.pipe
    pid = fork do
      @to_child.each_value do |f| f.close rescue nil end
      @from_child.each_value do |f| f.close rescue nil end
      @from_parent = to_child[0]
      @to_parent = to_parent[1]
      to_child[1].close
      to_parent[0].close
      child block
    end
    @@children << pid
    @to_child[pid] = to_child[1]
    @from_child[pid] = to_parent[0]
    to_child[0].close
    to_parent[1].close
  end

  def child(block)
    trap "HUP", "SIG_DFL"
    trap "CHLD", "SIG_DFL"
    trap "INT", "SIG_DFL"
    trap "TERM" do exit_child end
    @on_child_start.call if defined? @on_child_start
    cnt = 0
    lock = File.open(@lockf, "w")
    last_connect = nil
    while @max_request_per_child == 0 or cnt < @max_request_per_child
      tout = last_connect ? last_connect+@max_idle-Time.now : nil
      break if tout and tout <= 0
      r, = IO.select([@socks, @from_parent].flatten, nil, nil, tout)
      break unless r
      break if r.include? @from_parent
      next unless lock.flock(File::LOCK_EX|File::LOCK_NB)
      r, = IO.select(@socks, nil, nil, 0)
      if r == nil then
        lock.flock(File::LOCK_UN)
        next
      end
      s = r[0].accept
      lock.flock(File::LOCK_UN)
      @to_parent.puts "connect"
      block.call(s)
      s.close unless s.closed?
      @to_parent.puts "disconnect" rescue nil
      cnt += 1
      last_connect = Time.now
    end
    exit_child
  end
end
