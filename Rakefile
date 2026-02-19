# frozen_string_literal: true

require 'rake/testtask'
require 'rubocop/rake_task'

desc 'Start the CI/CD server'
task :start do
  ruby 'server.rb'
end

Rake::TestTask.new(:test) do |t|
  t.test_files = FileList['test/test_*.rb']
  t.warning = false
end

desc 'Run tests with coverage report'
task :coverage do
  ruby 'test/run_all.rb'
end

# RuboCop auto-format task
desc 'Auto-format code with RuboCop'
RuboCop::RakeTask.new(:format) do |task|
  task.patterns = ['**/*.rb']
  task.options = ['-a']
end

task default: :test