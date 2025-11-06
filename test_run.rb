#!/usr/bin/env ruby

require_relative 'utils'
require_relative 'email'

if __FILE__ == $0
  config_path = ARGV[0] || 'config.yml'
  config_obj = Config.new(config_path)
  log_path = config_obj.log_path || './logs/email_daemon.log'
  log_obj = Utils.create_logger(log_path)

  imap_obj = EmailHandler.new(config_obj, log_obj)
  p imap_obj.get_all_uids
end

