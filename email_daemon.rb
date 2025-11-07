#!/usr/bin/env ruby
require_relative 'utils'
require_relative 'email'
require_relative 'database'

class EmailDaemon
  attr_reader :config_obj, :log_obj, :data_obj, :imap_obj, :check_interval, :running, :shutdown_requested
  
  def initialize(config_path)
    @config_obj = Config.new(config_path)
    @log_obj = Utils.create_logger(@config_obj.log_path, true)
    @data_obj = Database.new(@config_obj.database_path)
    @imap_obj = EmailHandler.new(@config_obj, @log_obj)
    @check_interval = @config_obj.check_interval || 3600
    @running = false
    @shutdown_requested = false
  end
  
  def start
    @running = true
    @log_obj.info "Email daemon started. Checking every #{@check_interval} seconds"
    
    while @running && !@shutdown_requested
      process_inbox
      @log_obj.info "Sleeping for #{@check_interval} seconds"
      sleep(@check_interval)
    end

    @imap_obj.disconnect
    @log_obj.info "Email daemon stopped gracefully"
  end

  def request_shutdown
    @log_obj.info "Shutdown requested, will stop after current batch..."
    @shutdown_requested = true
  end
  
  def stop
    @running = false
  end
  
  def process_inbox
  	current_folder = 'INBOX'
    @log_obj.info "Processing #{current_folder}..."
    @imap_obj.ensure_connected
    @imap_obj.imap_obj.select(current_folder)
    
    #uids = @imap_obj.search_folder(current_folder)
    uids = @imap_obj.imap_obj.uid_search(['ALL'])
    @log_obj.info "Found #{uids.length} emails in #{current_folder}"
    
    moved_count = 0
    uids[0..200].each_slice(100) do |uid_batch|
      begin
        fetch_data = @imap_obj.imap_obj.uid_fetch(uid_batch, 'ENVELOPE')
        fetch_data.each do |data|
          uid = data.attr['UID']
          envelope = data.attr['ENVELOPE']
          from_addr = @imap_obj.extract_email_from_envelope(envelope)[:email]
          
          target_folder = get_target_folder(from_addr)
          if target_folder and target_folder != current_folder
            @imap_obj.move_email(uid, target_folder)
            moved_count += 1
          end
          @log_obj.info "Email progress #{moved_count}/#{uids.length}" if moved_count % 10 == 0
        end
      rescue => e
        @log_obj.error "Error processing batch: #{e.message}"
      end
    end
    @log_obj.info "**** Expunging ******"
    @imap_obj.imap_obj.expunge

    @log_obj.info "Moved #{moved_count} emails"
  rescue => e
    @log_obj.error "Error processing #{current_folder}: #{e.message}"
  end
  
  def get_target_folder(email_address)
    all_emails = EmailAddress.get_record_list(@data_obj)

    email_record = EmailAddress.find(@data_obj, address: email_address)
    return DEFAULT_FOLDER unless email_record
    
    contact = Contact.find(@data_obj, uid: email_record[:contact_id])
    return DEFAULT_FOLDER unless contact
    
    contact[:auto_folder]
  end
end

if __FILE__ == $0
  config_path = ARGV[0] || 'config.yml'
  daemon = EmailDaemon.new(config_path)
  
  trap('INT') { daemon.request_shutdown; exit }
  trap('TERM') { daemon.request_shutdown; exit }
  
  daemon.start
end
