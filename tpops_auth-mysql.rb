# $Id: tpops_auth-mysql.rb,v 1.1 2002/02/06 17:58:02 tommy Exp $

require 'mysql'
require 'md5'

class TPOPS
  class Auth

    MySQLAuthQuery = 'select login,passwd,uid,maildir from user where login="%s"' unless defined? MySQLAuthQuery

    def Auth::apop?()
      true
    end

    def initialize(user, pass, apop=nil)
      m = Mysql::new(MySQL_Server, MySQL_User, MySQL_Pass, MySQL_DB)
      res = m.query(sprintf(MySQLAuthQuery, m.quote user))
      m.close
      return if res.num_rows == 0
      login, pw, uid, maildir = res.fetch_row
      if not apop then
	return unless pass == pw
      else
	return unless pass == MD5::new(apop+pw).hexdigest
      end
      @login, @uid, @maildir = login, uid, maildir
      @authorized = true
    end

    def authorized?()
      @authorized
    end

    attr_reader :login, :uid, :maildir

    def lock()
      m = Mysql::new(MySQL_Server, MySQL_User, MySQL_Pass, MySQL_DB)
      begin
	m.query("insert ignore into locks (uid) values ('#{@uid}')")
	if m.affected_rows == 0 then
	  return false
	end
      ensure
	m.close
      end
      true
    end

    def unlock()
      m = Mysql::new(MySQL_Server, MySQL_User, MySQL_Pass, MySQL_DB)
      m.query("delete from locks where uid='#{@uid}'")
      m.close
    end

  end
end
