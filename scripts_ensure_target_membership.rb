#!/usr/bin/env ruby
require 'xcodeproj'
ROOT   = ENV['PROJECT_ROOT'] || File.expand_path('~/Desktop/timecard')
PROJ   = File.join(ROOT, 'Timecard.xcodeproj')
TARGET = ENV['TARGET_NAME']  || 'Timecard'

project = Xcodeproj::Project.open(PROJ)
target  = project.targets.find { |t| t.name == TARGET } || project.targets.first

added = 0
project.files.each do |ref|
  next unless ref.path
  next unless File.extname(ref.path) == '.swift'
  next if ref.path.start_with?('Support/Legacy') # keep legacy out

  in_sources = target.source_build_phase.files_references.include?(ref)
  unless in_sources
    target.add_file_references([ref])
    puts "added to Sources: #{ref.path}"
    added += 1
  end
end

project.save
puts "Done. #{added} file(s) added to Sources."
