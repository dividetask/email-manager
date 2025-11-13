#!/usr/bin/env ruby
require_relative 'utils'
require_relative 'email'
require_relative 'database'

if __FILE__ == $0
  config_path = ARGV[0] || 'config.yml'
  common = Common.new(config_path)

  daemon = EmailDaemon.new(common)
  sorter = EmailSorter.new(common)

  trap('INT') { daemon.request_shutdown; exit }
  trap('TERM') { daemon.request_shutdown; exit }

  daemon.start do
    sorter.connect
    sorter.process_folder 'INBOX'
    sorter.process_folder 'INBOX/Unsorted'
    sorter.cleanup
  end
end
