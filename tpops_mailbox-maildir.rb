# $Id: tpops_mailbox-maildir.rb,v 1.12 2004/06/08 04:10:52 tommy Exp $

$options.update({
  "maildir-use-filesize"	=> nil,
  "maildir-extended"		=> true,
})

class TPOPS

  $maildir_use_filesize = true unless defined? $maildir_use_filesize
  $maildir_extended = true unless defined? $maildir_extended

  class FileStat
    def initialize(name, size, mtime)
      @name, @size, @mtime = name, size, mtime
      @deleted = false
    end
    attr_reader :no, :name, :size, :mtime, :deleted
    attr_writer :no
    def deleted?() @deleted end
    def delete() @deleted = true end
    def undelete() @deleted = false end

    def real_delete()
      File::unlink @name
      @deleted = :real_delete
    end
  end

  class Mailbox
    private
    def exist?(msg)
      if msg <= 0 then return nil end
      if @files.size < msg then return nil end
      if @files[msg-1].deleted? then return nil end
      true
    end

    def normalize_line(line)
      if line[-1] != ?\n then line << "\n" end
      if line[-2] != ?\r then line[-1,0] = "\r" end
    end

    public
    def initialize(uid, maildir)
      files = []
      [maildir+'/cur', maildir+'/new'].each do |path|
	begin
	  File::stat(path)
	rescue Errno::ENOENT
	  next
	end
	Dir::foreach(path) do |f|
	  if f =~ /^(\d+)\./ then
	    mtime = $1.to_i
	    p = path+'/'+f
	    if $maildir_extended and f =~ /,S=(\d+)/ then
	      size = $1.to_i
	    else
	      if $maildir_use_filesize then
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
	if r[-1] != ?\n then r << "\n" end
	r.gsub!(/(^|[^\r])\n/o, "\\1\r\n")
	return r
      end
      File::open(@files[msg-1].name) do |f|
	f.each do |line|
	  normalize_line line
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
	  normalize_line line
	  if iterator? then
	    yield line
	  else
	    ret << line
	  end
	end
	if iterator? then
	  yield "\r\n"
	else
	  ret << "\r\n"
	end
	f.each do |line|
	  break if lines <= 0
	  normalize_line line
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
          f.real_delete
	end
      end
    end

    def real_stat()
      cnt = 0
      size = 0
      @files.each do |f|
	if f.deleted != :real_delete then
	  size += f.size
	  cnt += 1
	end
      end
      [cnt, size]
    end
  end
end
