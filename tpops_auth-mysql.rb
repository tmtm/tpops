# $Id: tpops_auth-mysql.rb,v 1.5 2003/04/19 04:52:00 tommy Exp $

require 'mysql'
require 'md5'

class TPOPS
  class Auth

    @@my = nil
    $mysql_auth_query = 'select login,passwd,uid,maildir from user where login="%s"' unless defined? $mysql_auth_query

    def Auth::apop?()
      true
    end

    def my()
      if @@my == nil then
	@@my = Mysql::new($mysql_server, $mysql_user, $mysql_pass, $mysql_db)
      end
      @@my
    end

    def initialize(user, pass, apop=nil)
      if $mysql_auth_query.is_a? Array
	queries = $mysql_auth_query
      else
	queries = [$mysql_auth_query]
      end
      res = nil
      queries.each do |qu|
	res = my.query(sprintf(qu, my.quote user))
	break if res.num_rows > 0
	res = nil
      end
      return unless res
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

    def locked?()
      @locked
    end

    attr_reader :login, :uid, :maildir

    def lock()
      my.query("delete from locks where unix_timestamp(now())-unix_timestamp(timestamp)>#{$connection_keep_time}")
      pid, host = my.query("select pid,host from locks where uid='#{my.quote @uid}'").fetch_row
      if pid and host == $hostname then
	begin
	  Process::kill 0, pid.to_i
	  return false
	rescue Errno::ESRCH
	  my.query("delete from locks where uid='#{my.quote @uid}'")
	rescue
	  return false
	end
      end

      my.query("insert ignore into locks (uid,pid,host) values ('#{my.quote @uid}','#{$$}','#{my.quote $hostname}')")
      if my.affected_rows == 0 then
	return false
      end
      @locked = true
      true
    end

    def unlock()
      my.query("delete from locks where uid='#{my.quote @uid}'")
      @locked = false
    end

  end
end
