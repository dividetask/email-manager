require 'net/imap'
require 'mail'
require 'logger'
require 'fileutils'


class EmailHandler
  attr_reader :imap_obj, :config_obj, :log_obj

  def initialize(config_obj, log_obj); @imap_obj = nil; @config_obj = config_obj; @log_obj = log_obj; end
  def disconnect; return unless @imap_obj; @imap_obj.logout; @imap_obj.disconnect; @log_obj.info "Disconnected from server"; end
  def search_folder(folder_name = 'INBOX'); connect unless @imap_obj; @imap_obj.examine(folder_name); @imap_obj.uid_search(['ALL']); end

  def connect
    @log_obj.info "Connecting to #{@config_obj.host}:#{@config_obj.port}"
    @imap_obj = Net::IMAP.new(@config_obj.host, port: @config_obj.port, ssl: @config_obj.use_ssl)
    @imap_obj.login(@config_obj.username, @config_obj.password)
    @log_obj.info "Connected"
  end

  def get_all_folders
    connect unless @imap_obj
    @log_obj.info "Fetching folders"
    folder_obj_list = @imap_obj.list("", "*")
    return [] if folder_obj_list.nil? || folder_obj_list.empty?
    folder_name_list = folder_obj_list.map { |folder| folder.name }
    @log_obj.info "Found #{folder_name_list.length} folders"
    folder_name_list
  end

  def get_all_uids
    connect unless @imap_obj
    folders = get_all_folders
    all_uids = {}
    folders.each do |folder|
      begin
        uids = search_folder(folder)
        all_uids[folder] = uids
        @log_obj.info "Folder '#{folder}': #{uids.length} emails"
      rescue => e
        @log_obj.error "Error reading folder '#{folder}': #{e.message}"
        all_uids[folder] = []
      end
    end
    all_uids
  end
end
