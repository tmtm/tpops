# $Id: tpops_auth-passwd.rb,v 1.5 2002/03/21 06:00:06 tommy Exp $

require 'etc'

class TPOPS
  class Auth

    PasswdLockDir = '/var/tmp/tpops' unless defined? PasswdLockDir

    def Auth::apop?()
      defined? APOPPasswdFile
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
	apophash = BDB::Hash::open(APOPPasswdFile, nil, 'r')
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

    attr_reader :login, :uid, :maildir

    def lock()
      lockfile = "#{PasswdLockDir}/#{@uid}"
      Dir::mkdir PasswdLockDir, 0700 unless File::exists? PasswdLockDir
      if File::exists? lockfile then
	if Time::now - File::stat(lockfile).mtime > ConnectionKeepTime then
	  File::unlink lockfile
	else
	  return false
	end
      end
      File::open(lockfile, File::RDWR|File::CREAT|File::EXCL, 0600).close rescue return false
      true
    end

    def unlock()
      lockfile = "#{PasswdLockDir}/#{@uid}"
      File::unlink lockfile
    end

  end
end
