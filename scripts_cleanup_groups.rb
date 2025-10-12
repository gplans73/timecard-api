#!/usr/bin/env ruby
require 'xcodeproj'
require 'find'

ROOT   = ENV['PROJECT_ROOT'] || File.expand_path('~/Desktop/timecard')
PROJ   = File.join(ROOT, 'Timecard.xcodeproj')
TARGET = ENV['TARGET_NAME']  || 'Timecard'

project = Xcodeproj::Project.open(PROJ)
main    = project.main_group

# 1) Hoist children of a group literally named "."
def flatten_dot_groups(group)
  group.groups.dup.each do |g|
    flatten_dot_groups(g)
    next unless g.display_name == "."
    parent = g.parent
    g.children.dup.each do |child|
      child.move(parent)
    end
    g.remove_from_project
    puts 'removed "." group and hoisted children'
  end
end
flatten_dot_groups(main)

# 2) Remove 'Recovered References' group (and any children)
def remove_group_by_name(group, name)
  group.groups.dup.each do |g|
    if g.display_name == name
      g.recursive_children.each { |c| c.remove_from_project if c.isa == 'PBXFileReference' }
      g.remove_from_project
      puts "removed group: #{name}"
    else
      remove_group_by_name(g, name)
    end
  end
end
remove_group_by_name(main, 'Recovered References')

# 3) Remove file refs pointing to paths that no longer exist
changed = 0
project.files.dup.each do |ref|
  next unless ref.path
  abs = File.expand_path(ref.path, File.dirname(PROJ))
  unless File.exist?(abs)
    ref.remove_from_project
    changed += 1
  end
end

project.save
puts "Cleanup complete. Removed #{changed} dangling reference(s). Project: #{PROJ}"
