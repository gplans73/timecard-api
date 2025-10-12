#!/usr/bin/env bash
set -euo pipefail
ROOT="${PROJECT_ROOT:-$HOME/Desktop/timecard}"
cd "$ROOT"

is_git(){ git rev-parse --is-inside-work-tree >/dev/null 2>&1; }
mv_safe(){ # mv or git mv; creates dest dir
  local src="$1" dst="$2"
  [ -e "$src" ] || { echo "skip (missing): $src"; return; }
  mkdir -p "$(dirname "$dst")"
  if is_git; then git mv -v "$src" "$dst"; else mv -v "$src" "$dst"; fi
}

# --- Ensure target folders exist ---
for d in \
  App/Root \
  Features/TimeEntry/Views Features/TimeEntry/ViewModels Features/TimeEntry/Models \
  Features/JobCode/Views Features/JobCode/ViewModels Features/JobCode/Models Features/JobCode/Components \
  Features/Settings/Views Features/Settings/ViewModels Features/Settings/Models \
  Features/Summary/Views Features/Mail/Views Features/History/Views \
  Domain/Entities Domain/UseCases \
  Data/Local/Stores Data/Remote/Cloud Data/Mappers \
  Services/PDF Services/Export Services/Generation Services/Cloud Services/Location \
  UI/Components UI/Modifiers UI/Theme/Colors UI/Theme/Types \
  Resources/Assets.xcassets Resources/Seeds \
  Support/BridgingHeaders Support/Legacy Utilities
do mkdir -p "$d"; done

echo "=== App / Support / Resources ==="
mv_safe "App.swift"                         "App/App.swift"
mv_safe "RootView_WithSummary.swift"        "App/Root/RootView.swift"
mv_safe "BootstrapView.swift"               "App/Root/BootstrapView.swift"
mv_safe "Timecard-Info.plist"               "Support/Timecard-Info.plist"
mv_safe "TimecardLG-Bridging-Header.h"      "Support/BridgingHeaders/TimecardLG-Bridging-Header.h"
mv_safe "InfoPlist.strings"                 "Resources/InfoPlist.strings"

# Assets
[ -d "Assets.xcassets" ] && mv_safe "Assets.xcassets" "Resources/Assets.xcassets"
[ -f "Assets.xcassets.zip" ] && echo "NOTE: keep out of target: Assets.xcassets.zip"

# Seeds / docs
[ -f "JobsSeed.csv" ] && mv_safe "JobsSeed.csv" "Resources/Seeds/JobsSeed.csv"
[ -f "README.txt" ] && mv_safe "README.txt" "Resources/README.md"

echo "=== Features: TimeEntry ==="
# In your screenshot the file name is ..._FULL_SunSatFriday_ALIGNED.swift (without 'Pay'), normalize to one name:
if ls -1 *TimeEntryView*ALIGNED.swift >/dev/null 2>&1; then
  f="$(ls -1 *TimeEntryView*ALIGNED.swift | head -1)"
  mv_safe "$f" "Features/TimeEntry/Views/TimeEntryView_FULL_SunSatFridayPay_ALIGNED.swift"
fi
mv_safe "TimecardPDFView.swift"             "Features/TimeEntry/Views/TimecardPDFView.swift"
mv_safe "EntryRow.swift"                    "Features/TimeEntry/Views/EntryRow.swift"
mv_safe "CodesAndNotesView.swift"           "Features/TimeEntry/Views/CodesAndNotesView.swift"

echo "=== Features: JobCode ==="
mv_safe "JobCodeInputView.swift"            "Features/JobCode/Views/JobCodeInputView.swift"
mv_safe "JobCodeTextField.swift"            "Features/JobCode/Components/JobCodeTextField.swift"
mv_safe "AssistantTextField.swift"          "Features/JobCode/Components/AssistantTextField.swift"
[ -f "UKeyboardType.swift" ] && mv_safe "UKeyboardType.swift" "Features/JobCode/Components/UKeyboardType.swift"
# Unify keypad (avoid the collision you hit previously)
if [ -e "JobCodeKeypad.swift" ] && [ -e "NumericKeypad.swift" ]; then
  mv_safe "JobCodeKeypad.swift"             "Features/JobCode/Components/JobCodeKeyboard.swift"
  mv_safe "NumericKeypad.swift"             "Support/Legacy/NumericKeypad_OLD.swift"
