# $Id: mailbox-maildir.rb,v 1.18 2006/01/26 11:43:00 tommy Exp $
#
# Copyright (C) 2003-2004 TOMITA Masahiro
# tommy@tmtm.org
#

$options.update({
  "maildir-use-filesize"	=> [/^(yes|no)$/i, "yes"],
  "maildir-extended"		=> [/^(yes|no)$/i, "yes"],
  "maildir-lock"		=> [/^(yes|no)$/i, "yes"],
  "maildir-uidl-convert"	=> [/^(yes|no)$/i, "no"],
})

require "lock"

class TPOPS
  class MailboxMaildir
    class FileStat
      def initialize(name, size, mtime)
        @name, @size, @mtime = name, size, mtime
        @deleted = false
        @seen = false
        @info = ""
        @in_new = nil
      end
      attr_reader :name, :size, :mtime
      attr_accessor :seen, :info, :in_new
      def deleted?() @deleted end
      def delete() @deleted = true end
      def undelete() @deleted = false end

      def real_delete()
        begin
          File.unlink @name
          @deleted = :real_delete
        rescue Errno::ENOENT
          # do nothing
        rescue
          log_err "delete failed: #{@name}: #{$!}"
        end
      end
    end

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

    def read_maildir(dir, in_new=false)
      ret = []
      Dir.foreach(dir) do |f|
        if f =~ /^(\d+)\./ then
          mtime = $1.to_i
          p = "#{dir}/#{f}"
          if TPOPS.conf["maildir-extended"] == "yes" and f =~ /,S=(\d+)/ then
            size = $1.to_i
          elsif TPOPS.conf["maildir-use-filesize"] == "yes" then
            s = File.stat(p)
            size = s.size
          else
            r = File.open(p) do |f| f.read end
            size = r.size + r.count("\n")	# "\n" -> "\r\n"
          end
          file = FileStat.new(p, size, mtime)
          file.info = p =~ /:2,(\w+)$/ ? $1 : ""
          file.in_new = in_new
          ret << file
        end
      end
      ret
    end

    public
    def initialize(maildir, auth=nil)
      @files = {}
      return unless File.exist? maildir
      begin
        begin
          @lock = Lock.new("#{maildir}/tpops_lock", TPOPS.conf["hostname"]) if TPOPS.conf["maildir-lock"] == "yes"
        rescue Errno::EEXIST
          raise TPOPS::Error, "cannot lock"
        end
        files = []
        files.concat read_maildir("#{maildir}/cur", false) if File.exist? "#{maildir}/cur"
        files.concat read_maildir("#{maildir}/new", true) if File.exist? "#{maildir}/new"
        files.sort! do |a, b|
          r = a.mtime <=> b.mtime
          if r == 0 then
            r = File.basename(a.name) <=> File.basename(b.name)
          end
          r
        end
        files.each_index do |i|
          @files[i+1] = files[i]
        end
        @uidl_conv = {}
        if TPOPS.conf["maildir-uidl-convert"] == "yes" and File.exist? "#{maildir}/tpops_uidl" then
          begin
            File.open("#{maildir}/tpops_uidl") do |f|
              f.each do |l|
                fname, uid = l.chomp.split(/\t/,2)
                @uidl_conv[fname] = uid
              end
            end
          rescue Errno::ENOENT
          end
        end
      rescue
        unlock
        raise
      end
    end

    def unlock()
      @lock.unlock if @lock
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
        f.seen = false
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
          uid = File.basename(@files[m].name).split(/:/)[0]
          ret << [m, @uidl_conv[uid] || uid]
        end
      end
      ret
    end

    def uidl(msg)
      if not exist? msg then return nil end
      uid = File.basename(@files[msg].name).split(/:/)[0]
      [msg, @uidl_conv[uid] || uid]
    end

    def last()
      n = 0
      @files.keys.each do |m|
        n = [n, m].max if @files[m].info.include? "S" or @files[m].seen
      end
      n
    end

    def commit()
      @files.values.each do |f|
        begin
          if f.deleted? then
            f.real_delete
          elsif f.in_new then
            if f.seen then
              a = f.name.split(/\/+/)
              a[-2] = "cur" if a[-2] == "new"
              dest = a.join("/")+":2,S"
              File.rename(f.name, dest)
            end
          elsif f.seen and not f.info.include? "S" then
            f.info = (f.info + "S").split(//).sort.join
            File.rename(f.name, f.name.split(/:/)[0]+":2,"+f.info)
          end
        rescue Errno::ENOENT
          # do nothing
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
