#!/usr/bin/env ruby

require_relative 'download'
require_relative 'database'
require_relative 'config'
require 'logger'

class EmailDaemon
  def initialize(config_path)
    @config = Config.new(config_path)
    @logger = @config.create_logger
    @logger.level = Logger::INFO
    
    @database = EmailDatabase.new(@config.database_path, logger: @logger)
    @downloader = EmailDownloader.new(@config.email, logger: @logger)
    @storage_dir = @config.email_storage_dir
    @check_interval = @config.check_interval
    @running = false
  end

  def start
    @running = true
    @logger.info "Email daemon starting... Will check every #{@check_interval} seconds"
    sync_emails
    
    while @running
      sleep(@check_interval)
      sync_emails if @running
    end
  end

  def stop
    @running = false
    puts "Email daemon stopping..." if @logger
    begin
      @downloader.disconnect
    rescue
      # Ignore errors during shutdown
    end
  end

  def sync_emails
    @logger.info "Starting email sync at #{Time.now}"
    
    begin
      already_downloaded = @database.get_all_uids
      new_emails = @downloader.download_new_emails(already_downloaded, @storage_dir)
      added_count = @database.add_emails(new_emails)
      @logger.info "Sync complete: #{added_count} new emails added"
      
      stats = @database.stats
      @logger.info "Database stats: #{stats[:total_emails]} total emails"
      @downloader.disconnect
      
    rescue => e
      @logger.error "Error during sync: #{e.message}"
      @logger.error e.backtrace.join("\n")
    end
  end
end

if __FILE__ == $0
  config_path = ARGV[0] || 'config.yml'
  
  daemon = EmailDaemon.new(config_path)
  
  ['INT', 'TERM'].each do |signal|
    trap(signal) do
      daemon.instance_variable_set(:@running, false)
      puts "\nReceived #{signal} signal, shutting down gracefully... (press Ctrl+C again to force quit)"
      exit
    end
  end

  daemon.start

  # Clean disconnect after main loop exits
  daemon.stop
end
