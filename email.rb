require 'net/imap'
require 'mail'
require 'logger'
require 'fileutils'

DEFAULT_FOLDER = "INBOX/Unsorted"

class Common
  attr_reader :config_obj, :log_obj, :data_obj
  def log_info message; @log_obj.info message; end
  def error message; @log_obj.error message; end

  def initialize(config_path)
    @config_obj = Config.new(config_path)
    @log_obj = Utils.create_logger(@config_obj.log_path, true)
    @data_obj = Database.new(@config_obj.database_path)
  end
end

class EmailDaemon
  attr_reader :common_obj, :email_sorter, :check_interval, :running, :shutdown_requested, :test_run_once
  def stop; @running = false; end
  def request_shutdown; @common_obj.log_info "Shutdown requested..."; @shutdown_requested = true; end

  def initialize(common_obj, params = {})
  	@common_obj = common_obj
    @email_sorter = EmailSorter.new(@common_obj)
    @check_interval = params[:overwrite_check_interval] || @common_obj.config_obj.check_interval || 3600
    @running = false
    @shutdown_requested = false
    @test_run_once = (params[:test_run_once] == true)
  end

  def start(&task)
    raise ArgumentError, "No task block provided" unless block_given?

    @running = true
    @common_obj.log_info "Daemon started. Running task every #{@check_interval} seconds"

    while @running && !@shutdown_requested
      begin
        task.call
      rescue => e
        @common_obj.error "Error running task: #{e.message}"
      end

      @common_obj.log_info "Sleeping for #{@check_interval} seconds"
      break if @test_run_once
      sleep(@check_interval)
    end

    @common_obj.log_info "Daemon stopped gracefully"
  end
end

class EmailSorter
  attr_reader :common_obj, :email_repo, :recognized_emails
  def initialize(common_obj); @common_obj = common_obj; @email_repo = EmailRepository.new(common_obj); end
  def get_responded_to_emails; @email_repo.fetch_sent_recipients; end
  def cleanup; @email_repo.disconnect; end
  def connect; @email_repo.connect; end
  
  def get_all_addresses_sent_to
    uids = @email_repo.handler.get_uids_by_folder('Sent')

    all_recipients = []
    uids.each_slice(100) do |uid_batch|
      envelopes = @email_repo.handler.fetch_envelopes(uid_batch)
      envelopes.each do |env|
        all_recipients.concat(env[:to]) if env[:to]
      end
    end

    all_recipients.flatten.map(&:downcase).uniq
  end

  def process_folder folder, max_emails = nil
    @common_obj.log_info "Processing #{folder}..."

    @recognized_emails = get_all_addresses_sent_to
    @common_obj.log_info "Found #{@recognized_emails.length} email addresses sent to"
    
    emails = @email_repo.fetch_emails folder
    @common_obj.log_info "Found #{emails.length} emails"
    
    moved_count = 0
    emails.each_with_index do |email, index|
      target_folder = determine_target_folder(email[:from])
      
      if target_folder && target_folder != folder
        @email_repo.move_email(email[:uid], target_folder)
        moved_count += 1
      end

      if max_emails && max_emails >= moved_count
        @common_obj.log_info "Exiting early, max emails reached (#{max_emails})"
        break
      end
      
      @common_obj.log_info "Progress #{index + 1}/#{emails.length}" if (index + 1) % 10 == 0
    end
    
    @email_repo.expunge
    @common_obj.log_info "Moved #{moved_count} emails"
  rescue => e
    @common_obj.error "Error processing inbox: #{e.message}"
  end
  
  private
  
  def determine_target_folder(email_address)
  	default_folder = (@recognized_emails.include? email_address) ? 'INBOX' : DEFAULT_FOLDER
    email_record = EmailAddress.find(@common_obj.data_obj, address: email_address)
    return default_folder unless email_record

    contact = Contact.find(@common_obj.data_obj, uid: email_record.contact_id)
    return default_folder unless contact

    contact.auto_folder
  end
end