elif [ -e "JobCodeKeypad.swift" ]; then
  mv_safe "JobCodeKeypad.swift"             "Features/JobCode/Components/JobCodeKeyboard.swift"
elif [ -e "NumericKeypad.swift" ]; then
  mv_safe "NumericKeypad.swift"             "Features/JobCode/Components/JobCodeKeyboard.swift"
fi

echo "=== Features: Settings / Summary / Mail / History ==="
for f in \
  SettingsView AppIconSettingsView EmailSettingsView HistoryView \
  iCloudSettingsView iCloudSyncStatusView IconSettingsView JobsSettingsView \
  OnCallSettingsView PayPeriodSettingsView ThemeSettingsView ToolbarButtonsSettingsView
do
  [ -f "$f.swift" ] && mv_safe "$f.swift" "Features/Settings/Views/$f.swift"
done
mv_safe "LGSummary_FIX_internal.swift"      "Features/Summary/Views/LGSummary_FIX_internal.swift"
mv_safe "SummaryTabSimple.swift"            "Features/Summary/Views/SummaryTabSimple.swift"
mv_safe "MailView.swift"                    "Features/Mail/Views/MailView.swift"
mv_safe "SendView.swift"                    "Features/Mail/Views/SendView.swift"

echo "=== Domain (Entities / UseCases) ==="
mv_safe "Job.swift"                         "Domain/Entities/Job.swift"
mv_safe "Models.swift"                      "Domain/Entities/Models.swift"
mv_safe "PayPeriodCalculator.swift"         "Domain/UseCases/CalculatePayPeriod.swift"
mv_safe "PayPeriod_SunSat_FridayPay.swift"  "Domain/UseCases/CalculatePayPeriod_SunSatFriday.swift"
mv_safe "PayPeriodBC.swift"                 "Domain/UseCases/PayPeriodRules_BC.swift"

echo "=== Data ==="
mv_safe "JobsStore.swift"                   "Data/Local/Stores/JobsStore.swift"
mv_safe "SwiftDataModels.swift"             "Data/Local/SwiftDataModels.swift"
mv_safe "UbiquitousSettingsSync.swift"      "Data/Remote/Cloud/UbiquitousSettingsSync.swift"
mv_safe "SettingsSync.swift"                "Data/Remote/Cloud/SettingsSync.swift"
mv_safe "Store.swift"                       "Data/Mappers/Store.swift"

echo "=== Services ==="
mv_safe "PDFRenderer.swift"                 "Services/PDF/PDFRenderer.swift"
mv_safe "XLSXWriter.swift"                  "Services/Export/XLSXWriter.swift"
mv_safe "AppIconManager.swift"              "Services/Generation/AppIconManager.swift"
mv_safe "HolidayManager.swift"              "Services/Generation/HolidayManager.swift"
mv_safe "IconAssetGenerator.swift"          "Services/Generation/IconAssetGenerator.swift"
mv_safe "IconGenerator.swift"               "Services/Generation/IconGenerator.swift"
mv_safe "LegacyCompat.swift"                "Services/Generation/LegacyCompat.swift"
mv_safe "CloudSupport.swift"                "Services/Cloud/CloudSupport.swift"
mv_safe "RegionLocator.swift"               "Services/Location/RegionLocator.swift"

echo "=== UI / Utilities ==="
mv_safe "ActivityView.swift"                "UI/Components/ActivityView.swift"
mv_safe "LGActivityView.swift"              "UI/Components/LGActivityView.swift"
mv_safe "View+Keyboard.swift"               "UI/Modifiers/View+Keyboard.swift"
mv_safe "ColorExtensions.swift"             "UI/Theme/Colors/ColorExtensions.swift"
mv_safe "ThemeType.swift"                   "UI/Theme/Types/ThemeType.swift"

echo "=== Leave these out of the target (just keep on disk) ==="
for junk in \
  "Assets.xcassets.zip" \
  "JobCodeTextField.swift.zip" \
  "Timecard 2.zip" \
  "Timecard Files/timecard_export_template.xlsx" \
  "Timecard Files/Timecard_Geoff_Strench_2025-09-28"
do [ -e "$junk" ] && echo "NOTE: not target member -> $junk"; done

echo "Feature reorg complete."
