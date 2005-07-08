# $Id: tpops.rb,v 1.5 2005/07/08 09:13:44 tommy Exp $
#
# Copyright (C) 2003-2005 TOMITA Masahiro
# tommy@tmtm.org
#

require "getssafe"

class TPOPS

  class Error < StandardError
  end

  @auth_classes = {}
  @mailbox_classes = {}
  @parallel_classes = {}
  @conf = nil

  @command = {
    :AUTHORIZATION => {
      "QUIT" => :comm_auth_quit,
      "USER" => :comm_user,
      "PASS" => :comm_pass,
      "APOP" => :comm_apop,
    },
    :TRANSACTION => {
      "STAT" => :comm_stat,
      "LIST" => :comm_list,
      "RETR" => :comm_retr,
      "DELE" => :comm_dele,
      "NOOP" => :comm_noop,
      "RSET" => :comm_rset,
      "TOP"  => :comm_top,
      "UIDL" => :comm_uidl,
      "LAST" => :comm_last,
      "QUIT" => :comm_quit,
    },
  }

  def self.conf()
    @conf
  end

  def self.conf=(v)
    @conf = v
  end

  def self.uid()
    @uid
  end

  def self.uid=(uid)
    @uid = uid
  end

  def self.gid()
    @gid
  end

  def self.gid=(gid)
    @gid = gid
  end

  def self.add_auth_class(name, klass)
    @auth_classes[name] = klass
  end

  def self.auth_class=(name)
    @auth_class = name
  end

  def self.auth_class()
    @auth_classes[@auth_class]
  end

  def self.add_mailbox_class(name, klass)
    @mailbox_classes[name] = klass
  end

  def self.mailbox_class=(name)
    @mailbox_class = name
  end

  def self.mailbox_class()
    @mailbox_classes[@mailbox_class]
  end

  def self.add_parallel_class(name, klass)
    @parallel_classes[name] = klass
  end

  def self.parallel_class=(name)
    @parallel_class = name
  end

  def self.parallel_class()
    @parallel_classes[@parallel_class]
  end

  def self.command()
    @command
  end

  def self.command=(comm)
    @command = comm
  end

  def start()
    pl = nil
    port = nil
    signal_setup = false
    already_forked = false
    pid_file = nil
    parallel_class = TPOPS.parallel_class
    loop = true
    while loop do
      load_config

      if TPOPS.conf["port"] != port then
        pl.close if pl
        pl = parallel_class.new(*(TPOPS.conf["port"].to_s.split(/:/)))
        port = TPOPS.conf["port"]
      end

      unless signal_setup then
        trap :HUP do
          Log.notice "tpops daemon reload"
          pl.stop
        end
        trap :TERM do
          loop = false
          pl.stop
        end
        trap :INT do
          pl.interrupt
          loop = false
          pl.stop
        end
        signal_setup = true
      end

      if TPOPS.conf["error-log"] then
        File.open(TPOPS.conf["error-log"], "a") do |f|
          STDERR.reopen f
          STDERR.sync = true
        end
      end

      if not TPOPS.conf["fg"] and not already_forked then
        if fork then
          exit
        end
        File.open("/dev/null") do |f|
          STDIN.reopen f
        end
        File.open("/dev/null", "w") do |f|
          STDOUT.reopen f
        end
        Process.setsid
        already_forked = true
        Log.notice "tpops daemon start"
      end

      File.unlink pid_file rescue nil if pid_file
      pid_file = nil
      if TPOPS.conf["pid-file"] and not TPOPS.conf["pid-file"].empty? then
        File.open(TPOPS.conf["pid-file"], "w") do |f| f.puts $$ end
        pid_file = TPOPS.conf["pid-file"]
      end

      pl.start do |conn|
        begin
          Conn.new conn
        rescue TPOPS::Error
          Log.err "#{$!}"
        rescue
          Log.err "#{$@[0]}: #{$!}"
          STDERR.puts Time.now.inspect
          STDERR.flush
          raise
        end
      end
    end
    File.unlink pid_file rescue nil if pid_file
    Log.notice "tpops daemon stop" unless TPOPS.conf["inetd"]
  end

  def start_by_inetd()
    File.open(TPOPS.conf["error-log"] || "/dev/null", "a") do |f|
      STDERR.reopen f
      STDERR.sync
    end
    begin
      Process.uid = TPOPS.uid if TPOPS.uid
      Process.euid = TPOPS.uid if TPOPS.uid
      Process.gid = TPOPS.gid if TPOPS.gid
      Conn.new(Socket.for_fd(STDIN.fileno))
    rescue TPOPS::Error
      Log.err "#{$!}"
    rescue
      Log.err "#{$@[0]}: #{$!}"
      STDERR.puts Time.now.inspect
      STDERR.flush
      raise
    end
    exit
  end

  def load_config()
    begin
      TPOPS.conf.parse ARGV
    rescue OptConfig::Error
      Log.err "#{$!}"
      raise
    end

    TPOPS.auth_class = TPOPS.conf["auth-type"]
    TPOPS.mailbox_class = TPOPS.conf["mailbox-type"]
    TPOPS.parallel_class = TPOPS.conf["parallel-type"]

    TPOPS.auth_class.reset

    TPOPS.uid = nil
    if TPOPS.conf["user"] then
      if TPOPS.conf["user"] =~ /\A\d+\Z/ then
        TPOPS.uid = TPOPS.conf["user"].to_i
      else
        require "etc"
        TPOPS.uid = Etc.getpwnam(TPOPS.conf["user"]).uid
      end
    end
    TPOPS.gid = nil
    if TPOPS.conf["group"] then
      if TPOPS.conf["group"] =~ /\A\d+\Z/ then
        TPOPS.gid = TPOPS.conf["group"].to_i
      else
        require "etc"
        TPOPS.gid = Etc.getgrnam(TPOPS.conf["group"]).gid
      end
    end
    if not TPOPS.conf["syslog"] or TPOPS.conf["syslog"] == "none" then
      Log.close
    else
      f = "LOG_#{TPOPS.conf["syslog"].upcase}"
      unless Syslog.constants.include? f then
        raise TPOPS::Error, "unknown facility: #{TPOPS.conf["syslog"]}"
      end
      fac = eval "Syslog::#{f}"
      Log.open fac, TPOPS.conf["debug"]
    end
  end
