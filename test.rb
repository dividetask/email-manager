#!/usr/bin/env ruby

require 'irb'
require_relative 'utils'
require_relative 'email'
require_relative 'database'
require_relative 'manage_manual'

#def get_all_emails_responded_to imap_obj, log_obj
  #folders = imap_obj.get_all_folders
  #current_folder = 'Sent'
  #emails_responded_to = []

  #imap_obj.ensure_connected
  #imap_obj.imap_obj.select(current_folder)
  #uids = imap_obj.imap_obj.uid_search(['ALL'])

  #begin
    #uids.each_slice(100) do |uid_batch|
      #fetch_data = imap_obj.imap_obj.uid_fetch(uid_batch, 'ENVELOPE')
      #fetch_data.each do |data|
        #uid = data.attr['UID']
        #envelope = data.attr['ENVELOPE']
        #emails_responded_to.concat(envelope.to.map { |e| "#{e.mailbox}@#{e.host}" }) if envelope.to
      #end
    #end
  #rescue => e
    #log_obj.error "Error processing batch: #{e.message}"
  #end

  #imap_obj.disconnect
  #emails_responded_to
#end


# Usage:
if __FILE__ == $0
  ManageManual.add_email_recipients_to_contacts(ARGV[0] || 'config.yml')
end


#if __FILE__ == $0
  #config_path = ARGV[0] || 'config.yml'
  #config_obj = Config.new(config_path)
  #log_path = config_obj.log_path || './logs/email_daemon.log'
  #log_obj = Utils.create_logger(log_path)

  #data_obj = Database.new(config_obj.database_path)
  #imap_obj = EmailHandler.new(config_obj, log_obj)
  #p get_all_emails_responded_to imap_obj, log_obj

#end