class EmailRepository
  attr_reader :common_obj, :handler
  def initialize(common_obj); @common_obj = common_obj; @handler = EmailHandler.new(@common_obj); end
  def move_email(uid, target_folder); @handler.move_email(uid, target_folder); end
  def expunge; @handler.expunge; end
  def disconnect; @handler.disconnect; end
  def connect; @handler.connect; end
  def delete(folder, uid); @handler.select_folder(folder); @handler.move_email(uid, 'Trash'); end

  def fetch_emails folder
    @handler.ensure_connected
    @handler.select_folder(folder)

    uids = @handler.search_all
    fetch_emails_by_uids(uids)
  end

  def find_duplicates(folder_list)
    all_emails = {}
    duplicates = {}

    folder_list.each do |folder|
      @handler.ensure_connected
      @handler.select_folder(folder)
      
      uids = @handler.search_all
      
      uids.each_slice(100) do |uid_batch|
        envelopes = @handler.fetch_envelopes(uid_batch)
        envelopes.each do |env|
          if all_emails[env[:message_id]]
            duplicates[env[:message_id]] = [all_emails[env[:message_id]]] unless duplicates[env[:message_id]]
            duplicates[env[:message_id]] << { uid: env[:uid], folder: folder, from: env[:from], subject: env[:subject] }
          else
            all_emails[env[:message_id]] = { uid: env[:uid], folder: folder, from: env[:from], subject: env[:subject] }
          end
        end
      end
    end
    
    duplicates
  end

  def fetch_sent_recipients
    @handler.ensure_connected
    @handler.select_folder('Sent')

    uids = @handler.search_all
    recipients = []

    uids.each_slice(100) do |uid_batch|
      envelopes = @handler.fetch_envelopes(uid_batch)
      envelopes.each do |envelope|
        if envelope[:to]
          recipients.concat(envelope[:to])
        end
      end
    end

    recipients.uniq
  end

  private

  def fetch_emails_by_uids(uids)
    emails = []

    uids.each_slice(100) do |uid_batch|
      begin
        envelopes = @handler.fetch_envelopes(uid_batch)
        envelopes.each do |env|
          emails << {
            uid: env[:uid],
            from: env[:from],
            to: env[:to],
            subject: env[:subject]
          }
        end
      rescue => e
        @common_obj.error "Error fetching batch: #{e.message}"
      end
    end

    emails
  end
end

class EmailHandler
  attr_reader :imap_obj, :common_obj
  def initialize(common_obj); @common_obj = common_obj; @imap_obj = nil; end
  def ensure_connected; connect unless @imap_obj; end
  def select_folder(folder); ensure_connected; @imap_obj.select(folder); end
  def search_all; @imap_obj.uid_search(['ALL']); end
  def expunge; @imap_obj.expunge; end
  def list_folders; ensure_connected; folder_list = @imap_obj.list("", "*"); return [] unless folder_list; folder_list.map(&:name); end
  def get_uids_by_folder(folder); select_folder(folder); search_all; end
  
  def connect
    @common_obj.log_info "Connecting to #{@common_obj.config_obj.host}:#{@common_obj.config_obj.port}"
    @imap_obj = Net::IMAP.new(
      @common_obj.config_obj.host,
      port: @common_obj.config_obj.port,
      ssl: @common_obj.config_obj.use_ssl
    )
    @imap_obj.login(@common_obj.config_obj.username, @common_obj.config_obj.password)
    @common_obj.log_info "Connected"
  end
  
  def disconnect
    return unless @imap_obj
    
    @imap_obj.logout
    @imap_obj.disconnect
    @imap_obj = nil
    @common_obj.log_info "Disconnected"
  rescue => e
    @common_obj.error "Error during disconnect: #{e.message}"
  end
  
  def fetch_envelopes(uids)
    fetch_data = @imap_obj.uid_fetch(uids, 'ENVELOPE')
    
    fetch_data.map do |data|
      envelope = data.attr['ENVELOPE']
      {
        uid: data.attr['UID'],
        from: extract_address(envelope.from&.first),
        name: extract_name(envelope.from&.first),
        to: extract_addresses(envelope.to),
        subject: envelope.subject,
        message_id: envelope.message_id
      }
    end
  end
  
  def move_email(uid, target_folder)
    @imap_obj.uid_copy(uid, target_folder)
    @imap_obj.uid_store(uid, "+FLAGS", [:Deleted])
    @common_obj.log_info "Moved UID #{uid} to #{target_folder}"
  rescue => e
    @common_obj.error "Failed to move UID #{uid}: #{e.message}"
  end
  
  private
  
  def extract_address(address_obj); return nil unless address_obj; "#{address_obj.mailbox}@#{address_obj.host}"; end
  def extract_addresses(address_list); return [] unless address_list; address_list.map { |addr| extract_address(addr) }.compact; end
  def extract_name(address_obj); return nil unless address_obj; address_obj.name; end
end

