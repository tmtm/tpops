# $Id: tpops_auth-passwd.rb,v 1.12 2004/05/31 18:02:08 tommy Exp $

require 'etc'

class TPOPS
  class Auth

    def Auth.apop?()
      defined? $apop_passwd_file
    end

    def initialize(user, pass, apop=nil)
      $passwd_lock_dir = '/var/run/tpops' unless defined? $passwd_lock_dir and $passwd_lock_dir
      $maildir = "Maildir" unless defined? $maildir and $maildir
      begin
	pw = Etc.getpwnam user
      rescue ArgumentError
	return
      end
      @login, @uid, @maildir = pw.name, pw.uid, pw.dir+"/"+$maildir+"/"
      if apop then
        require 'dbm'
	require 'md5'
	pw = DBM.open($apop_passwd_file, 0600)[@login]
	return unless pw
	if pass == MD5.new(apop+pw).hexdigest then
	  @authorized = true
	end
	return
      else
	if pw.passwd == 'x' then
          IO.foreach("/etc/shadow") do |line|
            shuser, shpw = line.split(/:/)
            if shuser == @login and shpw.length > 1 and pass.crypt(shpw) == shpw then
              @authorized = true
              return
            end
          end
        elsif pass.crypt(pw.passwd) == pw.passwd then
	  @authorized = true
	end
      end
    end

    def authorized?()
      @authorized
    end

    def locked?()
      @locked
    end

    attr_reader :login, :uid, :maildir

    def lock()
      Dir.mkdir $passwd_lock_dir, 0700 unless File.exists? $passwd_lock_dir
      lockfile = "#{$passwd_lock_dir}/#{@uid}"
      if File.exist? lockfile then
        begin
          if Time.now.to_i - File.mtime(lockfile).to_i > $connection_keep_time then
            File.unlink lockfile
            log_warn "lockfile removed because timeout: #{lockfile}"
          else
            pid, host = File.open(lockfile) do |f| f.read.split end
            if pid =~ /^\d+$/ and host == $hostname then
              begin
                Process.kill 0, pid.to_i
                return false
              rescue Errno::ESRCH
                File.unlink lockfile
                log_warn "lockfile removed because pid(#{pid}) not exist: #{lockfile}"
              end
            end
          end
        rescue Errno::ENOENT
          # ignore "no such file or directory"
        end
      end
      begin
        File.open(lockfile, File::RDWR|File::CREAT|File::EXCL, 0600).close
      rescue Errno::EEXIST
        return false
      end
      @lockfile = lockfile
      @locked = true
      true
    end

    def unlock()
      if @locked and @lockfile then
        File.unlink @lockfile rescue log_err #{@lockfile}: #{$!}"
      end
      @locked = false
    end
  end
end
