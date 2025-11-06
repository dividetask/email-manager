#!/usr/bin/env ruby

require_relative 'utils'

if __FILE__ == $0
  config_path = ARGV[0] || 'config.yml'
  config_obj = Config.new(config_path)
  log_path = config_obj.log_path || './logs/email_daemon.log'
  logger = Utils.create_logger(log_path)

  logger.info "Configuration loaded successfully"
  logger.info "Host: #{config_obj.host}"
  logger.info "Username: #{config_obj.username}"
  p config_obj.host, config_obj.username
end

