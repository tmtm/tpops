# $Id: mailbox-maildir.rb,v 1.5 2004/06/10 13:25:37 tommy Exp $

$options.update({
  "maildir-use-filesize"	=> [/^(yes|no)$/i, "yes"],
  "maildir-extended"		=> [/^(yes|no)$/i, "yes"],
  "maildir-lock"		=> [/^(yes|no)$/i, "yes"],
})

class TPOPS

  class FileStat
    def initialize(name, size, mtime)
      @name, @size, @mtime = name, size, mtime
      @deleted = false
      @seen = false
    end
    attr_reader :name, :size, :mtime, :seen
    attr_writer :seen
    def deleted?() @deleted end
    def delete() @deleted = true end
    def undelete() @deleted = false end

    def real_delete()
      begin
        File.unlink @name
        @deleted = :real_delete
      rescue
        log_err "delete failed: #{@name}: #{$!}"
      end
    end
  end

  class MailboxMaildir
    private
    def exist?(msg)
      if not @files.key? msg then return nil end
      if @files[msg].deleted? then return nil end
      true
    end

    def normalize_line(line)
      if line[-1] != ?\n then line << "\n" end
      if line[-2] != ?\r then line[-1,0] = "\r" end
    end

    public
    def initialize(maildir)
      lock(maildir)
      if File.directory? "#{maildir}/new" then
        Dir.foreach("#{maildir}/new") do |f|
          if f =~ /^(\d+)\./ then
            File.rename("#{maildir}/new/#{f}", "#{maildir}/cur/#{File.basename(f)}:2,")
          end
        end
      end
      files = []
      if File.directory? "#{maildir}/cur" then
	Dir.foreach("#{maildir}/cur") do |f|
	  if f =~ /^(\d+)\./ then
	    mtime = $1.to_i
	    p = "#{maildir}/cur/#{f}"
	    if $conf["maildir-extended"] == "yes" and f =~ /,S=(\d+)/ then
	      size = $1.to_i
	    elsif $conf["maildir-use-filesize"] == "yes" then
              s = File.stat(p)
              size = s.size
            else
              r = File.open(p) do |f| f.read end
              size = r.gsub(/\n/, "\r\n").size
	    end
	    files << FileStat.new(p, size, mtime)
	  end
	end
      end
      files.sort! do |a, b|
	a.mtime <=> b.mtime
      end
      @files = {}
      files.each_index do |i|
        @files[i+1] = files[i]
      end
    end

    def self.unlock(f, f2)
      proc do
        File.rename f2, f rescue nil
      end
    end

    def lock(maildir)
      return if $conf["maildir-lock"] == "no"
      f = "#{maildir}/tpops_lock"
      f2 = "#{f}.#{$$}.#{Time.now.to_i.to_s}"
      begin
        File.rename f, f2
        ObjectSpace.define_finalizer(self, self.class.unlock(f, f2))
        @lock = f
        @lock2 = f2
      rescue Errno::ENOENT
        ff = Dir.glob(f+".*")
        if ff.empty? then
          File.open(f, File::WRONLY|File::CREAT|File::EXCL, 0600).close rescue nil
          retry
        end
        Dir.glob(f+".*") do |i|
          if i.split(/\./)[-1].to_i < Time.now.to_i-$conf["connection-keep-time"] then
            log_notice "#{i}: lock is released"
            File.rename i, f rescue nil
            retry
          end
        end
        raise TPOPS::Error, "cannot lock"
      end
    end

    def unlock()
      return if $conf["maildir-lock"] == "no"
      File.rename @lock2, @lock rescue nil
      ObjectSpace.undefine_finalizer(self)
    end

    def stat()
      cnt = 0
      size = 0
      @files.values.each do |f|
	if not f.deleted? then
	  size += f.size
	  cnt += 1
	end
      end
      [cnt, size]
    end

    def list_all()
      ret = []
      @files.keys.sort.each do |m|
	if not @files[m].deleted? then
	  ret << [m, @files[m].size]
	end
      end
      ret
    end

    def list(msg)
      if not exist? msg then return nil end
      [msg, @files[msg].size]
    end

    def retr(msg)
      if not exist? msg then return nil end
      if not iterator? then
        r = File.open(@files[msg].name) do |f| f.read end
        if r[-1] != ?\n then r << "\n" end
        r.gsub!(/(^|[^\r])\n/o, "\\1\r\n")
        @files[msg].seen = true
        return r
      end
      File.open(@files[msg].name) do |f|
        f.each do |line|
          normalize_line line
          yield line
        end
      end
      @files[msg].seen = true
    end

    def dele(msg)
      if not exist? msg then return nil end
      @files[msg].delete
      true
    end

    def rset()
      @files.values.each do |f|
	f.undelete
      end
    end

    def top(msg, lines)
      if not exist? msg then return nil end
      ret = ''
      File.open(@files[msg].name) do |f|
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
      @files.keys.sort.each do |m|
	if not @files[m].deleted? then
	  ret << [m, File.basename(@files[m].name).split(/:/)[0]]
	end
      end
      ret
    end

    def uidl(msg)
      if not exist? msg then return nil end
      [msg, File.basename(@files[msg].name).split(/:/)[0]]
    end

    def commit()
      @files.values.each do |f|
	if f.deleted? then
          f.real_delete
        elsif f.seen then
          info = f.name =~ /:2,(\w+)$/ ? $1 : ""
          unless info.include? "S" then
            info << "S"
            info = info.split(//).sort.join
            File.rename(f.name, f.name.split(/:/)[0]+":2,"+info)
          end
        end
      end
    end

    def real_stat()
      cnt = 0
      size = 0
      @files.values.each do |f|
	if f.deleted? != :real_delete then
	  size += f.size
	  cnt += 1
	end
      end
      [cnt, size]
    end
  end
end

TPOPS.add_mailbox_class "maildir",TPOPS::MailboxMaildir
