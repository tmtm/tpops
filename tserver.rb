# $Id: tserver.rb,v 1.19.2.1 2004/03/02 10:30:23 tommy Exp $

require "socket"
require "tempfile"

class TServer

  def initialize(*args)
    @min_servers = 5
    @max_servers = 50
    @max_request_per_child = 50
    @max_idle = 100
    @children = []
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
    @old_trap = {}
    @old_trap["CHLD"] = trap "CHLD" do
      @children.delete_if do |pid|
        ret = Process.waitpid(pid, Process::WNOHANG) rescue nil
        ret
      end
      @old_trap["CHLD"].call if @old_trap["CHLD"].is_a? Proc
    end
    @old_trap["TERM"] = trap "TERM" do
      @to_child.each_value do |f| f.close rescue nil end
      if @old_trap["TERM"].is_a? Proc then
	@old_trap["TERM"].call
      else
	exit
      end
    end
    @old_trap["HUP"] = trap "HUP" do
      @to_child.each_value do |f| f.close rescue nil end
      @old_trap["HUP"].call if @old_trap["HUP"].is_a? Proc
    end
    @old_trap["INT"] = trap "INT" do
      Process.kill "TERM", *@children rescue nil
      if @old_trap["INT"].is_a? Proc then
	@old_trap["INT"].call
      else
	exit
      end
    end
  end

  def sock()
    @socks[0]
  end

  attr_reader :socks
  attr_accessor :min_servers, :max_servers, :max_request_per_child, :max_idle
  alias max_use max_request_per_child
  alias max_use= max_request_per_child=
  attr_writer :on_child_start, :on_child_exit

  def start(&block)
    @from_child = {}
    @to_child = {}
    if block == nil then
      raise "block required"
    end
    @min_servers.times do
      make_child block
    end
    loop do
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
      cs = @children.size
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
    @children << pid
    @to_child[pid] = to_child[1]
    @from_child[pid] = to_parent[0]
    to_child[0].close
    to_parent[1].close
  end

  def child(block)
    trap "SIGHUP", "SIG_DFL"
    trap "SIGCHLD", "SIG_DFL"
    trap "SIGTERM" do exit_child end
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
