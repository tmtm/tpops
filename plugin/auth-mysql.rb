# $Id: auth-mysql.rb,v 1.9 2005/07/22 01:57:04 tommy Exp $

require 'md5'

$options.update({
  "mysql-server"	=> true,
  "mysql-user"		=> true,
  "mysql-passwd"	=> true,
  "mysql-db"		=> true,
  "mysql-auth-query"	=> [true, "select login,passwd,maildir from user where login=\"%s\""],
  "mysql-crypt-passwd"	=> [/^(yes|no|crypt|sha)$/i, "no"],
})

class TPOPS
  class AuthMysql

    @@my = nil

    def self.apop?()
      return TPOPS.conf["mysql-crypt-passwd"] == "no"
    end

    def self.reset()
      @@my.close if @@my
      @@my = nil
    end

    def my()
      require 'mysql'
      if @@my == nil then
	@@my = Mysql.new(TPOPS.conf["mysql-server"], TPOPS.conf["mysql-user"], TPOPS.conf["mysql-passwd"], TPOPS.conf["mysql-db"])
      end
      @@my
    end

    def initialize(user, pass, apop=nil)
      queries = [TPOPS.conf["mysql-auth-query"]]
      res = nil
      queries.each do |qu|
        qu = qu.gsub(/%([%sud])/) do
          case $1
          when "%" then "%"
          when "s" then user
          when "u" then user.split(/@/)[0]
          when "d" then user.include? "@" ? user.split(/@/,2)[1] : ""
          end
        end
	res = my.query(qu)
	break if res.num_rows > 0
	res = nil
      end
      raise TPOPS::Error, "authentication failed" unless res
      login, pw, maildir = res.fetch_row
      if apop then
        if pass != MD5.new(apop+pw).hexdigest then
          raise TPOPS::Error, "authentication failed"
        end
      elsif TPOPS.conf["mysql-crypt-passwd"] == "no" then
        if pass != pw then
          raise TPOPS::Error, "authentication failed"
        end
      else
        case TPOPS.conf["mysql-crypt-passwd"]
        when "crypt"
          if pass.crypt(pw) != pw then
            raise TPOPS::Error, "authentication failed"
          end
        when "sha"
          require "digest/sha1"
          if [Digest::SHA1.digest(pass)].pack("m").chomp != pw.sub(/^\{SHA\}/,"") then
            raise TPOPS::Error, "authentication failed"
          end
        else
          require "digest/sha1"
          if pass.crypt(pw) != pw and [Digest::SHA1.digest(pass)].pack("m").chomp != pw.sub(/^\{SHA\}/,"") then
            raise TPOPS::Error, "authentication failed"
          end
        end
      end
      @login, @maildir = login, maildir
    end

    attr_reader :login, :maildir

  end
end

TPOPS.add_auth_class "mysql", TPOPS::AuthMysql
