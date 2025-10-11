#!/usr/bin/env bash
set -euo pipefail
cd "${PROJECT_ROOT:-$HOME/Desktop/timecard}"

is_git() { git rev-parse --is-inside-work-tree >/dev/null 2>&1; }
mv_one() {
  src="$1"; dst="$2"
  [ -e "$src" ] || { echo "skip (missing): $src"; return; }
  mkdir -p "$(dirname "$dst")"
  if is_git; then git mv -v "$src" "$dst"; else mv -v "$src" "$dst"; fi
}

# 1) Create target folders
for d in \
  App/Root \
  Features/TimeEntry/Views Features/JobCode/Views Features/JobCode/Components \
  Features/Settings/Views Features/Summary/Views Features/Mail/Views \
  Domain/Entities Domain/UseCases \
  Data/Local/Stores Data/Remote/Cloud Data/Mappers \
  Services/PDF Services/Export Services/Generation Services/Cloud Services/Location \
  UI/Components UI/Modifiers UI/Theme/Colors UI/Theme/Types \
  Resources/Assets.xcassets Resources/Seeds \
  Support/BridgingHeaders Support/Legacy \
  "Timecard Files"
do mkdir -p "$d"; done

echo "=== App / Support / Resources ==="
mv_one "App.swift"                        "App/App.swift"
mv_one "RootView_WithSummary.swift"       "App/Root/RootView.swift"                 # rename
mv_one "Timecard-Info.plist"              "Support/Timecard-Info.plist"
mv_one "TimecardLG-Bridging-Header.h"     "Support/BridgingHeaders/TimecardLG-Bridging-Header.h"
mv_one "InfoPlist.strings"                "Resources/InfoPlist.strings"

echo "=== Features: TimeEntry ==="
# Some projects show the long filename truncated in Finder/Xcode; handle both.
if [ -e "TimeEntryView_FULL_SunSatFridayPay_ALIGNED.swift" ]; then
  mv_one "TimeEntryView_FULL_SunSatFridayPay_ALIGNED.swift" "Features/TimeEntry/Views/TimeEntryView_FULL_SunSatFridayPay_ALIGNED.swift"
elif ls TimeEntryView_*ALIGNED.swift >/dev/null 2>&1; then
  f="$(ls TimeEntryView_*ALIGNED.swift | head -1)"
  mv_one "$f" "Features/TimeEntry/Views/TimeEntryView_FULL_SunSatFridayPay_ALIGNED.swift"
fi
mv_one "TimecardPDFView.swift"            "Features/TimeEntry/Views/TimecardPDFView.swift"
mv_one "EntryRow.swift"                   "Features/TimeEntry/Views/EntryRow.swift"
mv_one "CodesAndNotesView.swift"          "Features/TimeEntry/Views/CodesAndNotesView.swift"

echo "=== Features: JobCode ==="
mv_one "JobCodeInputView.swift"           "Features/JobCode/Views/JobCodeInputView.swift"
mv_one "JobCodeTextField.swift"           "Features/JobCode/Components/JobCodeTextField.swift"
mv_one "AssistantTextField.swift"         "Features/JobCode/Components/AssistantTextField.swift"
mv_one "UKeyboardType.swift"              "Features/JobCode/Components/UKeyboardType.swift" || true
# unify keypad name
if [ -e "JobCodeKeypad.swift" ]; then
  mv_one "JobCodeKeypad.swift"            "Features/JobCode/Components/JobCodeKeyboard.swift"
fi
if [ -e "NumericKeypad.swift" ]; then
  mv_one "NumericKeypad.swift"            "Features/JobCode/Components/JobCodeKeyboard.swift"
fi

echo "=== Features: Settings / Summary / Mail ==="
for f in SettingsView AppIconSettingsView EmailSettingsView HistoryView \
         iCloudSettingsView iCloudSyncStatusView IconSettingsView JobsSettingsView \
         OnCallSettingsView PayPeriodSettingsView ThemeSettingsView ToolbarButtonsSettingsView; do
  [ -e "$f.swift" ] && mv_one "$f.swift" "Features/Settings/Views/$f.swift"
