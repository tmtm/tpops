# $Id: tpops_maildir.rb,v 1.5 2001/07/16 09:38:47 tommy Exp $

require 'md5'
require 'mysql'

class TPOPS

  class Files
    def initialize(name, size, mtime=0)
      @name, @size, @mtime = name, size, mtime
    end
    attr_reader :name, :size, :mtime
  end

  def mycon()
    Mysql::new(MySQL_Server, MySQL_User, MySQL_Pass, MySQL_DB)
  end

  def auth(user, pass)
    m = mycon
    res = m.query("select uid, maildir from user where login='#{m.quote user}' and passwd='#{m.quote pass}'")
    if res.num_rows != 1 then
      return false
    end
    uid, @maildir = res.fetch_row
    @uid = uid.to_i
    m.close
    return true
  end

  def apop_auth(user, key)
    m = mycon
    res = m.query("select uid, passwd, maildir from user where login='#{m.quote user}'")
    if res.num_rows != 1 then
      return false
    end
    uid, pass, @maildir = res.fetch_row
    @uid = uid.to_i
    m.close
    MD5::new(@apopkey+pass).hexdigest == key
  end

  def reset_msgno()
    @deleted = []
    files = []
    [@maildir+'/cur', @maildir+'/new'].each do |path|
      Dir::foreach(path) do |f|
	if f !~ /^\./ then
	  p = path+'/'+f
	  s = File::stat(p)
	  size = s.size
	  if not MaildirCRLF then
	    r = File::open(p) do |f| f.read end
	    size = r.gsub(/\n/, "\r\n").size
	  end
	  files << Files::new(p, size, s.mtime.to_i)
	end
      end
    end
    @files = files.sort do |a, b|
      a.mtime <=> b.mtime
    end
  end

  def lock()
    m = mycon
    begin
      m.query("insert ignore into locks (uid) values ('#{@uid}')")
      if m.affected_rows == 0 then
	return false
      end
    ensure
      m.close
    end
    true
  end

  def unlock()
    m = mycon
    m.query("delete from locks where uid='#{@uid}'")
    m.close
  end

  def stat()
    size = 0
    @files.each_index do |i|
      if not @deleted.include? i+1 then
	size += @files[i].size
      end
    end
    [@files.size, size]
  end

  def exist?(msg)
    if @deleted.include? msg then return nil end
    if @files.size < msg then return nil end
    true
  end

  def list_all()
    ret = []
    @files.each_index do |i|
      if not @deleted.include? i+1 then
	ret << [i+1, @files[i].size]
      end
    end
    ret
  end

  def list(msg)
    if not exist? msg then return nil end
    [msg, @files[msg-1].size]
  end

  def retr(msg)
    if not exist? msg then return nil end
    r = File::open(@files[msg-1].name) do |f| f.read end
    if not MaildirCRLF then
      r.gsub!(/\n/, "\r\n")
    end
    r
  end

  def dele(msg)
    if not exist? msg then return nil end
    @deleted << msg
    true
  end

  def rset()
    @deleted = []
  end

  def top(msg, lines)
    if not exist? msg then return nil end
    r = File::open(@files[msg-1].name) do |f| f.read end
    if not MaildirCRLF then
      r.gsub!(/\n/, "\r\n")
    end
    if r =~ /\r\n\r\n/ then
      h = $` + "\r\n"	#`
      b = $'		#'
    else
      h = r
      b = ''
    end
    h + "\r\n" + b.split(/^/)[0,lines].join
  end

  def uidl_all()
    ret = []
    @files.each_index do |i|
      if not @deleted.include? i+1 then
	ret << [i+1, File::basename(@files[i].name).split(/:/)[0]]
      end
    end
    ret
  end

  def uidl(msg)
    if not exist? msg then return nil end
    [msg, File::basename(@files[msg-1].name).split(/:/)[0]]
  end

  def commit()
    @deleted.each do |i|
      f = @files[i-1].name
      File::unlink f
    end
  end

end
