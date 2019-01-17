# frozen_string_literal: true

require 'bundler/setup'

task default: %w[spec]

require 'rspec/core/rake_task'
RSpec::Core::RakeTask.new

begin
  require 'rubocop/rake_task'
  RuboCop::RakeTask.new
  task default: :rubocop
rescue LoadError => e
  raise unless e.path == 'rubocop/rake_task'
end
