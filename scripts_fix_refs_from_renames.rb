#!/usr/bin/env ruby
require 'xcodeproj'

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

# Old basename -> new relative PATH (adjust if any file lives elsewhere)
RENAMES = {
  "App.swift"                               => "App/TimecardApp.swift",
  "RootView_WithSummary.swift"              => "App/Root/MainTabView.swift",
  "AppIconManager.swift"                    => "AppIcon.swift",
  "CloudSupport.swift"                      => "CloudLog.swift",
  "JobCodeKeyboard.swift"                   => "Features/JobCode/Components/JobCodeKeypadView.swift",
  "TimeEntryView_FULL_SunSatFridayPay_ALIGNED.swift" => "Features/TimeEntry/Views/KeyboardDismissModifier.swift",
  "TimecardPDFView.swift"                   => "Features/TimeEntry/Views/TimeEntryType.swift",
  "IconGenerator.swift"                     => "IconArt.swift",
  "IconSettingsView.swift"                  => "IconEntry.swift",
  "LGSummary_FIX_internal.swift"            => "Summary_FIX_internal.swift",
  "Models.swift"                            => "TimeEntry.swift",
  "PayPeriodBC.swift"                        => "BCPayPeriod.swift",
  "PayPeriodCalculator.swift"                => "PayPeriod.swift",
  "PayPeriod_SunSat_FridayPay.swift"         => "OddPayPeriod.swift",
  "Store.swift"                              => "Country.swift",
  "SwiftDataModels.swift"                    => "EntryModel.swift",
  "ToolbarButtonsSettingsView.swift"         => "ToolbarButton.swift"
}

updated = 0
RENAMES.each do |old_base, new_rel|
  new_abs = File.join(ROOT, new_rel)
  unless File.exist?(new_abs)
    puts "skip (new file missing): #{new_rel}"
    next
  end

  # find any project file reference whose basename matches the OLD name
  ref = project.files.find { |f| f.path && File.basename(f.path) == old_base }
  unless ref
    puts "skip (no project ref for old): #{old_base}"
    next
  end

  grp = ensure_group(project.main_group, File.dirname(new_rel))

  was_in_sources = target.source_build_phase.files_references.include?(ref)
  ref.remove_from_project
  new_ref = grp.new_file(new_rel)
  target.add_file_references([new_ref]) if was_in_sources || File.extname(new_rel) == '.swift'
  puts "updated ref: #{old_base} -> #{new_rel}"
  updated += 1
end

project.save
puts "Done. Updated #{updated} renamed reference(s)."
