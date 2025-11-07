#!/usr/bin/env ruby

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
  
  def prompt_create_contacts(unknown_addresses, imap_obj)
    folders = imap_obj.get_all_folders

    unknown_addresses.each do |addr|
      puts "\n" + "="*50
      puts "Email: #{addr[:email]}"
      puts "Name from email: #{addr[:name]}" if addr[:name]
      puts "="*50
      
      print "Create contact? (y/n/q to quit): "
      response = gets.chomp.downcase
      
      break if response == 'q'
      next unless response == 'y'
      
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


if __FILE__ == $0
  config_path = ARGV[0] || 'config.yml'
  config_obj = Config.new(config_path)
  log_path = config_obj.log_path || './logs/email_daemon.log'
  log_obj = Utils.create_logger(log_path)


  data_obj = Database.new(config_obj.database_path)
  imap_obj = EmailHandler.new(config_obj, log_obj)


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

  imap_obj.disconnect

end

