# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "steep/rake_task"
# require "rubocop/rake_task"

RSpec::Core::RakeTask.new(:spec)
# RuboCop::RakeTask.new
Steep::RakeTask.new do |t|
  t.check.severity_level = :error
  t.watch.verbose
end

task default: %i[steep spec]
