
module ManageManual
  def self.add_email_recipients_to_contacts config_path
    common_obj = Common.new(config_path)
    handler = EmailHandler.new(common_obj)
    uids = handler.get_uids_by_folder('Sent')
    envelopes = handler.fetch_envelopes(uids)

    current_email_list = EmailAddress.all(common_obj.data_obj).map { |email| email[:address] }.flatten.map { |email| email.downcase }
    new_email_list = envelopes.map { |e| e[:to] }.flatten.map { |email| email.downcase }.uniq - current_email_list

    menu_obj = Menu.new common_obj
    folder_list = handler.list_folders

		menu_obj.prompt_for_each_sent_email new_email_list, folder_list

    handler.disconnect
  end
  
  def self.bulk_contacts config_path, selected_folder
    common_obj = Common.new(config_path)
    handler = EmailHandler.new(common_obj)

    menu_obj = Menu.new common_obj
    folder_list = handler.list_folders

    uids = handler.get_uids_by_folder(selected_folder)
    envelopes = handler.fetch_envelopes(uids)

    current_email_list = EmailAddress.all(common_obj.data_obj).map { |email| email[:address] }.flatten.map { |email| email.downcase }
    unknown_list = envelopes.select { |e| !current_email_list.include? e[:from].downcase }

		menu_obj.prompt_for_each_recievied_email unknown_list, folder_list

    handler.disconnect
  end

  def self.single_daemon_iteration config_path, max_emails = nil
    common_obj = Common.new(config_path)
    sorter = EmailSorter.new(common_obj)
    sorter.process_folder 'INBOX', max_emails
    sorter.process_folder 'INBOX/Unsorted', max_emails
    sorter.cleanup
  end

  def self.get_duplicate_list config_path, debug_info = false
    common_obj = Common.new(config_path)
    email_repo = EmailRepository.new(common_obj)
    duplicates = email_repo.find_duplicates ['INBOX', 'INBOX/Unsorted']
    print "Found #{duplicates.count} message with duplicates, total #{duplicates.values.sum { |list| list.count - 1 }}\n"
    if debug_info
      duplicates.each do |message_id, duplicate_list|
        print "Duplicates found: #{duplicate_list.count - 1}\n"
        duplicate_list.each { |dup| print "    from: #{dup[:from]}, subject: #{dup[:subject]}, folder: #{dup[:folder]}\n" }
        print "\n"
      end
    end
    email_repo.disconnect
  end

  def self.delete_duplicates config_path, max_delete = nil
    common_obj = Common.new(config_path)
    email_repo = EmailRepository.new(common_obj)
    duplicates = email_repo.find_duplicates ['INBOX', 'INBOX/Unsorted']
    print "Found #{duplicates.count} duplicates\n"
    duplicates.each do |message_id, duplicate_list|
    	print "Duplicates found: #{duplicate_list.count - 1}"
    	print " - from: #{duplicate_list.first[:from]}, subject: #{duplicate_list.first[:subject]}, folder: #{duplicate_list.first[:folder]}\n Deleting " 
      duplicate_list[1..-1].each do |dup|
        print '.'
      	email_repo.delete dup[:folder], dup[:uid]
      end
      print "\n"
      break if max_delete && max_delete <= 1
      max_delete = max_delete - 1 if max_delete
    end
    email_repo.expunge
    email_repo.disconnect
  end

  def self.test_deamon_1 config_path
    common = Common.new(config_path)

    daemon = EmailDaemon.new(common, {overwrite_check_interval: 10})
    sorter = EmailSorter.new(common)

    trap('INT') { daemon.request_shutdown; exit }
    trap('TERM') { daemon.request_shutdown; exit }

    @runs = 0
    daemon.start do
      @runs = @runs + 1
      p "RUN #{@runs}"
      sorter.connect
      sorter.process_folder 'INBOX'
      sorter.process_folder 'INBOX/Unsorted'
      sorter.cleanup
      daemon.stop if @runs >= 2
    end
  end

  def self.get_number(message, accepted_number_list)
    input = nil
    while (true)
      print "#{message} "
      input = gets.chomp
      break if input == 'q'
      input = input.to_i
      break if accepted_number_list.include? input
    end
    input
  end

  def self.get_response(message, accepted_responses)
    input = nil
    while (true)
      print "#{message} "
      input = gets.chomp
      break if input == 'q'
      break if accepted_responses.include? input
    end
    input
  end

	def self.show_selected email_list, is_selected_hash
    print "\n\n"
    email_list.each.with_index do |env, index|
      #print "#{index + 1}. #{'* ' if is_selected_hash[env[:from]]}#{env[:from]}\t\tsubject: '#{env[:subject][0..40]}'\n"
      from_text = "#{index + 1}. #{'* ' if is_selected_hash[env[:from]]}#{env[:from]}"
      print "#{from_text.ljust(50)}\tsubject: '#{env[:subject][0..40]}'\n"
    end
  end

  def self.bulk_spam config_path
    common_obj = Common.new(config_path)
    handler = EmailHandler.new(common_obj)
    folder = 'INBOX/Unsorted'
    uids = handler.get_uids_by_folder(folder)
    all_emails = {}

    uids.each_slice(20) do |uid_batch|
      begin
        #system('clear')
        envelopes = handler.fetch_envelopes(uid_batch)
        new_emails = []

        envelopes.each do |env|
          all_emails[env[:from]] = :unsorted unless all_emails[env[:from]]
          new_emails << env if all_emails[env[:from]] == :unsorted
        end

        is_selected_hash = {}
        input = nil
        while input != 'q'
          show_selected new_emails, is_selected_hash
          input = get_number "Select emails for spam ('q' when done): ", (1..new_emails.count).to_a
          break if input == 'q'
          is_selected_hash[new_emails[input - 1][:from]] = !is_selected_hash[new_emails[input - 1][:from]] if input > 0 and input <= new_emails.count
        end

        spam_uids = []
        envelopes.each { |env| spam_uids << env[:message_id] if is_selected_hash[env[:from]] == true }
        input = get_response "#{spam_uids.count} messages selected, Move to spam?", ['y','n']
        break if input == 'q'
        if input == 'y'
          new_emails.each do |env|
          	if is_selected_hash[env[:from]]
              handler.move_email(env[:uid], 'Spam')
              all_emails[env[:from]] = :spam
              common_obj.log_info "Moving #{env[:from]}, #{env[:subject]} to Spam"
            else
              all_emails[env[:from]] = :skipped
            end
          end
          handler.expunge
        end
      rescue => e
        common_obj.error "Error fetching batch: #{e.message}"
      end
    end

    handler.disconnect
  end
end

