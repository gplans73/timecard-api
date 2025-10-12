#!/usr/bin/env ruby
# Dry-run: pass --apply to actually rename (using `git mv` if repo)
require 'find'
root = ENV['PROJECT_ROOT'] || File.expand_path('~/Desktop/timecard')
apply = ARGV.include?('--apply')
swift = Dir.glob(File.join(root, '**', '*.swift'))
swift.each do |path|
  next if path.include?('/Support/Legacy/')
  code = File.read(path)
  if code =~ /(struct|class|actor|enum)\s+([A-Z][A-Za-z0-9_]*)/m
    type = $2
    current = File.basename(path, '.swift')
    next if current == type
    new_path = File.join(File.dirname(path), "#{type}.swift")
    puts "#{path.sub(root+'/','')}  ->  #{new_path.sub(root+'/','')}"
    if apply
      if system('git', 'mv', path, new_path)
      else
        File.rename(path, new_path)
      end
    end
  end
end
puts(apply ? "Renamed where needed." : "DRY-RUN complete. Re-run with --apply to rename.")
