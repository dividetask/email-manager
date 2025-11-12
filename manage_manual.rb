
module ManageManual
  def self.add_email_recipients_to_contacts config_path
    common_obj = Common.new(config_path)
    handler = EmailHandler.new(common_obj)
    uids = handler.get_uids_by_folder('Sent')
    envelopes = handler.fetch_envelopes(uids)

    current_email_list = EmailAddress.all(data_obj).map { |email| email[:address] }.flatten.map { |email| email.downcase }
    new_email_list = envelopes.map { |e| e[:to] }.flatten.map { |email| email.downcase }.uniq - current_email_list

    menu_obj = Menu.new common_obj
    folders = handler.list_folders

		menu_obj.prompt_for_each_sent_email new_email_list, folders

    handler.disconnect
  end
  
  def self.bulk_contacts config_path, selected_folder
    common_obj = Common.new(config_path)
    handler = EmailHandler.new(common_obj)

    menu_obj = Menu.new common_obj
    folders = handler.list_folders

    uids = handler.get_uids_by_folder(selected_folder)
    envelopes = handler.fetch_envelopes(uids)

    current_email_list = EmailAddress.all(common_obj.data_obj).map { |email| email[:address] }.flatten.map { |email| email.downcase }
    unknown_list = envelopes.select { |e| !current_email_list.include? e[:from].downcase }

		menu_obj.prompt_for_each_recievied_email unknown_list, folders

    handler.disconnect
  end

  def self.single_daemon_iteration config_path
    common_obj = Common.new(config_path)
    sorter = EmailSorter.new(common_obj)
    sorter.process_folder 'INBOX', 300
    sorter.process_folder 'INBOX/Unsorted', 300
    sorter.cleanup
  end
end

