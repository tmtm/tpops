# $Id: auth-mysql.rb,v 1.1 2004/06/09 15:10:23 tommy Exp $

require 'mysql'
require 'md5'

$options.update({
  "mysql-server"	=> true,
  "mysql-user"		=> true,
  "mysql-passwd"	=> true,
  "mysql-db"		=> true,
  "mysql-auth-query"	=> [true, "select login,passwd,uid,maildir from user where login=\"%s\""],
})

class TPOPS
  class Auth

    @@my = nil

    def self.apop?()
      true
    end

    def self.reset()
      @@my.close
      @@my = nil
    end

    def my()
      if @@my == nil then
	@@my = Mysql.new($conf["mysql-server"], $conf["mysql-user"], $conf["mysql-passwd"], $conf["mysql-db"])
      end
      @@my
    end

    def initialize(user, pass, apop=nil)
      queries = [$conf["mysql-auth-query"]]
      res = nil
      queries.each do |qu|
	res = my.query(sprintf(qu, my.quote(user)))
	break if res.num_rows > 0
	res = nil
      end
      return unless res
      login, pw, uid, maildir = res.fetch_row
      if not apop then
	return unless pass == pw
      else
	return unless pass == MD5.new(apop+pw).hexdigest
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
      my.query("delete from locks where unix_timestamp(now())-unix_timestamp(timestamp)>#{$conf["connection-keep-time"]}")
      pid, host = my.query("select pid,host from locks where uid='#{my.quote @uid}'").fetch_row
      if pid and host == $conf["hostname"] then
	begin
	  Process.kill 0, pid.to_i
	  return false
	rescue Errno::ESRCH
	  my.query("delete from locks where uid='#{my.quote @uid}'")
	rescue
	  return false
	end
      end

      my.query("insert ignore into locks (uid,pid,host) values ('#{my.quote @uid}','#{$$}','#{my.quote $conf["hostname"]}')")
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
