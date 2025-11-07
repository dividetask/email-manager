#!/usr/bin/env ruby

require 'irb'
require_relative 'utils'
require_relative 'email'
require_relative 'database'

class ContactPrompter
  attr_reader :data_obj, :log_obj
  
  def initialize(data_obj, log_obj)
    @data_obj = data_obj
    @log_obj = log_obj
  end
  
  def get_unknown_addresses(addresses)
    known_emails = EmailAddress.get_record_list(@data_obj).map { |ea| ea[:address] }
    addresses.reject { |addr| known_emails.include?(addr[:email]) }
  end

  def select_folder(folders)
    return nil if folders.empty?
    
    puts "\nAvailable folders:"
    folders.each_with_index do |folder, i|
      puts "  #{i + 1}. #{folder}"
    end
    puts "  0. None"
    
    print "\nSelect auto_folder (enter number): "
    choice = gets.chomp.to_i
    
    return nil if choice == 0 || choice > folders.length
    folders[choice - 1]
  end

  def test_stuff(imap_obj)
    folders = imap_obj.get_all_folders
  	current_folder = 'INBOX'
    @log_obj.info "Processing #{current_folder}..."
    imap_obj.ensure_connected
    imap_obj.imap_obj.select(current_folder)
    
    uids = imap_obj.search_folder(current_folder)
    @log_obj.info "Found #{uids.length} emails in #{current_folder}"

    while true
      p uids.sample(10)
      print "Enter UID (q - quit, r - refresh): "
      uid = gets.chomp.downcase

      break if uid == 'q'
      next if uid == 'r'

      begin
        uid = uid.to_i
        fetch_data = imap_obj.imap_obj.uid_fetch([uid], 'ENVELOPE')
        data = fetch_data.first
        uid = data.attr['UID']
        envelope = data.attr['ENVELOPE']
        from_addr = imap_obj.extract_email_from_envelope(envelope)[:email]
        subject = imap_obj.extract_email_from_envelope(envelope)[:subject]
        p data
        print "Where should we move #{from_addr}, #{subject}\n"
        target_folder = select_folder(folders)
        next unless target_folder
        imap_obj.move_email(uid, target_folder) if target_folder and target_folder != current_folder
      rescue => e
        @log_obj.error "Error processing batch: #{e.message}"
      end
    end
  end

  def prompt_move_emails(imap_obj)
    folders = imap_obj.get_all_folders
  	current_folder = 'INBOX'
    @log_obj.info "Processing #{current_folder}..."
    imap_obj.ensure_connected
    imap_obj.imap_obj.select(current_folder)
    
    uids = imap_obj.search_folder(current_folder)
    @log_obj.info "Found #{uids.length} emails in #{current_folder}"

    uids.each_slice(100) do |uid_batch|
      begin
        fetch_data = imap_obj.imap_obj.uid_fetch(uid_batch, 'ENVELOPE')
        fetch_data.each do |data|
          uid = data.attr['UID']
          envelope = data.attr['ENVELOPE']
          from_addr = imap_obj.extract_email_from_envelope(envelope)[:email]
          subject = imap_obj.extract_email_from_envelope(envelope)[:subject]
          
          print "Where should we move #{from_addr}, #{subject}\n"
          target_folder = select_folder(folders)
          return false unless target_folder
          imap_obj.move_email(uid, target_folder) if target_folder and target_folder != current_folder
        end
      rescue => e
        @log_obj.error "Error processing batch: #{e.message}"
      end
    end
    
  end

  def prompt_bulk_contacts(imap_obj, selected_folder)
    folders = imap_obj.get_all_folders
    addresses = imap_obj.get_email_addresses_from_folder(selected_folder)
    unknown_list = get_unknown_addresses(addresses)

    while true
      unknown_list.sample(10).each { |addr| print " #{addr[:email]}\n" }

      print "Enter Search (q - quit, r - refresh): "
      search = gets.chomp.downcase

      break if search == 'q'
      next if search == 'r'

      addr_list = unknown_list.select { |record| (record[:name] || []).include?(search) || (record[:email] || []).include?(search) }

      print "Found #{addr_list.count} records\n"
      next unless addr_list.count > 0
      addr_list.each { |addr| print " #{addr[:email]}\n" }

      print "Action - (n)ew contact, (e)xisting contact, (s)kip, (q)uit: "
      response = gets.chomp.downcase

      break if response == 'q'
      next if response == 's'

      if response == 'e'
        contact_hash = select_existing_contact
        next unless contact_hash
        
      elsif response == 'n'
        print "Contact name [#{addr_list.first[:name]}]: "
        name = gets.chomp
        name = addr_list.first[:name] if name.empty?
        
        print "Priority (0-10) [0]: "
        priority = gets.chomp
        priority = priority.empty? ? 0 : priority.to_i
        
        auto_folder = select_folder(folders)
        next unless auto_folder
        
        contact_obj = Contact.add_record(@data_obj, name: name, priority: priority, auto_folder: auto_folder)
        @log_obj.info "Created contact '#{name}'"
        puts "✓ Contact created successfully!"
        contact_hash = contact_obj.to_h
      else 
        next
      end
        
      addr_list.each do |addr|
        email_addr = EmailAddress.add_record(@data_obj, contact_id: contact_hash[:uid], address: addr[:email])
        @log_obj.info "Added email #{addr[:email]} to contact '#{contact_hash[:name]}'"
      end
      puts "✓ #{addr_list.count} emails added to contact successfully!"
      unknown_list = unknown_list - addr_list
    end
  end
  
  def prompt_create_contacts(unknown_addresses, imap_obj)
    folders = imap_obj.get_all_folders

    unknown_addresses.each do |addr|
      puts "\n" + "="*50
      puts "Email: #{addr[:email]}"
      puts "Name from email: #{addr[:name]}" if addr[:name]
      puts "="*50
      
      print "Action - (n)ew contact, (e)xisting contact, (s)kip, (q)uit: "
      response = gets.chomp.downcase

      break if response == 'q'
      next if response == 's'
    
      if response == 'e'
        contact = select_existing_contact
        next unless contact
        
        email_addr = EmailAddress.add_record(@data_obj, contact_id: contact[:uid], address: addr[:email])
        @log_obj.info "Added email #{addr[:email]} to existing contact '#{contact[:name]}'"
        puts "✓ Email added to contact successfully!"
        
      elsif response == 'n'
        print "Contact name [#{addr[:name]}]: "
        name = gets.chomp
        name = addr[:name] if name.empty?
        
        print "Priority (0-10) [0]: "
        priority = gets.chomp
        priority = priority.empty? ? 0 : priority.to_i
        
        auto_folder = select_folder(folders)
        
        contact = Contact.add_record(@data_obj, name: name, priority: priority, auto_folder: auto_folder)
        email_addr = EmailAddress.add_record(@data_obj, contact_id: contact.uid, address: addr[:email])
        
        @log_obj.info "Created contact '#{name}' with email #{addr[:email]}"
        puts "✓ Contact created successfully!"
      end
    end
  end

  def select_existing_contact
    contact_list = Contact.get_record_list(@data_obj)
    
    if contact_list.empty?
      puts "No existing contacts found."
      return nil
    end
    
    puts "\nExisting contacts:"
    puts "  0. Cancel"
    contact_list.each_with_index do |contact_hash, i|
      puts "  #{i + 1}. #{contact_hash[:name]}"
    end
    
    print "\nSelect contact (enter number): "
    choice = gets.chomp.to_i
    
    return nil if choice == 0 || choice > contact_list.length
    contact_list[choice - 1]
  end
