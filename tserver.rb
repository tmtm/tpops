# $Id: tserver.rb,v 1.1 2002/12/03 16:26:34 tommy Exp $

require 'socket'

class TServer

  def initialize(*args)
    @min_servers = 5
    @max_servers = 50
    @max_request_per_child = 50
    @max_idle = 100
    @children = []
    @connections = []
    if args.length == 1 and args[0].is_a? TCPSocket then
      @sock = args[0]
    else
      @sock = TCPServer::new(*args)
    end
    @old_trap = {}
    @old_trap['CHLD'] = trap 'CHLD' do
      if on_child_exit then
	@old_trap['CHLD'].call if @old_trap['CHLD']
      end
    end
    @old_trap['TERM'] = trap 'TERM' do
      @to_child.each_value do |f| f.puts 'exit' end
      if @old_trap['TERM'] then
	@old_trap['TERM'].call
      else
	exit
      end
    end
    @old_trap['HUP'] = trap 'HUP' do
      @to_child.each_value do |f| f.puts 'exit' end
      @old_trap['HUP'].call if @old_trap['HUP']
    end
    @old_trap['USR1'] = trap 'USR1' do
      @to_child.each_value do |f| f.puts 'exit' end
      @old_trap['USR1'].call if @old_trap['USR1']
    end
    @old_trap['INT'] = trap 'INT' do
      Process::kill 'TERM', *@children rescue nil
      if @old_trap['INT'] then
	@old_trap['INT'].call
      else
	exit
      end
    end
  end

  attr_reader :sock
  attr_accessor :min_servers, :max_servers, :max_request_per_child, :max_idle
  alias max_use max_request_per_child
  alias max_use= max_request_per_child=
  attr_accessor :on_child_start, :on_child_exit

  def start(&block)
    @from_child, @to_parent = IO::pipe
    @to_child = {}
    @last_connect = {}
    if block == nil then
      raise 'block required'
    end
    @min_servers.times do
      make_child block
    end
    loop do
      if IO::select([@from_child], nil, nil, 1) then
	from_child @from_child.gets.chomp
      end
      if @children.size > @min_servers then
	now = Time::now.to_i
	@children.each do |pid|
	  if @last_connect[pid] and @max_idle and
	      now - @last_connect[pid] > @max_idle then
	    @to_child[pid].puts 'exit' rescue true
	    break
	  end
	end
      end
      if @children.size < @min_servers then
	n = @min_servers-@children.size 
      elsif @connections.size >= @children.size-1 and @children.size < @max_servers then
	n = @connections.size - @children.size + 2
	if @children.size + n > @max_servers then
	  n = @max_servers - @children.size
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
  def on_child_exit()
    exited_pids = []
    @children.each do |pid|
      begin
	if Process::waitpid(pid, Process::WNOHANG) then
	  exited_pids << pid
	end
      rescue Errno::ECHILD	# for Linux bug?
      end
    end
    exited_pids.each do |pid|
      @children.delete pid
      @connections.delete pid
      @to_child[pid].close
      @to_child.delete pid
      @last_connect.delete pid
    end
    return exited_pids.empty?
  end

  def from_child(str)
    pid, *args = str.split
    pid = pid.to_i
    case args[0]
    when 'connect'
      @connections << pid
      @last_connect[pid] = nil
    when 'disconnect'
      @connections.delete pid
      @last_connect[pid] = Time::now.to_i
    end
  end

  def from_parent(str)
    case str
    when 'exit'
      @on_child_exit.call if defined? @on_child_exit
      exit
    end
  end

  def make_child(block)
    pipe = IO::pipe
    pid = fork do
      @to_child.each_value do |f| f.close end
      @from_parent = pipe[0]
      pipe[1].close unless pipe[1].closed?
      @from_child.close
      trap 'SIGCHLD', 'SIG_DFL'
      trap 'SIGTERM', 'SIG_DFL'
      trap 'SIGHUP', 'SIG_DFL'
      trap 'SIGUSR1', 'SIG_DFL'
      @on_child_start.call if defined? @on_child_start
      cnt = 0
      while @max_request_per_child == 0 or cnt < @max_request_per_child
	r, = IO::select([@sock, @from_parent])
	if r.include? @from_parent then
	  msg = @from_parent.gets
	  if msg == nil then
	    break
	  end
	  from_parent msg.chomp
	  next
	end
	s = @sock.accept
	@to_parent.puts "#{$$} connect"
	block.call(s)
	s.close unless s.closed?
	@to_parent.puts "#{$$} disconnect"
	cnt += 1
      end
      @on_child_exit.call if defined? @on_child_exit
    end
    @children << pid
    pipe[0].close
    @to_child[pid] = pipe[1]
    @last_connect[pid] = nil
  end

end