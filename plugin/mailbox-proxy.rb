# $Id: mailbox-proxy.rb,v 1.1 2006/01/26 09:15:10 tommy Exp $
#
# Copyright (C) 2003-2006 TOMITA Masahiro
# tommy@tmtm.org
#

$options.update({
  "pop-server"	=> [/.:\d+$/, "localhost:10110"],
})

class TPOPS
  class MailboxProxy
    private
    def wait_ok()
      loop do
        r = @sock.gets
        if r == nil then
          log_err "server connection closed"
          throw :disconnect
        end
        r.chomp!
        if r =~ /^\+OK/ then return r[4..-1] end
        if r =~ /^-NG/ then raise TPOPS::Error, r[4..-1] end
        raise TPOPS::Error, r
      end
    end

    def wait_p(&block)
      ret = ''
      loop do
        r = @sock.gets
        if r == nil then
          Log.warn "disconnected by server"
          throw :disconnect
        end
        if r == ".\r\n" then return ret end
        r[0,2] = '.' if r[0,2] == '..'
        if block then
          block.call r
        else
          ret << r
        end
      end
      ret
    end

    public
    def initialize(maildir, auth)
      @sock = TCPSocket.new *TPOPS.conf["pop-server"].split(/:/,2)
      wait_ok
      @sock.puts "USER #{auth.login}"
      wait_ok
      @sock.puts "PASS #{auth.passwd}"
      wait_ok
    end

    def unlock()
      # do nothing
    end

    def stat()
      @sock.puts "STAT\r\n"
      msgs, size = wait_ok.strip.split
      @stat = [msgs.to_i, size.to_i]
    end

    def list_all()
      ret = []
      @sock.puts "LIST\r\n"
      wait_ok
      wait_p.each do |r| ret << r.strip.split end
      ret
    end

    def list(msg)
      if not exist? msg then return nil end
      @sock.puts "LIST #{msg}\r\n"
      return wait_ok.strip.split
    end

    def retr(msg, &block)
      @sock.puts "RETR #{msg}\r\n"
      wait_ok
      wait_p block
    end

    def dele(msg)
      @sock.puts "DELE #{msg}\r\n"
      wait_ok
    end

    def rset()
      @sock.puts "RSET\r\n"
      wait_ok
    end

    def top(msg, lines, &block)
      @sock.puts "TOP #{msg} #{lines}\r\n"
      wait_ok
      wait_p block
    end

    def uidl_all()
      @sock.puts "UIDL\r\n"
      wait_ok 
      wait_p.each do |r| ret << r.strip.split end
    end

    def uidl(msg)
      @sock.puts "UIDL #{msg}\r\n"
      return wait_ok.strip.split
    end

    def last()
      @sock.puts "LAST\r\n"
      return wait_ok.strip.to_i
    end

    def commit()
      stat
      @sock.puts "QUIT\r\n"
      wait_ok
    end

    def real_stat()
      return @stat
    end
  end
end

TPOPS.add_mailbox_class "proxy",TPOPS::MailboxProxy
