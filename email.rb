require 'net/imap'
require 'mail'
require 'logger'
require 'fileutils'

class EmailDownloader
  attr_reader :imap, :config_data, :logger

  def initialize(config_path, log_path)
    @imap = nil
    @config_data = Config.new(config_path)
    @logger = Utils.create_logger(log_path)
  end

  def connect
    @logger.info "Connecting to #{@config_data.host}:#{@config_data.port}"
    @imap = Net::IMAP.new(@config_data.host, port: @config_data.port, ssl: @config_data.use_ssl)
    @imap.login(@config_data.username, @config_data.password)
    @logger.info "Connected"
  end

  def disconnect; return unless @imap; @imap.logout; @imap.disconnect; @logger.info "Disconnected from server"; end
  #def get_all_email_uids; connect unless @imap; @imap.uid_search(['ALL']); end

  # Download emails by their UIDs and save as .eml files
  # Returns an array of email metadata hashes
  def download_emails(uids, storage_dir)
    return [] if uids.empty?

    connect unless @imap
    emails = []

    # Ensure storage directory exists
    FileUtils.mkdir_p(storage_dir)

    uids.each do |uid|
      begin
        @logger.info "Downloading email UID: #{uid}"
        
        # Fetch the email
        fetch_data = @imap.uid_fetch(uid, ['RFC822', 'FLAGS']).first
        next unless fetch_data

        raw_email = fetch_data.attr['RFC822']
        flags = fetch_data.attr['FLAGS']
        
        # Parse the email for metadata
        mail = Mail.read_from_string(raw_email)
        
        # Save the raw email as .eml file
        email_filename = "#{uid}.eml"
        email_path = File.join(storage_dir, email_filename)
        File.write(email_path, raw_email)
        
        email_data = {
          uid: uid,
          message_id: mail.message_id,
          from: mail.from&.first,
          to: mail.to&.join(', '),
          subject: mail.subject,
          date: mail.date&.to_s,
          flags: flags,
          has_attachments: mail.attachments.any?,
          attachment_count: mail.attachments.count,
          email_file: email_path,
          downloaded_at: Time.now.to_s
        }

        emails << email_data
        @logger.info "Successfully downloaded: #{mail.subject} -> #{email_filename}"
      rescue => e
        @logger.error "Error downloading UID #{uid}: #{e.message}"
        @logger.error e.backtrace.join("\n")
      end
    end

    emails
  end

  def download_new_emails(already_downloaded_uids, storage_dir)
    all_uids = get_all_email_uids
    new_uids = all_uids - already_downloaded_uids
    
    @logger.info "Found #{all_uids.count} total emails, #{new_uids.count} new emails"
    
    download_emails(new_uids, storage_dir)
  end

  def move_emails(uids, destination_folder)
    return [] if uids.empty?

    connect unless @imap
    moved_uids = []

    uids.each do |uid|
      begin
        @logger.info "Moving email UID #{uid} to #{destination_folder}"
        @imap.uid_copy(uid, destination_folder)
        @imap.uid_store(uid, "+FLAGS", [:Deleted])
        moved_uids << uid
        @logger.info "Successfully moved UID #{uid}"
      rescue => e
        @logger.error "Error moving UID #{uid}: #{e.message}"
      end
    end

    # Expunge to permanently delete the moved messages from source folder
    @imap.expunge if moved_uids.any?

    moved_uids
  end
end

