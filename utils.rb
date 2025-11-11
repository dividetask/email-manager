require 'yaml'
require 'logger'
require 'fileutils'

class MultiIO
  def initialize(*targets)
    @targets = targets
  end

  def write(*args)
    @targets.each { |t| t.write(*args) }
  end

  def close
    @targets.each(&:close)
  end
end

module Utils
  def self.open_yaml(path)
    unless File.exist?(path)
      raise ConfigError, "File not found: #{path}"
    end

    begin
      YAML.load_file(path, symbolize_names: true)
    rescue Psych::SyntaxError => e
      raise ConfigError, "Invalid YAML syntax in #{path}: #{e.message}"
    rescue => e
      raise ConfigError, "Error loading file: #{e.message}"
    end
  end

  def self.create_logger(log_file, output_to_console = false)
    log_dir = File.dirname(log_file)
    FileUtils.mkdir_p(log_dir) unless log_dir == '.'

    loggers = [File.open(log_file, 'a')]
    loggers << STDOUT if output_to_console

    log_obj = Logger.new(MultiIO.new(*loggers))
    log_obj.level = Logger::DEBUG
    #log_obj.level = Logger::INFO
    log_obj
  end

  class ConfigError < StandardError; end
end

class Config
  attr_reader :host, :port, :username, :password, :use_ssl, :log_path, :database_path, :check_interval

  def initialize(config_path)
    config_data = Utils.open_yaml(config_path)
    @log_path = config_data[:log_path]
    @database_path = config_data[:database_path]
    @check_interval = config_data[:check_interval]

    email_config = config_data[:email]
    @host = email_config[:host]
    @port = email_config[:port]
    @username = email_config[:username]
    @password = email_config[:password]
    @use_ssl = email_config[:ssl].nil? ? true : email_config[:ssl]
  end
end

class Menu
  attr_reader :common_obj
  def initialize(common_obj); @common_obj = common_obj; end

  def prompt_for_each_sent_email new_email_list, folders
    new_email_list.each do |new_email|
      print "Add Email #{new_email} - (n)ew contact, (e)xisting contact, (s)kip, (q)uit: "
      response = gets.chomp.downcase

      break if response == 'q'
      next if response == 's'

      if response == 'e'
        contact_hash = select_existing_contact
        next unless contact_hash

      elsif response != 'n'
        next
      
      else
        print "Contact name: "
        name = gets.chomp
        
        print "Priority (0-10) [0]: "
        priority = gets.chomp
        priority = priority.empty? ? 0 : priority.to_i
        
        auto_folder = select_folder(folders)
        return true unless auto_folder
        
        contact_obj = Contact.add_record(@common_obj.data_obj, name: name, priority: priority, auto_folder: auto_folder)
        @common_obj.log_info "Created contact '#{name}'"
        puts "✓ Contact created successfully!"
        contact_hash = contact_obj.to_h
      end
      
      email_obj = EmailAddress.add_record(@common_obj.data_obj, contact_id: contact_hash[:uid], address: new_email)
      @common_obj.log_info "Added email #{new_email} to contact '#{contact_hash[:name]}'"
      puts "✓ 1 emails added to contact successfully!"
    end
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

  def select_existing_contact
    contact_list = Contact.all(@common_obj.data_obj)
    
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

  def prompt_for_each_recievied_email unknown_list, folders
    while true
      unknown_list.sample(10).each { |addr| print " #{addr[:from]}\n" }

      print "Enter Search (q - quit, r - refresh): "
      search = gets.chomp.downcase

      break if search == 'q'
      next if search == 'r'

      addr_list = unknown_list.select { |record| record[:name]&.downcase&.include?(search) || record[:from]&.downcase&.include?(search) }.uniq { |record| record[:from] }

      print "Found #{addr_list.count} records\n"
      next unless addr_list.count > 0
      addr_list.each { |addr| print " #{addr[:from]}\n" }

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
        
        contact_obj = Contact.add_record(@common_obj.data_obj, name: name, priority: priority, auto_folder: auto_folder)
        @common_obj.log_info "Created contact '#{name}'"
        puts "✓ Contact created successfully!"
        contact_hash = contact_obj.to_h
      else 
        next
      end
        
      addr_list.each do |addr|
        email_addr = EmailAddress.add_record(@common_obj.data_obj, contact_id: contact_hash[:uid], address: addr[:from])
        @common_obj.log_info "Added email #{addr[:from]} to contact '#{contact_hash[:name]}'"
      end
      puts "✓ #{addr_list.count} emails added to contact successfully!"
      unknown_list = unknown_list - addr_list
    end
  end
end
