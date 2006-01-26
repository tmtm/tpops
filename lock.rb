# $Id: lock.rb,v 1.1 2006/01/26 11:10:50 tommy Exp $
#
# Copyright (C) 2003-2006 TOMITA Masahiro
# tommy@tmtm.org
#

class Lock
  def initialize(lockfile, hostid="1", timeout=10)
    Log.debug "Lock: #{lockfile}"
    @lockf = nil
    @lockfiles = nil
    cnt = 0
    newlockfile = "#{lockfile}.#{hostid}.#{$$}"
    Log.debug "Lock: newlockfile: #{newlockfile}"
    if File.exist? newlockfile then
      Log.debug "Lock: already exist: #{newlockfile}"
      raise Errno::EDEADLK, newlockfile
    end
    begin
      @lockf = File.open(lockfile, File::WRONLY|File::CREAT)
      unless @lockf.flock(File::LOCK_EX|File::LOCK_NB) then
        Log.debug "Lock: already locked: #{lockfile}"
        raise Errno::EEXIST, lockfile
      end
      File.link lockfile, newlockfile
      nst = File.stat(newlockfile)
      st = File.stat(lockfile)
      if nst.nlink != 2 or st.nlink != 2 or nst.ino != st.ino then
        Log.debug "Lock: cannot lock: #{lockfile}: newlink=#{nst.nlink} link=#{st.nlink} newino=#{nst.ino} ino=#{st.ino}"
        raise Errno::EEXIST, lockfile
      end
      Log.debug "Lock: success: #{lockfile}"
      @lockfiles = [lockfile, newlockfile]
      return
    rescue Errno::ENOENT, Errno::EEXIST
      @lockf.close
      File.unlink newlockfile rescue nil
      Log.debug "Lock: retry_cnt #{cnt}"
      cnt += 1
      raise Errno::EEXIST, "cannot lock: #{lockfile}" if cnt > timeout
      cleanup lockfile, hostid
      sleep 1
      Log.debug "Lock: retry: #{lockfile}"
      retry
    rescue => e
      Log.error "Lock: unknown error occured: #{e.class}: #{e.message}: #{e.backtrace.inspect}"
      File.unlink newlockfile rescue nil
      raise
    ensure
      if @lockfiles.nil? then
        @lockf.close rescue nil
      end
    end
  end

  def unlock()
    File.unlink @lockfiles[0]
    File.unlink @lockfiles[1]
    @lockf.close
    @lockf = @lockfiles = nil
  end

  private
  def cleanup(lockfile, hostid)
    Log.debug "Lock#cleanup: #{lockfile}, #{hostid}"
    Dir.glob("#{lockfile}.#{hostid}.*") do |fn|
      begin
        f = File.open(fn, File::WRONLY)
        if f.flock(File::LOCK_EX|File::LOCK_NB) then
          Log.debug "Lock: unlink #{fn}"
          File.unlink fn
        end
        f.close
      rescue => e
        Log.debug "Lock: error: #{e.class}: #{e.message}: #{e.backtrace.inspect}"
      end
    end
  end
end