end

class TPOPS::Conn
  def initialize(sock)
    @sock = sock
    @status = :AUTHORIZATION
    @user = nil
    @apopkey = TPOPS.auth_class.apop? ? "<#{$$}.#{Time.now.to_i}@#{TPOPS.conf["hostname"]}>" : ""
    @start_time = Time.now
    @peer_addr = sock_to_addr @sock
    @mailbox = nil

    Log.info "connect from #{@peer_addr}"

    class <<@sock
      include GetsSafe
      def write(str)
        begin
          super str
        rescue
          raise TPOPS::Error, $!.to_s
        end
      end
    end

    connect_time = Time.now.to_i
    @sock.timeout = TPOPS.conf["command-timeout"].to_i
    @sock.maxlength = 1024

    ok "TPOPS ready. #{@apopkey}"
    begin
      catch :disconnect do
        loop do
          begin
            r = @sock.gets_safe
          rescue Errno::ETIMEDOUT
            Log.warn "command timeout"
            break
          rescue Errno::E2BIG
            Log.warn "line too long"
            break
          end
          if not r then
            Log.warn "connection closed unexpectedly"
            break
          end
          if connect_time < Time.now.to_i-TPOPS.conf["connection-keep-time"].to_i then
            Log.warn "connection time exceeded"
            err "connection time exceeded"
            break
          end
          r = r.chomp
          Log.debug "< #{r}"
          comm, arg = r.split(/ /, 2)
          next unless comm
          args = arg ? arg.split(/ /, -1) : []
          case @status
          when :AUTHORIZATION
            m = TPOPS.command[:AUTHORIZATION][comm.upcase]
            if m then
              self.method(m).call(args)
            else
              err "invalid command"
            end
          when :TRANSACTION
            m = TPOPS.command[:TRANSACTION][comm.upcase]
            if m then
              self.method(m).call(args)
            else
              err "invalid command"
            end
          end
        end
      end
    ensure
      @mailbox.unlock if @mailbox
      write_log rescue nil
      @sock.close rescue nil
      Log.info "disconnect from #{@peer_addr}" rescue nil
    end
  end

  def err(arg=nil)
    sleep TPOPS.conf["error-interval"].to_i
    @sock.write(arg ? "-ERR #{arg}\r\n" : "-ERR\r\n")
    Log.debug "> -ERR #{arg}"
  end

  def ok(arg=nil)
    @sock.write(arg ? "+OK #{arg}\r\n" : "+OK\r\n")
    Log.debug "> +OK #{arg}"
  end

  def comm_auth_quit(arg)
    if arg.size != 0 then
      err "too many arguments"
      return
    end
    ok "server signing off" rescue true
    throw :disconnect
  end

  def comm_user(arg)
    if @user then
      err "invalid command"
      return
    end
    if arg.size != 1 then
      err "too few/many arguments"
      return
    end
    ok "password required"
    @user = arg[0]
    if TPOPS.conf["domain"] then
      d = TPOPS.conf["domain"]
      if d =~ /^[a-z0-9]/i then
        d = "@"+d
      end
      if @user !~ /[@%\+]/ then
        @user = @user+d
      end
    end
  end

  def comm_pass(arg)
    if not @user then
      err "invalid command"
      return
    end
    pass = arg.join(" ")
    if pass.empty? then
      err "too few/many arguments"
      return
    end

    begin
      @auth = TPOPS.auth_class.new @user, pass
      to_transaction
    rescue TPOPS::Error
      Log.notice "authentication failed: #{@user}"
      err "authentication failed"
      throw :disconnect
    end
  end

  def comm_apop(arg)
    unless TPOPS.auth_class.apop? then
      err "APOP not supported"
      return
    end
    if @user then
      err "invalid command"
      return
    end
    if arg.size != 2 then
      err "too few/many arguments"
      return
    end
    @user = arg[0]

    begin
      @auth = TPOPS.auth_class.new arg[0], arg[1], @apopkey
      to_transaction
    rescue TPOPS::Error
      Log.notice "authentication failed: #{@user}"
      err "authentication failed"
      throw :disconnect
    end
  end  

  def to_transaction()
    begin
      @mailbox = TPOPS.mailbox_class.new @auth.maildir
    rescue TPOPS::Error
      Log.err "#{$!} for #{@user}"
      err $!.to_s
      throw :disconnect
    end
    @status = :TRANSACTION
    msgs, size = @mailbox.stat
    @start_mailbox = [msgs, size]
    ok "#{@user} has #{msgs} messages (#{size} octets)"
    Log.info "login: #{@user} has #{msgs} messages (#{size} octets)"
  end

  def write_log()
    if @mailbox then
      msgs, size = @mailbox.real_stat
    else
      msgs, size = 0, 0
    end
    if @status == :TRANSACTION then
      Log.info "logout: #{@user} has #{msgs} messages (#{size} octets)"
    end
    if TPOPS.conf["access-log"] then
      if @start_mailbox then
        s_msgs, s_size = @start_mailbox
      else
        s_msgs, s_size = 0, 0
      end
      u = @user == nil ? "()" : @status == :TRANSACTION ? @user : "(#{@user})"
      File.open(TPOPS.conf["access-log"], "a") do |f|
        f.syswrite sprintf("%s %s %s %s %d %d %d %d\n",
          @peer_addr, @start_time.strftime("%Y/%m/%d %H:%M:%S"),
          Time.now.strftime("%Y/%m/%d %H:%M:%S"),
          u, s_msgs, s_size, msgs, size)
      end
    end
  end

  def sock_to_addr(s)
    begin
      return s.peeraddr[3]
    rescue
      return "unknown"
    end
  end

  def comm_stat(arg)
    if arg.size != 0 then
      err "too many arguments"
      return
    end
    n, m = @mailbox.stat
    ok "#{n} #{m}"
  end

  def comm_list(arg)
    if arg.size == 0 then
      n, m = @mailbox.stat
      ok "#{n} messages (#{m} octets)"
      @sock.sync = false
      @mailbox.list_all.each do |n, m|
        @sock.write "#{n} #{m}\r\n"
      end
      @sock.sync = true
      @sock.write ".\r\n"
    elsif arg.size == 1 then
      n, m = @mailbox.list(arg[0].to_i)
      if n then
        ok "#{n} #{m}"
      else
        err "no such message"
      end
    else
      err "too many arguments"
    end
  end

  def comm_retr(arg)
    if arg.size != 1 then
      err "too few/many arguments"
      return
    end
    n = arg[0].to_i
    m, size = @mailbox.list(n)
    if not m then
      err "no such message"
      return
    end
    begin
      @sock.sync = false
      first = true
      @mailbox.retr(n) do |line|
        if first then
          ok "#{size} octets"
          first = false
        end
        if line[0] == ?. then line[0,0] = "." end
        @sock.write line
      end
      @sock.sync = true
      @sock.write ".\r\n"
    rescue Errno::ENOENT
      err "no such message"
    end
  end

  def comm_dele(arg)
    if arg.size != 1 then
      err "too few/many arguments"
      return
    end
    if @mailbox.dele(arg[0].to_i) then
      ok "message deleted"
    else
      err "no such message"
    end
  end

  def comm_noop(arg)
    if arg.size != 0 then
      err "too many arguments"
      return
    end
    ok
  end

  def comm_rset(arg)
    if arg.size != 0 then
      err "too many arguments"
      return
    end
    @mailbox.rset
    ok
  end

  def comm_top(arg)
    if arg.size != 2 then
      err "too few/many arguments"
      return
    end
    if not @mailbox.list(arg[0].to_i) then
      err "no such message"
      return
    end
    begin
      @sock.sync = false
      first = true
      @mailbox.top(arg[0].to_i, arg[1].to_i) do |line|
        if first then
          ok
          first = false
        end
        if line[0] == ?. then line[0,0] = "." end
        @sock.write line
      end
      @sock.sync = true
      @sock.write ".\r\n"
    rescue Errno::ENOENT
      err "no such message"
    end
  end

  def comm_uidl(arg)
    if arg.size == 0 then
      ok
      @sock.sync = false
      @mailbox.uidl_all.each do |m, id|
        @sock.write "#{m} #{id}\r\n"
      end
      @sock.sync = true
      @sock.write ".\r\n"
    elsif arg.size == 1 then
      m, id = @mailbox.uidl(arg[0].to_i)
      if m then
        ok "#{m} #{id}"
      else
        err "no such message"
      end
    else
      err "too many arguments"
    end
  end

  def comm_last(arg)
    if arg.size != 0 then
      err "too many arguments"
      return
    end
    n = @mailbox.last
    ok "#{n}"
  end

  def comm_quit(arg)
    if arg.size != 0 then
      err "too many arguments"
      return
    end
    @mailbox.commit
    ok "server signing off" rescue true
    throw :disconnect
  end
end
