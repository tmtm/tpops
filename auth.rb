require 'md5'
require 'mysql'

MySQL_Server = 'localhost'
MySQL_User = 'root'
MySQL_Pass = 'fuga'
MySQL_DB = 'tpops'

class TPOPS

  def mycon()
    Mysql::new(MySQL_Server, MySQL_User, MySQL_Pass, MySQL_DB)
  end

  def auth(user, pass)
    m = mycon
    res = m.query("select uid from user where login='#{m.quote user}' and passwd='#{m.quote pass}'")
    if res.num_rows != 1 then
      return false
    end
    @uid = res.fetch_row[0].to_i
    m.close
    return true
  end

  def apop_auth(user, key)
    m = mycon
    res = m.query("select uid, passwd from user where login='#{m.quote user}'")
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
    res = m.query("select id from msg where uid='#{@uid}' order by timestamp")
    c = 1
    res.each do |id,|
      m.query("update msg set msgno='#{c}' where id='#{id}'")
      c += 1
    end
    m.close
  end

  def stat()
    m = mycon
    res = m.query("select count(*), sum(length(header)+length(body)) from msg where uid='#{@uid}'")
    nn, mm = res.fetch_row
    m.close
    [nn.to_i, mm.to_i]
  end

  def list_all()
    m = mycon
    res = m.query("select msgno, length(header)+length(body) from msg where uid='#{@uid}'")
    ret = []
    res.each do |nn, mm|
      ret << [nn.to_i, mm.to_i]
    end
    m.close
    ret
  end

  def list(msg)
    m = mycon
    res = m.query("select msgno, length(header)+length(body) from msg where uid='#{@uid}' and msgno='#{msg}'")
    nn, mm = res.fetch_row
    m.close
    [nn.to_i, mm.to_i]
  end

  def exist?(msg)
    m = mycon
    res = m.query("select id from msg where uid='#{@uid}' and msgno='#{msg}'")
    m.close
    res.num_rows > 0
  end

end
