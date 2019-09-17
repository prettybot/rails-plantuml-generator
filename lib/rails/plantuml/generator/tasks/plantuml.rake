require 'rails/plantuml/generator/model_generator'
require 'optparse'

OUTPUT_FILE = 'diagramm.puml'

ASSOCIATION_TYPE = :association_type
ASSOCIATION_OTHER_CLASS = :other_class
ASSOCIATION_OTHER_NAME = :other_name
ASSOCIATION_TYPE_HAS_MANY = '*'
ASSOCIATION_TYPE_HAS_ONE = '1'

namespace :plantuml do
  desc "Pick a random user as the winner"
  task generate: :environment do |args|
    Rails.application.eager_load!
    options = {}
    o = OptionParser.new
    o.banner = "Usage: rake plantuml:generate [options]"
    o.on("-s DIR", "--skip DIR") { |excluded_dir|
      options[:excluded_dir] = excluded_dir
    }
    args = o.order!(ARGV) {}
    model_files = Dir.glob('app/models/**/*.rb')
    model_files -= o.parse!(args)
    model_files -= Dir.glob('app/models/concerns/**/*.rb')

    generator = Rails::Plantuml::Generator::ModelGenerator.new model_files

    File.open OUTPUT_FILE, 'w' do |file|
      generator.write_to_io file
    end
  end
end