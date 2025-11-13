
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
end

