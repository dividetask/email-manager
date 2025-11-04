require 'yaml'
require 'logger'

class Config
  attr_reader :email, :database_path, :email_storage_dir, :check_interval, :log_file

  REQUIRED_EMAIL_KEYS = [:host, :username, :password]
  DEFAULT_VALUES = {
    port: 993,
    ssl: true,
    mailbox: 'INBOX',
    database_path: './data/emails.json',
    email_storage_dir: './data/emails',
    check_interval: 3600,
    log_file: './logs/email_daemon.log'
  }

  def initialize(config_path); @config_path = config_path; @config_data = load_config; parse_and_validate; end

  def load_config
    unless File.exist?(@config_path)
      raise ConfigError, "Config file not found: #{@config_path}"
    end

    begin
      YAML.load_file(@config_path, symbolize_names: true)
    rescue Psych::SyntaxError => e
      raise ConfigError, "Invalid YAML syntax in #{@config_path}: #{e.message}"
    rescue => e
      raise ConfigError, "Error loading config file: #{e.message}"
    end
  end

  def parse_and_validate
    unless @config_data[:email].is_a?(Hash)
      raise ConfigError, "Missing or invalid 'email' section in config"
    end

    @email = DEFAULT_VALUES.slice(:port, :ssl, :mailbox).merge(@config_data[:email])

    REQUIRED_EMAIL_KEYS.each do |key|
      unless @email[key]
        raise ConfigError, "Missing required email configuration: #{key}"
      end
    end

    @database_path = @config_data[:database_path] || DEFAULT_VALUES[:database_path]
    @email_storage_dir = @config_data[:email_storage_dir] || DEFAULT_VALUES[:email_storage_dir]
    @check_interval = @config_data[:check_interval] || DEFAULT_VALUES[:check_interval]
    validate_check_interval
    @log_file = @config_data[:log_file] || DEFAULT_VALUES[:log_file]
  end

  def validate_check_interval
    unless @check_interval.is_a?(Integer) && @check_interval > 0
      raise ConfigError, "check_interval must be a positive integer (seconds)"
    end

    if @check_interval < 60
      warn "Warning: check_interval is less than 60 seconds. This may overload the email server."
    end
  end

  def create_logger
    log_dir = File.dirname(@log_file)
    FileUtils.mkdir_p(log_dir) unless log_dir == '.'

    logger = Logger.new(@log_file)
    logger.level = Logger::INFO
    logger
  end

  class ConfigError < StandardError; end
end
