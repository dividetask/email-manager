
module ManageManual
  def self.add_email_recipients_to_contacts config_path
    common_obj = Common.new(config_path)
    handler = EmailHandler.new(common_obj)
    uids = handler.get_uids_by_folder('Sent')
    envelopes = handler.fetch_envelopes(uids)

    current_email_list = EmailAddress.get_record_list(common_obj.data_obj).map { |email| email[:address] }.flatten.map { |email| email.downcase }
    new_email_list = envelopes.map { |e| e[:to] }.flatten.map { |email| email.downcase }.uniq - current_email_list

    menu_obj = Menu.new common_obj
    folders = handler.list_folders

		menu_obj.prompt_for_each_email new_email_list, folders

    handler.disconnect
  end
end
