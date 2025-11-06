require 'yaml'
require 'logger'
require 'fileutils'

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

  def self.create_logger(log_file)
    log_dir = File.dirname(log_file)
    FileUtils.mkdir_p(log_dir) unless log_dir == '.'

    logger = Logger.new(log_file)
    logger.level = Logger::INFO
    logger
  end

  class ConfigError < StandardError; end
end

class Config
  attr_reader :host, :port, :username, :password, :use_ssl, :log_path

  def initialize(config_path)
    config_data = Utils.open_yaml(config_path)
    @log_path = config_data[:log_path]

    email_config = config_data[:email]
    @host = email_config[:host]
    @port = email_config[:port]
    @username = email_config[:username]
    @password = email_config[:password]
    @use_ssl = email_config[:ssl].nil? ? true : email_config[:ssl]
  end
end
