#!/usr/bin/env ruby

require 'irb'
require_relative 'utils'
require_relative 'email'
require_relative 'database'
require_relative 'manage_manual'


if __FILE__ == $0
  #ManageManual.add_email_recipients_to_contacts(ARGV[0] || 'config.yml')
  ManageManual.bulk_contacts(ARGV[0] || 'config.yml', 'INBOX')
end
