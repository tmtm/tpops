# $Id: thread.rb,v 1.1 2005/07/06 13:22:09 tommy Exp $
#
# Copyright (C) 2003-2005 TOMITA Masahiro
# tommy@tmtm.org
#

$options.update({
  "max-servers"		=> [true, 50],
})

class Log
  def self.log(pri, str)
    return unless Syslog.opened?
    tid = Thread.current[:cnt]
    if tid then
      Syslog.log(pri, "[%d] %s", tid, str)
    else
      Syslog.log(pri, "%s", str)
    end
  end
end

class TPOPS
  class Thread
    @@children = []

    def initialize(*args)
      @sock = TCPServer.new(*args)
      @cnt = 0
    end

    def close()
      @sock.close
    end

    def start()
      @sock.listen [TPOPS.conf["max-servers"].to_i, 5].max
      @flag = :in_loop
      while @flag == :in_loop do
        @@children.delete_if do |t|
          if t.alive? then
            false
          else
            begin
              t.join
            rescue
              Log.err "[#{t[:cnt]}] #{$!}"
            end
            true
          end
        end
        if @@children.size >= TPOPS.conf["max-servers"].to_i then
          sleep 1
          next
        end
        next unless IO.select([@sock], nil, nil, 1)
        begin
          s = @sock.accept
        rescue Errno::ECONNABORTED, Errno::ECONNREFUSED, Errno::ECONNRESET
          next
        end
        break if @flag != :in_loop
        @cnt += 1
        tid = ::Thread.new(s, @cnt) do |s2, c|
          ::Thread.current[:cnt] = c
          yield s2
          s2.close unless s2.closed?
        end
        @@children << tid
      end
      @flag = :out_of_loop
    end

    def stop()
      @flag = :exit_loop
    end

    def interrupt()
      # do nothing
    end
  end
end

TPOPS.add_parallel_class "thread", TPOPS::Thread
