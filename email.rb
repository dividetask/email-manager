require 'net/imap'
require 'mail'
require 'logger'
require 'fileutils'

DEFAULT_FOLDER = "INBOX/Unsorted"

class EmailHandler
  attr_reader :imap_obj, :config_obj, :log_obj

  def initialize(config_obj, log_obj); @imap_obj = nil; @config_obj = config_obj; @log_obj = log_obj; end
  def ensure_connected; connect unless @imap_obj; end
  def search_folder(folder_name = 'INBOX'); ensure_connected; @imap_obj.examine(folder_name); @imap_obj.uid_search(['ALL']); end
  def extract_email_from_envelope(envelope); from = envelope.from[0]; { email: "#{from.mailbox}@#{from.host}", name: from.name }; end
  def expunge; ensure_connected; @imap_obj.expunge; end

  def disconnect
    return unless @imap_obj
    begin
      @imap_obj.logout
      @imap_obj.disconnect
    rescue => e
      @log_obj.error "Error during disconnect: #{e.message}"
    end
    @imap_obj = nil  # Important: set to nil so ensure_connected works
    @log_obj.info "Disconnected from server"
  end

  def connect
    @log_obj.info "Connecting to #{@config_obj.host}:#{@config_obj.port}"
    @imap_obj = Net::IMAP.new(@config_obj.host, port: @config_obj.port, ssl: @config_obj.use_ssl)
    @imap_obj.login(@config_obj.username, @config_obj.password)
    @log_obj.info "Connected"
  end

  def safe_folder_operation(folder, operation_name)
    begin
      yield
    rescue => e
      @log_obj.error "Error #{operation_name} folder '#{folder}': #{e.message}"
      nil
    end
  end

  def get_all_folders
    ensure_connected
    @log_obj.info "Fetching folders"
    folder_obj_list = @imap_obj.list("", "*")
    return [] if folder_obj_list.nil? || folder_obj_list.empty?
    folder_name_list = folder_obj_list.map { |folder| folder.name }
    @log_obj.info "Found #{folder_name_list.length} folders"
    folder_name_list
  end

  def get_all_uids
    ensure_connected
    folders = get_all_folders
    all_uids = {}
    folders.each do |folder|
      uids = safe_folder_operation(folder, "reading") { search_folder(folder) }
      all_uids[folder] = uids || []
      @log_obj.info "Folder '#{folder}': #{all_uids[folder].length} emails"
    end
    all_uids
  end

  def get_email_addresses_from_folder(folder = 'INBOX')
    ensure_connected
    uids = search_folder(folder)
    return [] if uids.empty?

    @log_obj.info "Fetching envelopes for #{uids.length} emails in batches"
    addresses = []
    uids.each_slice(100) do |uid_batch|
      begin
        fetch_data = @imap_obj.uid_fetch(uid_batch, 'ENVELOPE')
        fetch_data.each do |data|
          envelope = data.attr['ENVELOPE']
          addresses << extract_email_from_envelope(envelope)
        end
      rescue => e
        @log_obj.error "Error fetching batch: #{e.message}"
      end
    end

    addresses.compact.uniq { |a| a[:email] }
  end
  
  def move_email(uid, target_folder)
    @imap_obj.uid_copy(uid, target_folder)
    @imap_obj.uid_store(uid, "+FLAGS", [:Deleted])
    @log_obj.info "Moved email UID #{uid} to #{target_folder}"
  rescue => e
    @log_obj.error "Failed to move email UID #{uid}: #{e.message}"
  end
end
