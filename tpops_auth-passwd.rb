# $Id: tpops_auth-passwd.rb,v 1.8 2002/12/03 16:26:34 tommy Exp $

require 'etc'

class TPOPS
  class Auth

    $passwd_lock_dir = '/var/tmp/tpops' unless defined? $passwd_lock_dir

    def Auth::apop?()
      defined? $apop_passwd_file
    end

    def initialize(user, pass, apop=nil)
      begin
	pw = Etc::getpwnam user
      rescue ArgumentError
	return
      end
      @login, @uid, @maildir = pw.name, pw.uid, pw.dir+'/Maildir/'
      if apop then
	require 'bdb'
	require 'md5'
	apophash = BDB::Hash::open($apop_passwd_file, nil, 'r')
	pw = apophash[@login+"\0"].chop
	apophash.close
	return unless pw
	if pass == MD5::new(apop+pw).hexdigest then
	  @authorized = true
	end
	return
      else
	if pw.passwd == 'x' then
	  require 'shadow'
	  sh = Shadow::Passwd.getspnam @login
	  if sh and sh.sp_pwdp.length > 1 and pass.crypt(sh.sp_pwdp) == sh.sp_pwdp then
	    @authorized = true
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
      lockfile = "#{$passwd_lock_dir}/#{@uid}"
      Dir::mkdir $passwd_lock_dir, 0700 unless File::exists? $passwd_lock_dir
      if File::exists? lockfile then
	if Time::now - File::stat(lockfile).mtime > $connection_keep_time then
	  File::unlink lockfile rescue nil
	else
	  pid, host = File::open(lockfile) do |f| f.gets.split end
	  if pid =~ /^\d+$/ and host == $hostname then
	    begin
	      Process::kill 0, pid.to_i
	      return false
	    rescue Errno::ESRCH
	      File::unlink lockfile
	    rescue
	      return false
	    end
	  end
	end
      end
      begin
	File::open(lockfile, File::RDWR|File::CREAT|File::EXCL, 0600) do |f|
	  f.puts "#{$$.to_s} #{$hostname}"
	end
      rescue
	log_err "#{lockfile}: #{$!.to_s}"
	$stderr.puts "#{lockfile}: #{$!.to_s}"
	return false
      end
      @locked = true
      true
    end

    def unlock()
      lockfile = "#{$passwd_lock_dir}/#{@uid}"
      File::unlink lockfile
      @locked = false
    end

  end
end
