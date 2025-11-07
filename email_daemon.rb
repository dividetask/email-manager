#!/usr/bin/env ruby
require_relative 'utils'
require_relative 'email'
require_relative 'database'

class EmailDaemon
  attr_reader :config_obj, :log_obj, :data_obj, :imap_obj, :check_interval
  
  def initialize(config_path)
    @config_obj = Config.new(config_path)
    @log_obj = Utils.create_logger(@config_obj.log_path, true)
    @data_obj = Database.new(@config_obj.database_path)
    @imap_obj = EmailHandler.new(@config_obj, @log_obj)
    @check_interval = @config_obj.check_interval || 3600
    @running = false
  end
  
  def start
    @running = true
    @log_obj.info "Email daemon started. Checking every #{@check_interval} seconds"
    
    while @running
      process_inbox
      sleep(@check_interval)
    end
  end
  
  def stop
    @running = false
    @imap_obj.disconnect
    @log_obj.info "Email daemon stopped"
  end
  
  def process_inbox
    @log_obj.info "Processing INBOX..."
    @imap_obj.ensure_connected
    @imap_obj.imap_obj.select('INBOX')
    
    uids = @imap_obj.search_folder('INBOX')
    @log_obj.info "Found #{uids.length} emails in INBOX"
    
    moved_count = 0
    uids.each_slice(100) do |uid_batch|
      begin
        fetch_data = @imap_obj.imap_obj.uid_fetch(uid_batch, 'ENVELOPE')
        fetch_data.each do |data|
          uid = data.attr['UID']
          envelope = data.attr['ENVELOPE']
          from_addr = @imap_obj.extract_email_from_envelope(envelope)[:email]
          
          target_folder = get_target_folder(from_addr)
          if target_folder
            move_email(uid, target_folder)
            moved_count += 1
          end
        end
      rescue => e
        @log_obj.error "Error processing batch: #{e.message}"
      end
    end
    
    @log_obj.info "Moved #{moved_count} emails"
  rescue => e
    @log_obj.error "Error processing inbox: #{e.message}"
  end
  
  def get_target_folder(email_address)
    #@log_obj.debug "Table name: #{EmailAddress.table_name}"
    #@log_obj.debug "Database keys: #{@data_obj.data.keys.inspect}"

    all_emails = EmailAddress.get_record_list(@data_obj)
    #@log_obj.debug "All email records: #{all_emails.inspect}"

    email_record = EmailAddress.find(@data_obj, address: email_address)
    #@log_obj.debug "Looking for email: #{email_address}, found: #{email_record.inspect}"
    return nil unless email_record
    
    contact = Contact.find(@data_obj, uid: email_record[:contact_id])
    #@log_obj.debug "Found contact: #{contact.inspect}"
    return nil unless contact
    
    contact[:auto_folder]
  end
  
  def move_email(uid, target_folder)
    @imap_obj.imap_obj.uid_copy(uid, target_folder)
    @imap_obj.imap_obj.uid_store(uid, "+FLAGS", [:Deleted])
    @log_obj.info "Moved email UID #{uid} to #{target_folder}"
  rescue => e
    @log_obj.error "Failed to move email UID #{uid}: #{e.message}"
  end
end

if __FILE__ == $0
  config_path = ARGV[0] || 'config.yml'
  daemon = EmailDaemon.new(config_path)
  
  trap('INT') { daemon.stop; exit }
  trap('TERM') { daemon.stop; exit }
  
  daemon.start
end
