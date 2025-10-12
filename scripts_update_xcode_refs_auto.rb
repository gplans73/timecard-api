#!/usr/bin/env ruby
require 'xcodeproj'
require 'find'

ROOT   = ENV['PROJECT_ROOT'] || File.expand_path('~/Desktop/timecard')
PROJ   = File.join(ROOT, 'Timecard.xcodeproj')
TARGET = ENV['TARGET_NAME']  || 'Timecard'

project = Xcodeproj::Project.open(PROJ)
main    = project.main_group
target  = project.targets.find { |t| t.name == TARGET } || project.targets.first

def ensure_group(root, rel)
  g = root
  rel.split('/').each { |seg| next if seg.empty?; g = (g[seg] || g.new_group(seg)) }
  g
end

# Index all files on disk by basename
disk_index = {}
Find.find(ROOT) do |p|
  next if File.directory?(p)
  rel = p.sub(/^#{Regexp.escape(ROOT)}\//, '')
  disk_index[File.basename(p)] ||= []
  disk_index[File.basename(p)] << rel
end

changed = 0
project.files.each do |ref|
  next unless ref.path # skip groups
  base = File.basename(ref.path)
  matches = disk_index[base] || []
  next if matches.empty?

  # Prefer a match that isn't in Support/Legacy
  rel = matches.find { |m| !m.start_with?('Support/Legacy') } || matches.first

  # Already correct?
  next if ref.path == rel

  grp = ensure_group(main, File.dirname(rel))
  # Recreate the ref under correct group if needed
  was_in_sources = target.source_build_phase.files_references.include?(ref)
  ref.remove_from_project
  new_ref = grp.new_file(rel)
  target.add_file_references([new_ref]) if was_in_sources || File.extname(rel) == '.swift'
  puts "updated ref: #{base} -> #{rel}"
  changed += 1
end

project.save
puts "Auto-update complete (#{changed} refs updated). Project: #{PROJ}, target: #{target.name}"
