# $Id: tpops_sub.rb,v 1.4 2001/08/01 00:39:22 tommy Exp $

require 'md5'
require 'mysql'

class TPOPS

  def mycon()
    Mysql::new(MySQL_Server, MySQL_User, MySQL_Pass, MySQL_DB)
  end

  def auth(user, pass)
    m = mycon
    res = m.query(sprintf(AuthQuery, m.quote user))
    if res.num_rows != 1 then
      return false
    end
    uid, p = res.fetch_row
    if pass != p then
      return false
    end
    @uid = uid.to_i
    m.close
    return true
  end

  def apop_auth(user, key)
    m = mycon
    res = m.query(sprintf(AuthQuery, m.quote user))
    if res.num_rows != 1 then
      return false
    end
    uid, pass = res.fetch_row
    @uid = uid.to_i
    m.close
    MD5::new(@apopkey+pass).hexdigest == key
  end

  def reset_msgno()
    m = mycon
    res = m.query("select id from msg where uid='#{@uid}' order by timestamp, id")
    c = 1
    res.each do |id,|
      m.query("update msg set msgno='#{c}' where id='#{id}'")
      c += 1
    end
    m.close
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
    m = mycon
    res = m.query("select count(*), sum(size) from msg where uid='#{@uid}' and msgno > 0")
    msgs, size = res.fetch_row
    m.close
    return msgs.to_i, size.to_i
  end

  def exist?(msg, col='id', m=nil)
    if msg <= 0 then
      return nil
    end
    m0 = m || mycon
    res = m0.query("select #{col} from msg where uid='#{@uid}' and msgno='#{msg}'")
    m0.close if not m
    res.fetch_row
  end

  def list_all()
    m = mycon
    res = m.query("select msgno, size from msg where uid='#{@uid}' and msgno > 0 order by msgno")
    ret = []
    res.each do |nn, mm|
      ret << [nn.to_i, mm.to_i]
    end
    m.close
    ret
  end

  def list(msg)
    nn, mm = exist? msg, 'msgno, size'
    if nn == nil then return nil end
    return nn.to_i, mm.to_i
  end

  def retr(msg)
    h, b = exist? msg, 'header, body'
    if h == nil then return nil end
    h.gsub(/\n/, "\r\n") + "\r\n" + b.gsub(/\n/, "\r\n")
  end

  def dele(msg)
    m = mycon
    begin
      id, = exist? msg, 'id', m
      if id == nil then return nil end
      m.query("update msg set msgno=-msgno where id='#{id}'")
    ensure
      m.close
    end
    true
  end

  def rset()
    m = mycon
    m.query("update msg set msgno=-msgno where uid='#{@uid}' and msgno < 0")
    m.close
  end

  def top(msg, lines)
    h, b = exist? msg, 'header, body'
    if h == nil then return nil end
    h.gsub(/\n/, "\r\n") + "\r\n" + b.split(/^/)[0,lines].join.gsub(/\n/, "\r\n")
  end

  def uidl_all()
    m = mycon
    res = m.query("select msgno, concat(id, '.', uid, '.', timestamp + 0) from msg where uid='#{@uid}' and msgno > 0 order by msgno")
    ret = []
    res.each do |msg, id|
      ret << [msg.to_i, id]
    end
    m.close
    ret
  end

  def uidl(msg)
    m, id = exist? msg, "msgno, concat(id, '.', uid, '.', timestamp + 0)"
    if m == nil then return nil end
    return m, id
  end

  def commit()
    m = mycon
    m.query("delete from msg where uid='#{@uid}' and msgno < 0")
    m.close
  end

end
