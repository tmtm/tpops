# $Id: tpops_mailbox-maildir.rb,v 1.5 2002/04/21 05:25:33 tommy Exp $

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
      [maildir+'cur', maildir+'new'].each do |path|
	next unless File::directory? path
	Dir::foreach(path) do |f|
	  if f =~ /^(\d+)\./ then
	    mtime = $1.to_i
	    p = path+'/'+f
	    if MaildirExtended and f =~ /,S=(\d+)/ then
	      size = $1.to_i
	    else
	      if MaildirUseFileSize then
		s = File::stat(p)
		size = s.size
	      else
		r = File::open(p) do |f| f.read end
		size = r.gsub(/\n/, "\r\n").size
	      end
	    end
	    files << FileStat::new(p, size, mtime)
	  end
	end
      end
      @files = files.sort do |a, b|
	a.mtime <=> b.mtime
      end
      @files.each_index do |i|
	@files[i].no = i+1
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
      if not iterator? then
	r = File::open(@files[msg-1].name) do |f| f.read end
	if r[-1,1] != "\n" then line << "\n" end
	r.gsub!(/(^|[^\r])\n/, "\\1\r\n")
	r
      end
      File::open(@files[msg-1].name) do |f|
	f.each do |line|
	  if line[-1,1] != "\n" then line << "\n" end
	  line.gsub!(/(^|[^\r])\n/, "\\1\r\n")
	  yield line
	end
      end
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
      ret = ''
      File::open(@files[msg-1].name) do |f|
	f.each do |line|
	  break if line =~ /^\r?$/
	  if line[-1,1] != "\n" then line << "\n" end
	  line.gsub!(/(^|[^\r])\n/, "\\1\r\n")
	  if iterator? then
	    yield line
	  else
	    ret << line
	  end
	end
	yield "\r\n"
	f.each do |line|
	  break if lines <= 0
	  if line[-1,1] != "\n" then line << "\n" end
	  line.gsub!(/(^|[^\r])\n/, "\\1\r\n")
	  if iterator? then
	    yield line
	  else
	    ret << line
	  end
	  lines -= 1
	end
      end
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
