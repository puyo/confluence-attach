#!/usr/bin/env ruby
#
# Confluence attach script.
#
# Examples:
#   attach x.png x.svg
#       Attaches x.png and x.svg files to a Confluence page.

require 'rubygems'
gem 'escape', '>=0.0.4'
gem 'sqlite3-ruby', '>=1.2.2'

require 'escape'
require 'optparse'
require 'ostruct'

module Confluence

  def self.attach_cli
    options = OpenStruct.new :url => nil, :page_id => nil, :noop => false, :verbose => false

    parser = OptionParser.new do |parser|
      parser.on("-c", "--confluence CONFLUENCE_URL", 
          "Confluence URL.") do |arg|
        options.url = arg
      end
      parser.on("-p", "--page PAGEID",
          "Confluence page upload destination",
          "(edit page and copy from browser address)") do |arg|
        if not arg.match(/^\d+/)
          raise ArgumentError.new("Page ID should be a positive integer")
        end
        options.page_id = arg.to_i
      end
      parser.on("-v", "--verbose", "Display more feedback.") do
        options.verbose = true
      end
      parser.on("-n", "--noop", "Don't actually do anything. Just print",
          "what commands would be run.") do
        options.noop = true
      end
      parser.separator("")
      parser.separator("Examples:")
      parser.separator("  #{parser.program_name} x.png x.svg")
      parser.separator("    Attaches x.png and x.svg files to a Confluence page.")
    end

    begin
      parser.parse!
      if options.url.nil?
        raise "You must specify confluence's URL."
      end
      if options.page_id.nil?
        raise "You must specify a page ID to upload to."
      end
      if ARGV.empty?
        raise "You must specify a file to attach."
      end
      attach_curl(options.url, options.page_id, options.noop, options.verbose, ARGV)
    rescue RuntimeError => e
      $stderr.puts "ERROR: #{e}"
      $stderr.puts
      $stderr.puts parser
      exit 2
    end
  end

  private

  def self.attach_curl(url, page_id, noop, verbose, files)
    if curl_version.nil?
      raise "This program relies on the 'curl' program which is not installed. Aborting."
    end

    begin
      cookie_args = firefox3_cookie_args('%confluence%') 
    rescue RuntimeError => e
      $stderr.puts e
      cookie_args = firefox2_cookie_args
    end

    cmd = []
    cmd << 'curl' << '-v' << '--insecure'
    cmd += cookie_args

    count = 0
    for file in files
      if File.exists?(file)
        cmd << '-F' << "file_#{count}=@#{file}"
        cmd << '-F' << "comment_#{count}=Inkscape" if File.extname(file) == ".svg"
        count += 1
      end
    end

    cmd << '-F' << "confirm=Attach Files(s)"
    cmd << "#{url}/pages/doattachfile.action?pageId=#{page_id}"

    escaped = Escape.shell_command(cmd)
    puts escaped
    if noop
      puts "No-op mode"
      exit 0
    else
      result = `(#{escaped} 2>&1)`
      puts result if verbose
      if $?.exitstatus != 0
        $stderr.puts "\n!!! Failed to upload (curl error #{$?.exitstatus})"
        exit $?.exitstatus
      elsif result.match(/\<\ Location:.*login\.action;jsessionid=/)
        $stderr.puts "\n!!! Failed to upload (not authenticated)"
        exit 26
      else
        puts
        puts "Uploaded successfully"
        exit 0
      end
    end
  end

  def self.curl_version
    v = `curl --version`.strip
    if v != ""
      v.match(/^curl (\d+)\.(\d+)\.(\d+)/).captures
    else
      nil
    end
  end

  def self.profiles_home
    case RUBY_PLATFORM
    when /darwin/, /osx/, /mac/
      "#{ENV['HOME']}/Library/Application Support/Firefox/Profiles/*.default"
    when /linux/
      "#{ENV['HOME']}/.mozilla/firefox/*.default"
    else
      raise "Unrecognised/unsupported platform '#{RUBY_PLATFORM}'"
    end
  end

  def self.firefox3_cookie_args(like_host)
    require 'sqlite3'

    cookie_glob = "#{profiles_home}/cookies.sqlite"
    cookie_file = Dir.glob(cookie_glob).first or raise("Cannot find Firefox 3 cookie file #{cookie_glob}")
    db = SQLite3::Database.new(cookie_file)
    cookies = []
    db.execute("select name, value from moz_cookies where host like ?", like_host) do |row|
      name, value = row[0], row[1]
      cookies << [name, value]
    end
    ['--cookie', cookies.map{|k,v| "#{k}=#{v}" }.join(';')]
  end

  def self.firefox2_cookie_args
    cookie_glob = "#{profiles_home}/cookies.txt"
    cookie_file = Dir.glob(cookie_glob).first or raise("Cannot find Firefox 2 cookie file #{cookie_glob}")
    ['--cookie', cookie_file]
  end
end

if $0 == __FILE__
  Confluence.attach_cli
end
