# $Id: tpops_auth-passwd.rb,v 1.2 2002/02/07 16:12:55 tommy Exp $

require 'etc'

class TPOPS
  class Auth

    PasswdLockDir = '/var/tmp/tpops' unless defined? PasswdLockDir
    APOPPasswd = '/etc/tpops-apoppw' unless defined? APOPPasswd

    def Auth::apop?()
      true
    end

    def initialize(user, pass, apop=nil)
      begin
	pw = Etc::getpwnam user
      rescue ArgumentError
	return
      end
      @login, @uid, @maildir = pw.name, pw.uid, pw.dir+'/Maildir/'
      if apop then
	dbm = GDBM::open(APOPPasswd, 0600)
	p = dbm[@login]
	dbm.close
	return unless p
	if pass == MD5::new(apop+pw).hexdigest then
	  @authorized = true
	end
	return
      else
	if pass.crypt(pw.passwd) == pw.passwd then
	  @authorized = true
	  return
	end
	if pw.passwd == 'x' then
	  require 'shadow'
	  sh = Shadow::Passwd.getspnam @login
	  if sh and pass.crypt(sh.sp_pwdp) == sh.sp_pwdp then
	    @authorized = true
	  end
	end
      end
    end

    def authorized?()
      @authorized
    end

    attr_reader :login, :uid, :maildir

    def lock()
      lockfile = "#{PasswdLockDir}/#{@uid}"
      Dir::mkdir PasswdLockDir, 0700 unless File::exists? PasswdLockDir
      File::open(lockfile, File::RDWR|File::CREAT|File::EXCL, 0600).close rescue return false
      true
    end

    def unlock()
      lockfile = "#{PasswdLockDir}/#{@uid}"
      File::unlink lockfile
    end

  end
end