end


def clean_email_uids()
  config_path = ARGV[0] || 'config.yml'
  config_obj = Config.new(config_path)
  log_path = config_obj.log_path || './logs/email_daemon.log'
  log_obj = Utils.create_logger(log_path)

  data_obj = Database.new(config_obj.database_path)

  log_obj.info "Cleaning UIDs for Email Addresses"
  EmailAddress.clean_uids(data_obj, log_obj)
end

def single_address(config_obj, log_obj, data_obj, imap_obj)
  log_obj.info "Fetching email addresses from INBOX"
  addresses = imap_obj.get_email_addresses_from_folder('INBOX')
  log_obj.info "Found #{addresses.length} unique email addresses"

  prompter = ContactPrompter.new(data_obj, log_obj)

  unknown = prompter.get_unknown_addresses(addresses)

  puts "\nFound #{unknown.length} unknown email addresses"

  if unknown.empty?
    puts "All email addresses are already in the database!"
  else
    prompter.prompt_create_contacts(unknown, imap_obj)
  end
end

def bulk_address(config_obj, log_obj, data_obj, imap_obj)
  #current_folder = 'INBOX'

  #log_obj.info "Fetching email addresses from #{current_folder}"
  #addresses = imap_obj.get_email_addresses_from_folder(current_folder)
  #log_obj.info "Found #{addresses.length} unique email addresses"

  current_folder = DEFAULT_FOLDER
  prompter = ContactPrompter.new(data_obj, log_obj)
  prompter.prompt_bulk_contacts(imap_obj, current_folder)
end

if __FILE__ == $0
  #clean_email_uids()

  config_path = ARGV[0] || 'config.yml'
  config_obj = Config.new(config_path)
  log_path = config_obj.log_path || './logs/email_daemon.log'
  log_obj = Utils.create_logger(log_path)

  data_obj = Database.new(config_obj.database_path)
  imap_obj = EmailHandler.new(config_obj, log_obj)

  current_folder = 'INBOX'
  imap_obj.ensure_connected
  imap_obj.imap_obj.select(current_folder)
  imap_obj.expunge
  #bulk_address(config_obj, log_obj, data_obj, imap_obj)
  #single_address(config_obj, log_obj, data_obj, imap_obj)
  #prompter = ContactPrompter.new(data_obj, log_obj)
  #prompter.test_stuff(imap_obj)

  imap_obj.disconnect

end

