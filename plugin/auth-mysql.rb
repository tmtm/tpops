# $Id: auth-mysql.rb,v 1.5 2004/06/10 17:14:04 tommy Exp $

require 'md5'

$options.update({
  "mysql-server"	=> true,
  "mysql-user"		=> true,
  "mysql-passwd"	=> true,
  "mysql-db"		=> true,
  "mysql-auth-query"	=> [true, "select login,passwd,maildir from user where login=\"%s\""],
})

class TPOPS
  class AuthMysql

    @@my = nil

    def self.apop?()
      true
    end

    def self.reset()
      @@my.close
      @@my = nil
    end

    def my()
      require 'mysql'
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
      raise TPOPS::Error, "authentication failed" unless res
      login, pw, maildir = res.fetch_row
      if apop and pass != MD5.new(apop+pw).hexdigest or not apop and pass != pw then
        raise TPOPS::Error, "authentication failed"
      end
      @login, @maildir = login, maildir
    end

    attr_reader :login, :maildir

  end
end

TPOPS.add_auth_class "mysql", TPOPS::AuthMysql
