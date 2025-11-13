#!/usr/bin/env ruby

require 'irb'
require_relative 'utils'
require_relative 'email'
require_relative 'database'
require_relative 'manage_manual'


if __FILE__ == $0
  config_path = ARGV[0] || 'config.yml'
  #ManageManual.add_email_recipients_to_contacts(config_path)
  #ManageManual.bulk_contacts(config_path, 'INBOX/Unsorted')
  #ManageManual.bulk_contacts(config_path, 'INBOX')
  #ManageManual.single_daemon_iteration(config_path)
  #ManageManual.get_duplicate_list config_path
  #ManageManual.delete_duplicates config_path
  #ManageManual.test_deamon_1 config_path
  ManageManual.bulk_spam config_path
end
