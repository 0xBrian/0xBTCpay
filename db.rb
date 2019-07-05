require "mysql2"
require "sequel"
require "yaml"

env = (Sinatra::Base.environment.to_s rescue nil) || ENV["RACK_ENV"] || "development"
config = YAML.load(File.read("database.yml"))[env]
DB = Sequel.connect(config)
Sequel.default_timezone = :utc
require "./models"
