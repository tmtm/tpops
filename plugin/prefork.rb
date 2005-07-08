# $Id: prefork.rb,v 1.2 2005/07/08 07:44:32 tommy Exp $
#
# Copyright (C) 2003-2005 TOMITA Masahiro
# tommy@tmtm.org
#

require "prefork"

$options.update({
  "min-servers"		=> [true, 5],
  "max-servers"		=> [true, 50],
  "max-use"		=> [true, 100],
  "max-idle"		=> [true, 100],
})

class TPOPS
  class PreFork < ::PreFork
    def initialize(*args)
      super
      on_child_start do
        trap :HUP, "EXIT"
        trap :TERM, "EXIT"
        trap :INT, "EXIT"
        begin
          if TPOPS.uid then
            File.chown(TPOPS.uid, nil, @lockf)
            Process.uid = TPOPS.uid
            Process.euid = TPOPS.uid
          end
          Process.gid = TPOPS.gid if TPOPS.gid
        rescue
          Log.err "setuid/setgid #{$!}"
          sleep 5
          raise
        end
      end
    end

    def start()
      PreFork.logging = TPOPS.conf["debug"] ? (Syslog.opened? ? :syslog : true) : nil
      @min_servers = TPOPS.conf["min-servers"].to_i
      @max_servers = TPOPS.conf["max-servers"].to_i
      @max_use = TPOPS.conf["max-use"].to_i
      @max_idle = TPOPS.conf["max-idle"].to_i
      socks.each do |s|
        s.listen [@max_servers, 5].max
      end
      super
    end
  end
end

TPOPS.add_parallel_class "prefork", TPOPS::PreFork
