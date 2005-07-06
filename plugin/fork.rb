# $Id: fork.rb,v 1.1 2005/07/06 13:22:09 tommy Exp $
#
# Copyright (C) 2003-2005 TOMITA Masahiro
# tommy@tmtm.org
#

$options.update({
  "max-servers"		=> [true, 50],
})

class TPOPS
  class Fork
    @@children = []

    def initialize(*args)
      @sock = TCPServer.new(*args)
    end

    def close()
      @sock.close
    end

    def start()
      @sock.listen [TPOPS.conf["max-servers"].to_i, 5].max
      @flag = :in_loop
      while @flag == :in_loop do
        @@children.delete_if do |p|
          begin
            Process.waitpid(p, Process::WNOHANG)
          rescue Errno::ECHILD
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
        pid = fork do
          @sock.close
          trap :HUP, "EXIT"
          trap :TERM, "EXIT"
          trap :INT, "EXIT"
          Process.gid = TPOPS.gid if TPOPS.gid
          Process.uid = TPOPS.uid if TPOPS.uid
          Process.euid = TPOPS.uid if TPOPS.uid
          yield s
          s.close unless s.closed?
        end
        @@children << pid
        s.close
      end
      @flag = :out_of_loop
    end

    def stop()
      @flag = :exit_loop
    end

    def interrupt()
      Process.kill "TERM", *@@children rescue nil
    end
  end
end

TPOPS.add_parallel_class "fork", TPOPS::Fork
