require 'rubygems'
require 'rspec/core/rake_task'  # testing framework
require 'yard'                  # yard documentation



# By default we don't run network tests
task :default => :limited_spec
RSpec::Core::RakeTask.new(:limited_spec) do |t|
    # Exclude network tests
    # t.rspec_opts = "--tag ~network" 
end
RSpec::Core::RakeTask.new(:spec)


desc "Run all tests"
task :test => [:spec]


YARD::Rake::YardocTask.new do |t|
    t.files   = ['lib/**/*.rb', '-', 'ext/README.md', 'README.md']
end
