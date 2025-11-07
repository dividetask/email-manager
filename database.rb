require 'json'
require 'fileutils'

class Database
  attr_reader :db_path, :data

  def initialize(db_path); @db_path = db_path; @data = load_database; end
  def load_database; return JSON.parse(File.read(@db_path), symbolize_names: true) if File.exist?(@db_path); return { }; end

  def save; FileUtils.mkdir_p(File.dirname(@db_path)); File.write(@db_path, JSON.pretty_generate(@data)); end
  def generate_uid(table); uid = 0; uid += 1 while (@data[table] || []).any? { |record| record[:uid] == uid }; return uid; end
end

class Table
  attr_accessor :data_obj, :uid

  def initialize(data_obj); @data_obj = data_obj; generate_uid; end
  def set_defaults(params); params; end
  def table_name; self.class.table_name; end
  def generate_uid; @uid = @data_obj.generate_uid(table_name); end
  def save; @data_obj.data[table_name] ||= []; @data_obj.data[table_name] << self.to_h; @data_obj.save; self; end

  def self.add_record(data_obj, **params); record = new(data_obj, **params); record.save; end
  def self.table_name; self.name.downcase + 's'; end
  def self.find(data_obj, **params); get_record_list(data_obj).find { |r| params.all? { |k, v| r[k] == v } }; end 
  def self.get_record_list(data_obj); data_obj.data[table_name.to_sym] || []; end

  def to_h
    hash = {}
    (instance_variables - [:@data_obj]).each do |var|
      key = var.to_s.delete('@').to_sym
      hash[key] = instance_variable_get(var)
    end
    hash
  end

  def self.from_h(data_obj, hash)
    obj = allocate
    obj.instance_variable_set(:@data_obj, data_obj)
    hash.each do |key, value|
      obj.instance_variable_set("@#{key}", value)
    end
    obj
  end
end

class Contact < Table
  attr_accessor :name, :priority, :auto_folder
  def initialize(data_obj, name:, priority:, auto_folder: nil); super(data_obj); @name = name; @priority = priority; @auto_folder = auto_folder; end
end

class EmailAddress < Table
  attr_accessor :contact_id, :address
  def initialize(data_obj, contact_id:, address:); super(data_obj); @contact_id = contact_id; @address = address; end
end
