#!/usr/bin/env ruby
require 'xcodeproj'
ROOT   = ENV['PROJECT_ROOT'] || File.expand_path('~/Desktop/timecard')
PROJ   = File.join(ROOT, 'Timecard.xcodeproj')
project = Xcodeproj::Project.open(PROJ)
target  = project.targets.find{|t| t.name=='Timecard'} || project.targets.first

added = 0
project.files.each do |ref|
  next unless ref.path
  next unless File.extname(ref.path) == '.swift'
  next if ref.path.start_with?('Support/Legacy')
  unless target.source_build_phase.files_references.include?(ref)
    target.add_file_references([ref])
    added += 1
    puts "added: #{ref.path}"
  end
end
project.save
puts "Done. #{added} file(s) added to Sources."
