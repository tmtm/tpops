# $Id: auth-passwd.rb,v 1.4 2004/06/10 11:20:22 tommy Exp $

require 'etc'

$options.update({
  "apop-passwd-file"	=> true,
  "maildir"		=> [true, "Maildir"],
})

class TPOPS
  class AuthPasswd

    def self.apop?()
      $conf["apop-passwd-file"] and not $conf["apop-passwd-file"].empty?
    end

    def self.reset()
    end

    def initialize(user, pass, apop=nil)
      begin
	pw = Etc.getpwnam user
      rescue ArgumentError
        raise TPOPS::Error, "authentication failed"
      end
      @login, @maildir = pw.name, pw.dir+"/"+$conf["maildir"]+"/"
      if apop then
        require 'dbm'
	require 'md5'
        dbm = DBM.open($conf["apop-passwd-file"], nil)
        if dbm == nil then
          log_warn("DBM: #{$conf["apop-passwd-file"]}: open failed")
          raise TPOPS::Error, "authentication failed"
        end
	pw = dbm[@login]
        dbm.close
        if pw == nil or pass != MD5.new(apop+pw).hexdigest then
          raise TPOPS::Error, "authentication failed"
        end
	return
      else
	if pw.passwd == 'x' then
          IO.foreach("/etc/shadow") do |line|
            shuser, shpw = line.split(/:/)
            if shuser == @login then
              if shpw.length > 1 and pass.crypt(shpw) == shpw then
                return
              end
              raise TPOPS::Error, "authentication failed"
            end
          end
        elsif pass.crypt(pw.passwd) == pw.passwd then
          return
	end
        raise TPOPS::Error, "authentication failed"
      end
    end

    attr_reader :login, :maildir

  end
end

TPOPS.add_auth_class "passwd", TPOPS::AuthPasswd