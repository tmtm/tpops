# $Id: log.rb,v 1.1 2005/07/06 13:22:09 tommy Exp $
#
# Copyright (C) 2003-2005 TOMITA Masahiro
# tommy@tmtm.org
#

require "syslog"

class Log
  def self.open(facility, debug=false)
    if Syslog.opened? then
      Syslog.reopen(File.basename($0), nil, facility)
    else
      Syslog.open(File.basename($0), nil, facility)
    end
    @debug = debug
  end

  def self.close()
    Syslog.close if Syslog.opened?
  end

  def self.log(pri, str)
    Syslog.log(pri, "%s", str) if Syslog.opened?
  end

  def self.debug(str)
    self.log(Syslog::LOG_DEBUG, str) if @debug
  end

  def self.info(str)
    self.log(Syslog::LOG_INFO, str)
  end

  def self.notice(str)
    self.log(Syslog::LOG_NOTICE, str)
  end

  def self.warn(str)
    self.log(Syslog::LOG_WARNING, str)
  end

  def self.err(str)
    self.log(Syslog::LOG_ERR, str)
  end
end
