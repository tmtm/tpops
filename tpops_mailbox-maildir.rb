# $Id: tpops_mailbox-maildir.rb,v 1.1 2002/02/06 17:58:02 tommy Exp $

class TPOPS

  class FileStat
    def initialize(name, size, mtime)
      @name, @size, @mtime = name, size, mtime
      @deleted = false
    end
    attr_reader :no, :name, :size, :mtime
    attr_writer :no
    def deleted?() @deleted end
    def delete() @deleted = true end
    def undelete() @deleted = false end
  end

  class Mailbox
    private
    def exist?(msg)
      if msg <= 0 then return nil end
      if @files.size < msg then return nil end
      if @files[msg-1].deleted? then return nil end
      true
    end

    public
    def initialize(uid, maildir)
      files = []
      [maildir+'/cur', maildir+'/new'].each do |path|
	Dir::foreach(path) do |f|
	  if f !~ /^\./ then
	    p = path+'/'+f
	    s = File::stat(p)
	    size = s.size
	    if not MaildirCRLF then
	      r = File::open(p) do |f| f.read end
	      size = r.gsub(/\n/, "\r\n").size
	    end
	    files << FileStat::new(p, size, s.mtime.to_i)
	  end
	end
      end
      @files = files.sort do |a, b|
	a.mtime <=> b.mtime
      end
      @files.each_index do |i|
	f.no = i+1
      end
    end

    def stat()
      cnt = 0
      size = 0
      @files.each do |f|
	if not f.deleted? then
	  size += f.size
	  cnt += 1
	end
      end
      [cnt, size]
    end

    def list_all()
      ret = []
      @files.each do |f|
	if not f.deleted? then
	  ret << [f.no, f.size]
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
      @files[msg-1].delete
      true
    end

    def rset()
      @files.each do |f|
	f.undelete
      end
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
      @files.each do |f|
	if not f.deleted? then
	  ret << [f.no, File::basename(f.name).split(/:/)[0]]
	end
      end
      ret
    end

    def uidl(msg)
      if not exist? msg then return nil end
      [msg, File::basename(@files[msg-1].name).split(/:/)[0]]
    end

    def commit()
      @files.each do |f|
	if f.deleted? then
	  File::unlink f.name
	end
      end
    end
  end

end
