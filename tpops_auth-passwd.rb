# $Id: tpops_auth-passwd.rb,v 1.1 2002/02/06 17:58:02 tommy Exp $

require 'etc'

class TPOPS
  class Auth

    def Auth::apop?()
      false
    end

    def initialize(user, pass, apop=nil)
      begin
	pw = Etc::getpwnam user
      rescue ArgumentError
	return
      end
      @login, @uid, @maildir = pw.name, pw.uid, pw.dir+'/Maildir/'
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

    def authorized?()
      @authorized
    end

    attr_reader :login, :uid, :maildir
  end
end
