# $Id: tpops_maildir.rb,v 1.1 2001/06/29 05:40:53 tommy Exp $

require 'md5'
require 'mysql'

class TPOPS

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
    path = @maildir+'/cur'
    Dir::foreach(path) do |f|
      if f !~ /^\./ then
	p = path+'/'+f
	s = File::stat(p)
	files << [p, s.size, s.mtime]
      end
    end
    path = @maildir+'/new'
    Dir::foreach(path) do |f|
      if f !~ /^\./ then
	p = path+'/'+f
	s = File::stat(p)
	files << [p, s.size, s.mtime]
      end
    end
    files.sort do |a, b|
      a[2] <=> b[2]
    end
    @files = files
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
    @files.each do |f|
      size += f[1]
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
	ret << [i+1, @files[i][1]]
      end
    end
    ret
  end

  def list(msg)
    if not exist? msg then return nil end
    [msg, @files[msg-1][1]]
  end

  def retr(msg)
    if not exist? msg then return nil end
    File::open(@files[msg-1][0]) do |f| f.read end
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
    r = File::open(@files[msg-1][0]) do |f| f.read end
    if r =~ /\r?\n(?=\r?\n)/ then
      h = $` + $&	#`
      b = $'		#'
    else
      h = r
      b = ''
    end
    h + b.split(/^/)[0,lines].join
  end

  def uidl_all()
    ret = []
    @files.each_index do |i|
      if not @deleted.include? i+1 then
	ret << [i+1, File::basename(@files[i][0]).split(/:/)[0]]
      end
    end
    ret
  end

  def uidl(msg)
    if not exist? msg then return nil end
    [msg, File::basename(@files[msg-1][0]).split(/:/)[0]]
  end

  def commit()
    @deleted.each do |i|
      f = @files[i-1][0]
      File::rename f, File::dirname(f)+'/.'+File::basename(f)
    end
  end

end