done
mv_one "LGSummary_FIX_internal.swift"     "Features/Summary/Views/LGSummary_FIX_internal.swift"
mv_one "SummaryTabSimple.swift"           "Features/Summary/Views/SummaryTabSimple.swift"
mv_one "MailView.swift"                   "Features/Mail/Views/MailView.swift"
mv_one "SendView.swift"                   "Features/Mail/Views/SendView.swift"

echo "=== Domain (business layer) ==="
mv_one "Job.swift"                         "Domain/Entities/Job.swift"
mv_one "Models.swift"                      "Domain/Entities/Models.swift"            || true
mv_one "PayPeriodCalculator.swift"         "Domain/UseCases/CalculatePayPeriod.swift"   # rename
mv_one "PayPeriod_SunSat_FridayPay.swift"  "Domain/UseCases/CalculatePayPeriod_SunSatFriday.swift"
mv_one "PayPeriodBC.swift"                 "Domain/UseCases/PayPeriodRules_BC.swift"

echo "=== Data ==="
mv_one "JobsStore.swift"                   "Data/Local/Stores/JobsStore.swift"
mv_one "SwiftDataModels.swift"             "Data/Local/SwiftDataModels.swift"
mv_one "UbiquitousSettingsSync.swift"      "Data/Remote/Cloud/UbiquitousSettingsSync.swift"
mv_one "SettingsSync.swift"                "Data/Remote/Cloud/SettingsSync.swift"
mv_one "Store.swift"                       "Data/Mappers/Store.swift"

echo "=== Services ==="
mv_one "PDFRenderer.swift"                 "Services/PDF/PDFRenderer.swift"
mv_one "XLSXWriter.swift"                  "Services/Export/XLSXWriter.swift"
mv_one "AppIconManager.swift"              "Services/Generation/AppIconManager.swift"
mv_one "HolidayManager.swift"              "Services/Generation/HolidayManager.swift"
mv_one "IconAssetGenerator.swift"          "Services/Generation/IconAssetGenerator.swift"
mv_one "IconGenerator.swift"               "Services/Generation/IconGenerator.swift"
mv_one "LegacyCompat.swift"                "Services/Generation/LegacyCompat.swift"
mv_one "CloudSupport.swift"                "Services/Cloud/CloudSupport.swift"
mv_one "RegionLocator.swift"               "Services/Location/RegionLocator.swift"

echo "=== UI ==="
mv_one "ActivityView.swift"                "UI/Components/ActivityView.swift"
mv_one "LGActivityView.swift"              "UI/Components/LGActivityView.swift"
mv_one "View+Keyboard.swift"               "UI/Modifiers/View+Keyboard.swift"
mv_one "ColorExtensions.swift"             "UI/Theme/Colors/ColorExtensions.swift"
mv_one "ThemeType.swift"                   "UI/Theme/Types/ThemeType.swift"

echo "=== Resources ==="
# unzip old assets if present
if [ -f "Assets.xcassets.zip" ]; then
  echo "Unzipping Assets.xcassets.zip -> Resources/Assets.xcassets/"
  mkdir -p Resources/Assets.xcassets
  unzip -oq "Assets.xcassets.zip" -d "Resources/Assets.xcassets"
  rm -f "Assets.xcassets.zip"
fi
mv_one "Assets.xcassets"                   "Resources/Assets.xcassets"
mv_one "JobsSeed.csv"                      "Resources/Seeds/JobsSeed.csv"
# README.txt to markdown if desired
[ -f "README.txt" ] && mv_one "README.txt" "Resources/README.md" || true

echo "=== Not adding to target (kept outside groups) ==="
for junk in "JobCodeTextField.swift.zip" "Timecard 2.zip" ; do
  [ -e "$junk" ] && echo "NOTE: leave out of target -> $junk"
done
# keep customer exports/tools out of project references
[ -e "Timecard Files/timecard_export_template.xlsx" ] && echo "NOTE: leave out of target -> Timecard Files/timecard_export_template.xlsx"
[ -e "Timecard Files/Timecard_Geoff_Strench_2025-09-28" ] && echo "NOTE: leave out of target -> Timecard Files/Timecard_Geoff_Strench_2025-09-28"

echo "Moves & renames complete."
