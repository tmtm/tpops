# $Id: tserver.rb,v 1.23 2004/03/21 13:14:00 tommy Exp $
#
# Copyright (C) 2003-2004 TOMITA Masahiro
# tommy@tmtm.org
#

require "socket"
require "tempfile"

class TServer

  class Children < Array
    def fds()
      self.map{|c| c.active? ? c.from : nil}.compact.flatten
    end

    def pids()
      self.map{|c| c.pid}
    end

    def active()
      self.map{|c| c.active? ? c : nil}.compact
    end

    def idle()
      self.map{|c| c.idle? ? c :  nil}.compact
    end

    def by_fd(fd)
      self.each do |c|
        return c if c.from == fd
      end
      nil
    end

    def cleanup()
      new = Children.new
      self.each do |c|
        new << c unless c.exit
      end
      self.replace new
    end
  end

  class Child
    def initialize(pid, from, to)
      @pid, @from, @to = pid, from, to
      @status = :new
      @exit = false
    end
    # status is one of :new, :idle, :connect, :close

    attr_accessor :pid, :from, :to, :exit

    def event(s)
      case s
      when "connect" then @status = :connect
      when "disconnect" then @status = :idle
      when "close" then @status = :close
      else
        $stderr.puts "unknown status: #{s}"
      end
    end

    def close()
      @from.close unless @from.closed?
      @to.close unless @to.closed?
      @status = :close
    end

    def idle?()
      @status == :new or @status == :idle
    end

    def active?()
      @exit == false and (@status == :new or @status == :idle or @status == :connect)
    end

  end

  @@children = Children.new
  @@already_setup_signal = false
  @@already_setup_sigchld = false

  def initialize(*args)
    @handle_signal = true
    @min_servers = 5
    @max_servers = 50
    @max_request_per_child = 50
    @max_idle = 100
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

  def on_child_start(&block)
    if block == nil then
      raise "block required"
    end
    @on_child_start = block
  end

  def on_child_exit(&block)
    if block == nil then
      raise "block required"
    end
    @on_child_exit = block
  end

  attr_reader :socks
  attr_accessor :min_servers, :max_servers, :max_request_per_child, :max_idle
  alias max_use max_request_per_child
  alias max_use= max_request_per_child=
  attr_writer :on_child_start, :on_child_exit
  attr_accessor :handle_signal

  def start(&block)
    if block == nil then
      raise "block required"
    end
    setup_signal_handler if @handle_signal
    unless @@already_setup_sigchld then
      old_chld_trap = trap "CHLD" do
        @@children.active.each do |c|
          Process.waitpid(c.pid, Process::WNOHANG) rescue nil
        end
        old_chld_trap.call if old_chld_trap.is_a? Proc
      end
      @@already_setup_sigchld = true
    end
    (@min_servers-@@children.size).times do
      make_child block
    end
    @flag = :in_loop
    while @flag == :in_loop do
      r, = IO.select(@@children.fds, nil, nil, nil)
      if r then
        r.each do |f|
          c = @@children.by_fd f
          l = f.gets
          if l then
            c.event l.chomp
          else
            c.exit = true
          end
        end
      end
      @@children.cleanup
      n = 0
      if @@children.size < @min_servers then
        n = @min_servers - @@children.size
      else
        if @@children.idle.size <= 2 then
          n = 2
        end
      end
      if @@children.size + n > @max_servers then
        n = @max_servers - @@children.size
      end
      n.times do
	make_child block
      end
    end
    @flag = :out_of_loop
    terminate
  end

  def close()
    if @flag != :out_of_loop then
      raise "close() must be called out of start() loop"
    end
    @socks.each do |s|
      s.close
    end
  end

  def stop()
    @flag = :exit_loop
  end

  def terminate()
    @@children.each do |c|
      c.to.close unless c.to.closed?
    end
  end

  def interrupt()
    Process.kill "TERM", *(@@children.pids) rescue nil
  end

  private

  def exit_child()
    @on_child_exit.call if defined? @on_child_exit
    exit!
  end

  def make_child(block)
    to_child = IO.pipe
    to_parent = IO.pipe
    pid = fork do
      @@children.map{|c| c.close}
      @from_parent = to_child[0]
      @to_parent = to_parent[1]
      to_child[1].close
      to_parent[0].close
      child block
    end
    @@children << Child.new(pid, to_parent[0], to_child[1])
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
      @to_parent.syswrite "connect\n"
      block.call(s)
      s.close unless s.closed?
      @to_parent.syswrite "disconnect\n" rescue nil
      cnt += 1
      last_connect = Time.now
    end
    exit_child
  end
end
