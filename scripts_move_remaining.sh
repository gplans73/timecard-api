#!/usr/bin/env bash
set -euo pipefail
cd "${PROJECT_ROOT:-$HOME/Desktop/timecard}"

is_git(){ git rev-parse --is-inside-work-tree >/dev/null 2>&1; }
mv_safe(){ src="$1"; dst="$2"; [ -e "$src" ] || { echo "skip (missing): $src"; return; }
  mkdir -p "$(dirname "$dst")"; if is_git; then git mv -v "$src" "$dst"; else mv -v "$src" "$dst"; fi; }

# Services / Generation & Cloud
mv_safe "AppIcon.swift"                    "Services/Generation/AppIcon.swift"
mv_safe "IconArt.swift"                    "Services/Generation/IconArt.swift"
mv_safe "CloudLog.swift"                   "Services/Cloud/CloudLog.swift"

# Settings Views (UI)
mv_safe "IconEntry.swift"                  "Features/Settings/Views/IconEntry.swift"

# Summary view
mv_safe "Summary_FIX_internal.swift"       "Features/Summary/Views/Summary_FIX_internal.swift"

# Domain / Data
mv_safe "TimeEntry.swift"                  "Domain/Entities/TimeEntry.swift"
mv_safe "BCPayPeriod.swift"                "Domain/UseCases/BCPayPeriod.swift"
mv_safe "PayPeriod.swift"                  "Domain/UseCases/PayPeriod.swift"
mv_safe "OddPayPeriod.swift"               "Domain/UseCases/OddPayPeriod.swift"
mv_safe "Country.swift"                    "Data/Mappers/Country.swift"
mv_safe "EntryModel.swift"                 "Data/Local/EntryModel.swift"
mv_safe "ToolbarButton.swift"              "Domain/Entities/ToolbarButton.swift"
