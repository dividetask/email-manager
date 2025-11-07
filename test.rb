#!/usr/bin/env ruby

require 'irb'
require_relative 'utils'
require_relative 'email'
require_relative 'database'

if __FILE__ == $0
  config_path = ARGV[0] || 'config.yml'
  config_obj = Config.new(config_path)
  log_path = config_obj.log_path || './logs/email_daemon.log'
  log_obj = Utils.create_logger(log_path)

  data_obj = Database.new(config_obj.database_path)
  imap_obj = EmailHandler.new(config_obj, log_obj)

  folders = imap_obj.get_all_folders
  current_folder = 'INBOX'

  while true
    imap_obj.ensure_connected
    imap_obj.imap_obj.select(current_folder)
    uids = imap_obj.imap_obj.uid_search(['ALL'])

    print "Found #{uids.length} emails in #{current_folder}\n"

    begin
      uid = uids.first
      fetch_data = imap_obj.imap_obj.uid_fetch([uid], 'ENVELOPE')
      data = fetch_data.first
      envelope = data.attr['ENVELOPE']
      from_addr = imap_obj.extract_email_from_envelope(envelope)[:email]

			p envelope
      print "Press any key to move email (q to quit) "
      any_key = gets.chomp.downcase

      break if any_key == 'q'

      imap_obj.move_email(uid, DEFAULT_FOLDER)
      imap_obj.imap_obj.expunge
    rescue => e
      @log_obj.error "Error processing batch: #{e.message}"
    end

    imap_obj.disconnect
  end
end

