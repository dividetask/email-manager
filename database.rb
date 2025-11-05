require 'json'
require 'fileutils'
require 'logger'

class EmailDatabase
  attr_reader :db_path, :logger, :data

  VALID_STATUSES = ['unread', 'read', 'important', 'spam', 'pending', 'archived']

  def initialize(db_path, logger: Logger.new(STDOUT)); @db_path = db_path; @logger = logger; @data = load_database; end

  # Load the database from JSON file
  def load_database
    if File.exist?(@db_path)
      @logger.info "Loading database from #{@db_path}"
      JSON.parse(File.read(@db_path), symbolize_names: true)
    else
      @logger.info "Creating new database at #{@db_path}"
      { emails: [], metadata: { created_at: Time.now.to_s, last_updated: Time.now.to_s } }
    end
  rescue JSON::ParserError => e
    @logger.error "Error parsing database: #{e.message}"
    backup_corrupted_db
    { emails: [], metadata: { created_at: Time.now.to_s, last_updated: Time.now.to_s } }
  end

  # Save the database to JSON file
  def save_database
    @data[:metadata][:last_updated] = Time.now.to_s
    
    # Ensure directory exists
    FileUtils.mkdir_p(File.dirname(@db_path))
    
    # Write to temp file first, then rename (atomic operation)
    temp_path = "#{@db_path}.tmp"
    File.write(temp_path, JSON.pretty_generate(@data))
    FileUtils.mv(temp_path, @db_path)
    
    @logger.info "Database saved to #{@db_path}"
  end

  # Add new emails to the database
  def add_emails(emails)
    return 0 if emails.empty?

    added_count = 0
    emails.each do |email|
      unless email_exists?(email[:uid])
        email[:status] = 'unread'
        email[:tags] = []
        @data[:emails] << email
        added_count += 1
      end
    end

    save_database if added_count > 0
    @logger.info "Added #{added_count} new emails to database"
    added_count
  end

  def email_exists?(uid); @data[:emails].any? { |email| email[:uid] == uid }; end
  def get_all_uids; @data[:emails].map { |email| email[:uid] }; end
  def get_all_emails; @data[:emails]; end
  def get_emails_by_status(status); validate_status!(status); @data[:emails].select { |email| email[:status] == status }; end
  def find_email(uid); @data[:emails].find { |email| email[:uid] == uid }; end

  # Update email status
  def update_status(uid, new_status)
    validate_status!(new_status)
    
    email = find_email(uid)
    if email
      email[:status] = new_status
      email[:status_updated_at] = Time.now.to_s
      save_database
      @logger.info "Updated email #{uid} status to #{new_status}"
      true
    else
      @logger.warn "Email with UID #{uid} not found"
      false
    end
  end

  # Add tags to an email
  def add_tags(uid, tags)
    email = find_email(uid)
    if email
      email[:tags] ||= []
      tags = [tags] unless tags.is_a?(Array)
      email[:tags] = (email[:tags] + tags).uniq
      save_database
      @logger.info "Added tags to email #{uid}: #{tags.join(', ')}"
      true
    else
      @logger.warn "Email with UID #{uid} not found"
      false
    end
  end

  # Remove tags from an email
  def remove_tags(uid, tags)
    email = find_email(uid)
    if email
      email[:tags] ||= []
      tags = [tags] unless tags.is_a?(Array)
      email[:tags] -= tags
      save_database
      @logger.info "Removed tags from email #{uid}: #{tags.join(', ')}"
      true
    else
      @logger.warn "Email with UID #{uid} not found"
      false
    end
  end

  # Search emails by various criteria
  def search(criteria = {})
    results = @data[:emails]

    if criteria[:from]
      results = results.select { |e| e[:from]&.include?(criteria[:from]) }
    end

    if criteria[:subject]
      results = results.select { |e| e[:subject]&.include?(criteria[:subject]) }
    end

    if criteria[:status]
      validate_status!(criteria[:status])
      results = results.select { |e| e[:status] == criteria[:status] }
    end

    if criteria[:tags]
      tags = criteria[:tags].is_a?(Array) ? criteria[:tags] : [criteria[:tags]]
      results = results.select { |e| (e[:tags] & tags).any? }
    end

    results
  end

  # Get database statistics
  def stats
    {
      total_emails: @data[:emails].count,
      by_status: VALID_STATUSES.map { |s| [s.to_sym, get_emails_by_status(s).count] }.to_h,
      created_at: @data[:metadata][:created_at],
      last_updated: @data[:metadata][:last_updated]
    }
  end

  def move_emails(downloader, uids, destination_folder)
    return 0 if uids.empty?

    # Move on server
    moved_uids = downloader.move_emails(uids, destination_folder)

    # Update database to match
    moved_uids.each do |uid|
      email = find_email(uid)
      next unless email

      email[:folder] = destination_folder
      email[:moved_at] = Time.now.to_s
    end

    save_database
    moved_uids.count
  end

  # Read an email's content from its .eml file
  def read_email(email_file)
    unless File.exist?(email_file)
      @logger.error "Email file not found: #{email_file}"
      return nil
    end
    
    raw_email = File.read(email_file)
    mail = Mail.read_from_string(raw_email)
    
    {
      from: mail.from&.first,
      to: mail.to,
      subject: mail.subject,
      date: mail.date,
      body_text: extract_text_body(mail),
      body_html: extract_html_body(mail),
      attachments: mail.attachments.map { |a| { filename: a.filename, content_type: a.content_type } }
    }
  end

  # Search emails by content (requires reading .eml files)
  def search_content(criteria = {})
    results = []
    
    @data[:emails].each do |email|
      next unless File.exist?(email[:email_file])
      
      mail_content = read_email(email[:email_file])
      next unless mail_content
      
      match = true
      
      if criteria[:body_contains]
        text = mail_content[:body_text] || ''
        match = false unless text.downcase.include?(criteria[:body_contains].downcase)
      end
      
      results << email.merge(mail_content) if match
    end
    
    results
  end

  private

  # Extract plain text body from Mail object
  def extract_text_body(mail)
    if mail.multipart?
      text_part = mail.text_part
      text_part&.decoded
    else
      mail.content_type&.include?('text/plain') ? mail.decoded : nil
    end
  end

  # Extract HTML body from Mail object
  def extract_html_body(mail)
    if mail.multipart?
      html_part = mail.html_part
      html_part&.decoded
    else
      mail.content_type&.include?('text/html') ? mail.decoded : nil
    end
  end


  # Validate status value
  def validate_status!(status)
    unless VALID_STATUSES.include?(status)
      raise ArgumentError, "Invalid status: #{status}. Valid statuses are: #{VALID_STATUSES.join(', ')}"
    end
  end

  # Backup corrupted database
  def backup_corrupted_db
    backup_path = "#{@db_path}.corrupted.#{Time.now.to_i}"
    FileUtils.cp(@db_path, backup_path)
    @logger.warn "Corrupted database backed up to #{backup_path}"
  end
end
