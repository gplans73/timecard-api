#!/usr/bin/env ruby
require 'xcodeproj'

ROOT   = ENV['PROJECT_ROOT'] || File.expand_path('~/Desktop/timecard')
PROJ   = File.join(ROOT, 'Timecard.xcodeproj')
TARGET = ENV['TARGET_NAME']  || 'Timecard'

proj   = Xcodeproj::Project.open(PROJ)
main   = proj.main_group
target = proj.targets.find { |t| t.name == TARGET } || proj.targets.first

def ensure_group(root, rel)
  g = root
  rel.split('/').each { |seg| next if seg.empty?; g = (g[seg] || g.new_group(seg)) }
  g
end

MAP = {
  # App
  "App.swift"=>"App/App.swift",
  "RootView_WithSummary.swift"=>"App/Root/RootView.swift",
  "Timecard-Info.plist"=>"Support/Timecard-Info.plist",
  "TimecardLG-Bridging-Header.h"=>"Support/BridgingHeaders/TimecardLG-Bridging-Header.h",
  "InfoPlist.strings"=>"Resources/InfoPlist.strings",

  # TimeEntry
  "TimeEntryView_FULL_SunSatFridayPay_ALIGNED.swift"=>"Features/TimeEntry/Views/TimeEntryView_FULL_SunSatFridayPay_ALIGNED.swift",
  "TimecardPDFView.swift"=>"Features/TimeEntry/Views/TimecardPDFView.swift",
  "EntryRow.swift"=>"Features/TimeEntry/Views/EntryRow.swift",
  "CodesAndNotesView.swift"=>"Features/TimeEntry/Views/CodesAndNotesView.swift",

  # JobCode
  "JobCodeInputView.swift"=>"Features/JobCode/Views/JobCodeInputView.swift",
  "JobCodeTextField.swift"=>"Features/JobCode/Components/JobCodeTextField.swift",
  "AssistantTextField.swift"=>"Features/JobCode/Components/AssistantTextField.swift",
  "UKeyboardType.swift"=>"Features/JobCode/Components/UKeyboardType.swift",
  "JobCodeKeypad.swift"=>"Features/JobCode/Components/JobCodeKeyboard.swift",
  "NumericKeypad.swift"=>"Features/JobCode/Components/JobCodeKeyboard.swift",

  # Settings / Summary / Mail
  "SettingsView.swift"=>"Features/Settings/Views/SettingsView.swift",
  "AppIconSettingsView.swift"=>"Features/Settings/Views/AppIconSettingsView.swift",
  "EmailSettingsView.swift"=>"Features/Settings/Views/EmailSettingsView.swift",
  "HistoryView.swift"=>"Features/Settings/Views/HistoryView.swift",
  "iCloudSettingsView.swift"=>"Features/Settings/Views/iCloudSettingsView.swift",
  "iCloudSyncStatusView.swift"=>"Features/Settings/Views/iCloudSyncStatusView.swift",
  "IconSettingsView.swift"=>"Features/Settings/Views/IconSettingsView.swift",
  "JobsSettingsView.swift"=>"Features/Settings/Views/JobsSettingsView.swift",
  "OnCallSettingsView.swift"=>"Features/Settings/Views/OnCallSettingsView.swift",
  "PayPeriodSettingsView.swift"=>"Features/Settings/Views/PayPeriodSettingsView.swift",
  "ThemeSettingsView.swift"=>"Features/Settings/Views/ThemeSettingsView.swift",
  "ToolbarButtonsSettingsView.swift"=>"Features/Settings/Views/ToolbarButtonsSettingsView.swift",
  "LGSummary_FIX_internal.swift"=>"Features/Summary/Views/LGSummary_FIX_internal.swift",
  "SummaryTabSimple.swift"=>"Features/Summary/Views/SummaryTabSimple.swift",
  "MailView.swift"=>"Features/Mail/Views/MailView.swift",
  "SendView.swift"=>"Features/Mail/Views/SendView.swift",

  # Domain
  "Job.swift"=>"Domain/Entities/Job.swift",
  "Models.swift"=>"Domain/Entities/Models.swift",
  "PayPeriodCalculator.swift"=>"Domain/UseCases/CalculatePayPeriod.swift",
  "PayPeriod_SunSat_FridayPay.swift"=>"Domain/UseCases/CalculatePayPeriod_SunSatFriday.swift",
  "PayPeriodBC.swift"=>"Domain/UseCases/PayPeriodRules_BC.swift",

  # Data
  "JobsStore.swift"=>"Data/Local/Stores/JobsStore.swift",
  "SwiftDataModels.swift"=>"Data/Local/SwiftDataModels.swift",
  "UbiquitousSettingsSync.swift"=>"Data/Remote/Cloud/UbiquitousSettingsSync.swift",
  "SettingsSync.swift"=>"Data/Remote/Cloud/SettingsSync.swift",
  "Store.swift"=>"Data/Mappers/Store.swift",

  # Services
  "PDFRenderer.swift"=>"Services/PDF/PDFRenderer.swift",
  "XLSXWriter.swift"=>"Services/Export/XLSXWriter.swift",
  "AppIconManager.swift"=>"Services/Generation/AppIconManager.swift",
  "HolidayManager.swift"=>"Services/Generation/HolidayManager.swift",
  "IconAssetGenerator.swift"=>"Services/Generation/IconAssetGenerator.swift",
  "IconGenerator.swift"=>"Services/Generation/IconGenerator.swift",
  "LegacyCompat.swift"=>"Services/Generation/LegacyCompat.swift",
  "CloudSupport.swift"=>"Services/Cloud/CloudSupport.swift",
  "RegionLocator.swift"=>"Services/Location/RegionLocator.swift",

  # UI
  "ActivityView.swift"=>"UI/Components/ActivityView.swift",
  "LGActivityView.swift"=>"UI/Components/LGActivityView.swift",
  "View+Keyboard.swift"=>"UI/Modifiers/View+Keyboard.swift",
  "ColorExtensions.swift"=>"UI/Theme/Colors/ColorExtensions.swift",
  "ThemeType.swift"=>"UI/Theme/Types/ThemeType.swift",

  # Resources (non-code generally not added to Sources)
  "JobsSeed.csv"=>"Resources/Seeds/JobsSeed.csv",
  "README.md"=>"Resources/README.md"
}

def add_or_move_ref(project, main, target, old, new_rel)
  full = File.join(ROOT, new_rel)
  unless File.exist?(full)
    puts "skip (no file on disk): #{new_rel}"
    return
  end
  # try to find by exact or basename
  ref = project.files.find { |f| f.path == old || f.path == new_rel || File.basename(f.path.to_s) == File.basename(old) }

  grp = ensure_group(main, File.dirname(new_rel))
  if ref
    # rebuild under correct group if needed
    unless grp.children.include?(ref)
      was_in_build = target.source_build_phase.files_references.include?(ref)
      ref.remove_from_project
      new_ref = grp.new_file(new_rel)
      target.add_file_references([new_ref]) if was_in_build
      puts "moved ref: #{old} -> #{new_rel}"
    else
      ref.path = new_rel
      puts "updated ref: #{old} -> #{new_rel}"
    end
  else
    new_ref = grp.new_file(new_rel)
    # Only add to Sources phase if it's Swift
    target.add_file_references([new_ref]) if File.extname(new_rel) == ".swift"
    puts "added ref: #{new_rel}"
  end
end

MAP.each { |old,newp| add_or_move_ref(proj, main, target, old, newp) }
proj.save
puts "Reference update complete for #{PROJ} (target: #{target.name})."
