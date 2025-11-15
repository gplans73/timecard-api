import SwiftUI

/// Minimal local definition to satisfy this view. If your project defines `TimeEntryType` elsewhere,
/// remove this and use the shared type instead.
private enum TimeEntryType {
    case regular
    case night
    case ot
    case dt
    case vacation
    case stat
}

struct TimecardPDFView: View {
    @EnvironmentObject var store: TimecardStore
    var weekOffset: Int = 0 // 0 = Week #1, 1 = Week #2

    // DateFormatter for MM-dd-yy
    private let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "MM-dd-yy"
        return df
    }()

    // Days of week starting Sunday
    private let weekdays = Calendar.current.weekdaySymbols // Sunday first

    // Computed: Dates for the current week (7 days), starting from weekStart
    private var weekDates: [Date] {
        let startDate = store.weekRange(offset: weekOffset).lowerBound
        return (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: startDate) }
    }

    // Extract week number 1 or 2
    private var weekNumberString: String {
        return "Week #\(weekOffset + 1)"
    }
    
    // Pads a string with spaces up to a fixed length so it occupies consistent width with monospaced font
    private func padToLength(_ text: String, length: Int) -> String {
        let count = text.count
        if count >= length { return text }
        return text + String(repeating: " ", count: length - count)
    }

    // MARK: - Helper functions for displaying timecard data
    private func formatHours(_ value: Double) -> String {
        let nf = NumberFormatter()
        nf.minimumFractionDigits = 0
        nf.maximumFractionDigits = 2
        nf.minimumIntegerDigits = 1
        return nf.string(from: NSNumber(value: value)) ?? ""
    }
    
    private func displayJobText(for entry: Entry) -> String {
        let category: PayCategory = entry.isNightShift ? .night : store.category(for: entry.code)
        // For STAT entries, always display "Stat" for the job label
        if category == .stat {
            return "Stat"
        }
        // Do NOT prefix job number with "N"; the N prefix belongs on the labour code
        return entry.jobNumber
    }
    
    private func displayJobNumber(for entry: Entry) -> String {
        // Do NOT prefix job number with "N"; the N prefix belongs on the labour code
        return entry.jobNumber
    }

    private func displayLabourCode(for entry: Entry) -> String {
        // Prefix labour code with "N" when this entry is marked as a night shift
        if entry.isNightShift {
            return "N\(entry.code)"
        }
        return entry.code
    }

    private func entriesFor(day: Date) -> [Entry] {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: day)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
        let dayRange = dayStart..<dayEnd
        
        return store.entries.filter { entry in
            guard dayRange.contains(entry.date),
                  !entry.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
            let category: PayCategory = entry.isNightShift ? .night : store.category(for: entry.code)
            // Allow empty job number for STAT holidays so they appear in the PDF
            let hasJobOrIsStat = !entry.jobNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || category == .stat
            return hasJobOrIsStat
        }
    }
    
    private func regularEntriesFor(day: Date) -> [Entry] {
        return entriesFor(day: day).filter { entry in
            // First check if user selected "Overtime hours" - if so, exclude from regular table
            if entry.isOvertime {
                return false
            }
            // Otherwise, check code category (Night entries are excluded from the Regular table)
            let category: PayCategory = entry.isNightShift ? .night : store.category(for: entry.code)
            return category == .regular || category == .vacation || category == .stat
        }
    }
    
    private func overtimeEntriesFor(day: Date) -> [Entry] {
        return store.entries.filter { entry in
            let calendar = Calendar.current
            let dayStart = calendar.startOfDay(for: day)
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
            let dayRange = dayStart..<dayEnd

            guard dayRange.contains(entry.date),
                  entry.hours != 600,
                  !entry.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }

            if entry.isOvertime { return true }
            let category: PayCategory = entry.isNightShift ? .night : store.category(for: entry.code)
            return category == .ot || category == .dt || category == .onCall
        }
    }
    
    private func nightEntriesFor(day: Date) -> [Entry] {
        return entriesFor(day: day).filter { entry in
            // Exclude items explicitly marked as overtime
            if entry.isOvertime { return false }
            // Treat the Night toggle as night regardless of code
            let category: PayCategory = entry.isNightShift ? .night : store.category(for: entry.code)
            return category == .night
        }
    }
    
    // Helper function to calculate daily overtime and double-time based on total hours worked
    private func calculateDailyOvertimeAndDoubleTime(for date: Date) -> (overtime: Double, doubleTime: Double) {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
        let dayRange = dayStart..<dayEnd

        // Include all worked entries for the day (exclude sentinels and empty codes)
        let dayEntries = store.entries.filter { entry in
            dayRange.contains(entry.date) &&
            entry.hours != 600 &&
            !entry.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        let totalHours = dayEntries.reduce(0.0) { $0 + $1.hours }

        // Pull thresholds from the current overtime policy
        let policy = store.overtimePolicy
        let regularCap = policy.dailyRegularCap ?? Double.greatestFiniteMagnitude
        let otUpper = policy.dailyOTCap ?? regularCap // upper bound of OT band
        let dtStart = policy.dailyDTCap ?? otUpper    // DT starts after this

        // Compute OT as hours between regularCap and dtStart; DT as hours after dtStart
        let overtime: Double
        let doubleTime: Double
        if policy.dailyRegularCap == nil && policy.dailyOTCap == nil && policy.dailyDTCap == nil {
            // No daily rules (weekly-only)
            overtime = 0
            doubleTime = 0
        } else {
            overtime = max(0.0, min(totalHours, dtStart) - regularCap)
            doubleTime = max(0.0, totalHours - dtStart)
        }

        return (overtime: overtime, doubleTime: doubleTime)
    }

    // Added helpers for explicit OT and DT hours per day (used for Sunday rule)
    private func explicitOTHours(for date: Date) -> Double {
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        let end = cal.date(byAdding: .day, value: 1, to: start)!
        let range = start..<end
        let entries = store.entries.filter { e in
            range.contains(e.date) && e.hours != 600 && !e.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return entries.reduce(0.0) { sum, e in
            let cat: PayCategory = e.isNightShift ? .night : store.category(for: e.code)
            return (cat == .ot || e.isOvertime) ? sum + e.hours : sum
        }
    }

    private func explicitDTHours(for date: Date) -> Double {
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        let end = cal.date(byAdding: .day, value: 1, to: start)!
        let range = start..<end
        let entries = store.entries.filter { e in
            range.contains(e.date) && e.hours != 600 && !e.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return entries.reduce(0.0) { sum, e in
            let cat: PayCategory = e.isNightShift ? .night : store.category(for: e.code)
            return (cat == .dt) ? sum + e.hours : sum
        }
    }
    
    // Added new helper for explicit On Call hours per date
    private func explicitOnCallHours(for date: Date) -> Double {
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        let end = cal.date(byAdding: .day, value: 1, to: start)!
        let range = start..<end
        let entries = store.entries.filter { e in
            range.contains(e.date) && e.hours != 600 && !e.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return entries.reduce(0.0) { sum, e in
            let cat: PayCategory = e.isNightShift ? .night : store.category(for: e.code)
            return (cat == .onCall) ? sum + e.hours : sum
        }
    }

    // Added helper for capped explicit OT/DT for any date (applies 12-hr cap and rolls over excess OT to DT)
    private func explicitCappedOTDT(for date: Date) -> (ot: Double, dt: Double) {
        let ot = explicitOTHours(for: date)
        let dt = explicitDTHours(for: date)
        if ot > 12 { return (ot: 12.0, dt: dt + (ot - 12.0)) }
        return (ot: ot, dt: dt)
    }

    // New helper functions for weekly capped OT and DT totals
    private func weeklyCappedOT(forWeekDates weekDates: [Date]) -> String {
        let sum = weekDates.reduce(0.0) { $0 + explicitCappedOTDT(for: $1).ot }
        return sum > 0 ? formatHours(sum) : ""
    }

    private func weeklyCappedDT(forWeekDates weekDates: [Date]) -> String {
        let sum = weekDates.reduce(0.0) { $0 + explicitCappedOTDT(for: $1).dt }
        return sum > 0 ? formatHours(sum) : ""
    }

// Weekly OT/DT totals for the Notes column that mirror the overtime table logic
    private func weeklyOTForNotes(weekDates: [Date]) -> String {
        let policyMap = computeWeekOTDT(weekDates: weekDates)
        let total = weekDates.reduce(0.0) { sum, d in
            let key = Calendar.current.startOfDay(for: d)
            let policy = policyMap[key] ?? (0,0)
            return sum + min(policy.ot, 4.0)
        }
        return total > 0 ? formatHours(total) : ""
    }

    private func weeklyDTForNotes(weekDates: [Date]) -> String {
        let policyMap = computeWeekOTDT(weekDates: weekDates)
        let total = weekDates.reduce(0.0) { sum, d in
            let key = Calendar.current.startOfDay(for: d)
            let policy = policyMap[key] ?? (0,0)
            return sum + policy.dt
        }
        return total > 0 ? formatHours(total) : ""
    }

    // Pay period capped OT/DT totals (use same logic as tables)
    private func payPeriodCappedOT() -> String {
        let calendar = Calendar.current
        let payRange = store.payPeriodRange
        let weeks = max(1, store.payPeriodWeeks)
        var totalOT: Double = 0.0

        // Iterate each week in the pay period and use the same logic as the overtime table
        for _ in 0..<weeks {
            let weekRange = store.weekRange(offset: 0)
            // Build the 7 dates for this week
            let weekDates = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: calendar.startOfDay(for: weekRange.lowerBound)) }
            let policyMap = computeWeekOTDT(weekDates: weekDates)

            for d in weekDates {
                // Only include days that fall within the actual pay period range
                let dayStart = calendar.startOfDay(for: d)
                guard payRange.contains(dayStart) else { continue }
                let policy = policyMap[dayStart] ?? (0,0)
                // Use policy OT capped at 4h per day; OC is already included in the policy via daily totals
                totalOT += min(policy.ot, 4.0)
            }
        }

        return totalOT > 0 ? formatHours(totalOT) : ""
    }

    private func payPeriodCappedDT() -> String {
        let calendar = Calendar.current
        let payRange = store.payPeriodRange
        let weeks = max(1, store.payPeriodWeeks)
        var totalDT: Double = 0.0

        for w in 0..<weeks {
            let weekRange = store.weekRange(offset: w)
            let weekDates = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: calendar.startOfDay(for: weekRange.lowerBound)) }
            let policyMap = computeWeekOTDT(weekDates: weekDates)

            for d in weekDates {
                let dayStart = calendar.startOfDay(for: d)
                guard payRange.contains(dayStart) else { continue }
                let policy = policyMap[dayStart] ?? (0,0)
                // OC contributions are already reflected in policy DT via daily totals
                totalDT += policy.dt
            }
        }

        return totalDT > 0 ? formatHours(totalDT) : ""
    }
    
    // Always-show variants for Summary Totals (display 0 or $0 instead of blank)
    private func payPeriodRegularPlusStatAlways() -> String {
        let totals = store.totals(for: store.payPeriodRange)
        let value = totals.regular + totals.stat
        return formatHours(value)
    }

    private func payPeriodOnCallAmountAlways() -> String {
        let totals = store.totals(for: store.payPeriodRange)
        let amount = totals.onCall
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = Locale.current.currency?.identifier ?? "USD"
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? "$0"
    }

    private func payPeriodOnCallCountAlways() -> String {
        let range = store.payPeriodRange
        let count = store.entries.filter { entry in
            range.contains(entry.date) && (store.category(for: entry.code) == .onCall)
        }.count
        let amount = Double(count) * 50.0
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = Locale.current.currency?.identifier ?? "USD"
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? "$0"
    }
    
    // Local computation of pay-period On Call stipend: $300 per week with any on-call activity
    private func payPeriodOnCallStipendAlways() -> String {
        let calendar = Calendar.current
        let payRange = store.payPeriodRange
        // Determine how many weeks in the pay period
        let weeks = max(1, store.payPeriodWeeks)
        var stipendWeeks = 0
        // Build week ranges starting at the pay period lowerBound
        var startOfWeek = calendar.startOfDay(for: payRange.lowerBound)
        for w in 0..<weeks {
            guard let endOfWeek = calendar.date(byAdding: .day, value: 7, to: startOfWeek) else { break }
            let weekRange = startOfWeek..<min(endOfWeek, payRange.upperBound)
            let hasOnCall = store.entries.contains { entry in
                weekRange.contains(entry.date) && (store.category(for: entry.code) == .onCall)
            }
            if hasOnCall { stipendWeeks += 1 }
            startOfWeek = endOfWeek
        }
        let amount = Double(stipendWeeks) * 300.0
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = Locale.current.currency?.identifier ?? "USD"
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? "$0"
    }

    private func totalHoursFor(day: Date, type: TimeEntryType) -> String {
        let entries = entriesFor(day: day)
        var totalHours = 0.0
        
        for entry in entries {
            let category: PayCategory = entry.isNightShift ? .night : store.category(for: entry.code)
            switch type {
            case .regular:
                if category == .regular { totalHours += entry.hours }
            case .night:
                if category == .night { totalHours += entry.hours }
            case .ot:
                if category == .ot { totalHours += entry.hours }
            case .dt:
                if category == .dt { totalHours += entry.hours }
            case .vacation:
                if category == .vacation { totalHours += entry.hours }
            case .stat:
                if category == .stat { totalHours += entry.hours }
            }
        }
        
        return totalHours > 0 ? formatHours(totalHours) : ""
    }

    private func totalHoursFor(type: TimeEntryType) -> String {
        let range = store.weekRange(offset: weekOffset)
        let totals = store.totals(for: range)
        let value: Double
        switch type {
        case .regular:  value = totals.regular
        case .night:    value = totals.night
        case .ot:       value = totals.ot
        case .dt:       value = totals.dt
        case .vacation: value = totals.vacation
        case .stat:     value = totals.stat
        }
        return value > 0 ? formatHours(value) : ""
    }
    
    private func totalHoursRegularIncludingStatForWeek() -> String {
        let totals = store.totals(for: store.weekRange(offset: weekOffset))
        let value = totals.regular + totals.stat
        return value > 0 ? formatHours(value) : ""
    }

    private func totalHoursRegularIncludingStatForPayPeriod() -> String {
        let totals = store.totals(for: store.payPeriodRange)
        let value = totals.regular + totals.stat
        return value > 0 ? formatHours(value) : ""
    }

    private func totalRegularTableHoursForWeek() -> String {
        let totals = store.totals(for: store.weekRange(offset: weekOffset))
        // The Regular Time table includes Regular + Vacation + Stat categories
        let value = totals.regular + totals.vacation + totals.stat
        return value > 0 ? formatHours(value) : ""
    }

    private func weekOnCallAmountString() -> String {
        let range = store.weekRange(offset: weekOffset)
        let hasOnCall = store.entries.contains { entry in
            range.contains(entry.date) && (store.category(for: entry.code) == .onCall)
        }
        guard hasOnCall else { return "" }
        let amount = 300.0
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = Locale.current.currency?.identifier ?? "USD"
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? ""
    }

    private func weekOnCallCountString() -> String {
        let range = store.weekRange(offset: weekOffset)
        let count = store.entries.filter { entry in
            range.contains(entry.date) && (store.category(for: entry.code) == .onCall)
        }.count
        let amount = Double(count) * 50.0
        guard amount > 0 else { return "" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = Locale.current.currency?.identifier ?? "USD"
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? ""
    }

    private func totalHoursForPayPeriod(type: TimeEntryType) -> String {
        let totals = store.totals(for: store.payPeriodRange)
        let value: Double
        switch type {
        case .regular:  value = totals.regular
        case .night:    value = totals.night
        case .ot:       value = totals.ot
        case .dt:       value = totals.dt
        case .vacation: value = totals.vacation
        case .stat:     value = totals.stat
        }
        return value > 0 ? formatHours(value) : ""
    }
    
    private func payPeriodOnCallAmountString() -> String {
        let totals = store.totals(for: store.payPeriodRange)
        let amount = totals.onCall // sum of $300 per week with any On Call
        guard amount > 0 else { return "" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = Locale.current.currency?.identifier ?? "USD"
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? ""
    }

    private func payPeriodOnCallCountString() -> String {
        let range = store.payPeriodRange
        let count = store.entries.filter { entry in
            range.contains(entry.date) && (store.category(for: entry.code) == .onCall)
        }.count
        let amount = Double(count) * 50.0
        guard amount > 0 else { return "" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = Locale.current.currency?.identifier ?? "USD"
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? ""
    }
    
    // MARK: - OT/DT policy computation (8/40 with Sunday rest and DT > 12)
    private func computeWeekOTDT(weekDates: [Date]) -> [Date: (ot: Double, dt: Double)] {
        let cal = Calendar.current
        // Step 1: get worked hours per day (exclude vacation, stat, onCall)
        var dayWorked: [Date: Double] = [:]
        for d in weekDates {
            let start = cal.startOfDay(for: d)
            let end = cal.date(byAdding: .day, value: 1, to: start)!
            let range = start..<end
            let entries = store.entries.filter { e in
                range.contains(e.date) && e.hours != 600 && !e.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            let worked = entries.reduce(0.0) { sum, e in
                let cat: PayCategory = e.isNightShift ? .night : store.category(for: e.code)
                // Count all worked categories toward daily OT/DT calculation (regular, night, ot, dt, onCall)
                if cat == .regular || cat == .night || cat == .ot || cat == .dt || cat == .onCall { 
                    return sum + e.hours 
                } else { 
                    return sum 
                }
            }
            dayWorked[start] = worked
        }

        // Step 2: apply daily rules using overtime policy
        var result: [Date: (ot: Double, dt: Double)] = [:]
        for d in weekDates {
            let key = cal.startOfDay(for: d)
            let hours = dayWorked[key] ?? 0
            
            // Use store's overtime policy thresholds
            let regularCap = store.overtimePolicy.dailyRegularCap ?? Double.greatestFiniteMagnitude
            let otUpper = store.overtimePolicy.dailyOTCap ?? regularCap
            let dtStart = store.overtimePolicy.dailyDTCap ?? otUpper
            
            let dailyOT = max(0.0, min(hours, dtStart) - regularCap)
            let dailyDT = max(0.0, hours - dtStart)
            result[key] = (ot: dailyOT, dt: dailyDT)
        }

        // Step 3: Sunday weekly rest = all hours on Sunday are at least OT (1.5x)
        if let sunday = weekDates.first {
            let sKey = cal.startOfDay(for: sunday)
            let hours = dayWorked[sKey] ?? 0
            // Ensure at least hours are counted as OT (but keep any DT already computed)
            let current = result[sKey] ?? (0,0)
            let dtStart = store.overtimePolicy.dailyDTCap ?? (store.overtimePolicy.dailyOTCap ?? Double.greatestFiniteMagnitude)
            let ensuredOT = max(current.ot, max(0.0, min(hours, dtStart)))
            let dt = current.dt
            result[sKey] = (ot: ensuredOT, dt: dt)
        }

        // Step 4: Weekly rule: hours over weekly cap become OT after daily rules
        if let weeklyCap = store.overtimePolicy.weeklyRegularCap {
            let totalWorked = dayWorked.values.reduce(0.0, +)
            let weeklyExcess = max(0.0, totalWorked - weeklyCap)
            if weeklyExcess > 0 {
                var remaining = weeklyExcess
                // Allocate from end of week backward so later days get weekly OT first
                for d in weekDates.reversed() {
                    if remaining <= 0 { break }
                    let key = cal.startOfDay(for: d)
                    let hours = dayWorked[key] ?? 0
                    var current = result[key] ?? (0,0)
                    // Regular capacity left on this day after daily OT/DT
                    let alreadyOTDT = current.ot + current.dt
                    let regLeft = max(0.0, hours - alreadyOTDT)
                    if regLeft > 0 {
                        let allocation = min(regLeft, remaining)
                        current.ot += allocation
                        remaining -= allocation
                        result[key] = current
                    }
                }
            }
        }

        return result
    }

    var body: some View {
        // A4 landscape: 297mm x 210mm = 842pt x 595pt - using smaller width to reduce blank space
        let pageSize = CGSize(width: 760, height: 595) // Increased width from 700 to 760 to accommodate Notes column
        let margin: CGFloat = 16

        let weekDates = self.weekDates
        let df = dateFormatter
        let weekdaysShort = ["Sun","Mon","Tues","Wed","Thurs","Fri","Sat"]
        let tableRightInset: CGFloat = margin + 12 // tweak this to nudge tables further left if needed
        let summaryHorizontalShift: CGFloat = 140 // move Summary Totals left into the red-box area

        _ = store.totals(for: store.weekRange(offset: weekOffset))
        let year = Calendar.current.component(.year, from: weekDates.first ?? store.weekStart)

        return VStack(spacing: 0) {
            // Header
            HStack(alignment: .top, spacing: 0) {
                // Left side - Logo and Employee info combined
                HStack(spacing: 20) {
                    // Logo
                    Group {
                        if let img = store.companyLogoImage {
                            img.resizable()
                        } else {
                            Image(store.companyLogoName ?? "logo").resizable()
                        }
                    }
                    .scaledToFit()
                    .frame(width: 44, height: 44)
                    
                    // Employee info
                    HStack(spacing: 8) { // Added spacing between fields
                        // Employee field
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Employee")
                                .font(.custom("Arial", size: 11))
                                .bold()
                            Rectangle()
                                .fill(Color.clear)
                                .frame(height: 20)
                                .overlay(
                                    VStack(spacing: 0) {
                                        Text(store.employeeName)
                                            .font(.custom("Arial", size: 10))
                                            .padding(.horizontal, 4)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        Spacer()
                                        Rectangle()
                                            .fill(Color.black)
                                            .frame(height: 1)
                                    }
                                )
                        }
                        .frame(width: 280)
                        
                        // PP # field
                        VStack(alignment: .leading, spacing: 2) {
                            Text("PP #")
                                .font(.custom("Arial", size: 11))
                                .bold()
                                .frame(maxWidth: .infinity, alignment: .center)
                            Rectangle()
                                .fill(Color.clear)
                                .frame(height: 20)
                                .overlay(
                                    VStack(spacing: 0) {
                                        Text(String(store.payPeriodNumber))
                                            .font(.custom("Arial", size: 10))
                                            .padding(.horizontal, 4)
                                            .frame(maxWidth: .infinity, alignment: .center)
                                        Spacer()
                                        Rectangle()
                                            .fill(Color.black)
                                            .frame(height: 1)
                                    }
                                )
                        }
                        .frame(width: 80)
                        
                        // Year field
                        VStack(alignment: .leading, spacing: 2) {
                            Text("YEAR")
                                .font(.custom("Arial", size: 11))
                                .bold()
                                .frame(maxWidth: .infinity, alignment: .center)
                            Rectangle()
                                .fill(Color.clear)
                                .frame(height: 20)
                                .overlay(
                                    VStack(spacing: 0) {
                                        Text(String(year))
                                            .font(.custom("Arial", size: 10))
                                            .padding(.horizontal, 4)
                                            .frame(maxWidth: .infinity, alignment: .center)
                                        Spacer()
                                        Rectangle()
                                            .fill(Color.black)
                                            .frame(height: 1)
                                    }
                                )
                        }
                        .frame(width: 80)
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal, margin)
            .padding(.top, 6)
            .frame(height: 56)

            // Main content - Compact layout with minimal spacing
            ZStack(alignment: .bottomTrailing) {
                // Left side - Main timesheet tables
                VStack(alignment: .leading, spacing: 0) {
                    // Regular Time section
                    HStack {
                        Text("Regular Time")
                            .font(.custom("Arial", size: 8))
                            .bold()
                        Spacer()
                    }
                    .padding(.bottom, 4)
                    
                    // Regular time table
                    regularTimeTable(weekDates: weekDates, weekdaysShort: weekdaysShort, df: df)
                    
                    Spacer().frame(height: 12)
                    
                    // Overtime & Double-Time section
                    HStack {
                        Text("Overtime & Double-Time")
                            .font(.custom("Arial", size: 8, relativeTo: .body))
                            .bold()
                        Spacer()
                    }
                    .padding(.bottom, 4)
                    
                    overtimeTable(weekDates: weekDates, weekdaysShort: weekdaysShort, df: df)
                }
                .padding(.leading, margin)
                .padding(.trailing, tableRightInset) // nudge tables left to align right edge with Summary panel

                // Summary Totals (only show on last week of pay period), aligned to the right edge of the tables
                if weekOffset == max(0, (store.payPeriodWeeks - 1)) {
                    VStack(spacing: 0) {
                        Text("Summary Totals")
                            .font(.custom("Arial", size: 10, relativeTo: .body))
                            .bold()
                            .frame(width: 90, height: 20)
                            .background(Color.white)
                            .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                        
                        summaryRow("Regular Time:", payPeriodRegularPlusStatAlways(), width: 90)
                        summaryRow("OT:", payPeriodCappedOT(), width: 90)
                        summaryRow("DT:", payPeriodCappedDT(), width: 90)
                        summaryRow("VP:", totalHoursForPayPeriod(type: .vacation), width: 90)
                        summaryRow("NS:", totalHoursForPayPeriod(type: .night), width: 90)
                        summaryRow("STAT:", totalHoursForPayPeriod(type: .stat), width: 90)
                        if store.onCallEnabled {
                            summaryRow("On Call:", payPeriodOnCallStipendAlways(), width: 90)
                            summaryRow("# of On Call", payPeriodOnCallCountAlways(), width: 90)
                        }
                    }
                    .padding(.trailing, margin + summaryHorizontalShift) // shift left toward red-box area
                    .padding(.bottom, margin)   // small bottom margin from the tables
                }
            }

            Spacer()
        }
        .background(Color.white)
        .frame(width: pageSize.width, height: pageSize.height)
    }
    
    // MARK: - Regular Time Table
    private func regularTimeTable(weekDates: [Date], weekdaysShort: [String], df: DateFormatter) -> some View {
        let dayColumnWidth: CGFloat = 60
        let dateColumnWidth: CGFloat = 60
        let laborCodeColumnWidth: CGFloat = 23
        let shiftHoursWidth: CGFloat = 30
        let notesWidth: CGFloat = 115
        
        return VStack(spacing: 0) {
            // Header row
            HStack(spacing: 0) {
                // Sun Date header
                VStack(alignment: .center, spacing: 1) {
                    Text("Sun")
                        .font(.custom("Arial", size: 8))
                        .bold()
                    Text("Date")
                        .font(.custom("Arial", size: 8))
                        .bold()
                }
                .frame(width: dayColumnWidth, height: 60)
                .background(Color.white)
                .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                
                // Date header
                Text(df.string(from: weekDates[0]))
                    .font(.custom("Arial", size: 8))
                    .bold()
                    .frame(width: dateColumnWidth, height: 60)
                    .background(Color.white)
                    .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                
                // 14 labor code columns with vertical text
                ForEach(0..<14, id: \.self) { colIndex in
                    // Get unique job/code combinations for the week including regular and night entries
                    let allEntries = weekDates.flatMap { regularEntriesFor(day: $0) + nightEntriesFor(day: $0) }
                    let uniqueEntries = Array(Set(allEntries.map { "\(displayJobText(for: $0))|\(displayLabourCode(for: $0))" }))
                        .sorted()
                        .map { combo -> (jobDisplay: String, code: String) in
                            let parts = combo.split(separator: "|", omittingEmptySubsequences: false)
                            let job = parts.indices.contains(0) ? String(parts[0]) : ""
                            let code = parts.indices.contains(1) ? String(parts[1]) : ""
                            return (jobDisplay: job, code: code)
                        }
                    
                    let jobDisplay = colIndex < uniqueEntries.count ? uniqueEntries[colIndex].jobDisplay : ""
                    let labourCode = colIndex < uniqueEntries.count ? uniqueEntries[colIndex].code : ""
                    
                    let isPlaceholder = jobDisplay.isEmpty && labourCode.isEmpty
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(labourCode.isEmpty ? "Labour Code:" : padToLength(labourCode, length: 10))
                            .font(.custom("Arial", size: 7))
                            .foregroundColor(.black)
                        Text(jobDisplay.isEmpty ? "Job:" : padToLength(jobDisplay, length: 10))
                            .font(.custom("Arial", size: 7))
                            .foregroundColor(.black)
                    }
                    .frame(width: 60, height: laborCodeColumnWidth, alignment: .trailing)
                    .rotationEffect(.degrees(-90))
                    .padding(.bottom, 0)
                    .offset(y: 0) // Changed from 3 to 0 per instructions
                    .offset(y: isPlaceholder ? -15 : -5) // Changed from -18 to -21 per instructions and per requested replacement
                    .frame(width: laborCodeColumnWidth, height: 60, alignment: .bottom)
                    .background(Color.white)
                    .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                }
                
                // Shift Hours header
                VStack(spacing: 1) {
                    Text("Shift")
                        .font(.custom("Arial", size: 7))
                        .bold()
                    Text("Hours")
                        .font(.custom("Arial", size: 7))
                        .bold()
                }
                .frame(width: shiftHoursWidth, height: 60)
                .background(Color.white)
                .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                
                // Notes header replaced with only the week label text (no "Regular Time:")
                Text(weekNumberString)
                    .font(.custom("Arial", size: 14))
                    .bold()
                    .frame(width: notesWidth, height: 60)
                    .background(Color.white)
                    .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
            }
            
            // Week rows
            ForEach(0..<7, id: \.self) { i in
                // ** Changed here per instructions: include night entries in daily rendering **
                let dayRegular = regularEntriesFor(day: weekDates[i])
                let dayNight = nightEntriesFor(day: weekDates[i])
                let dayEntries = dayRegular + dayNight
                let dayTotalHours = dayEntries.reduce(0.0) { $0 + $1.hours }
                
                HStack(spacing: 0) {
                    // Day column
                    VStack(alignment: .center, spacing: 1) {
                        Text(weekdaysShort[i])
                            .font(.custom("Arial", size: 8))
                            .bold()
                    }
                    .frame(width: dayColumnWidth, height: 22)
                    .background(Color.white)
                    .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                    
                    // Date column
                    Text(df.string(from: weekDates[i]))
                        .font(.custom("Arial", size: 8))
                        .frame(width: dateColumnWidth, height: 22)
                        .background(Color.white)
                        .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                    
                    // 14 data columns - display hours worked
                    ForEach(0..<14, id: \.self) { colIndex in
                        // Get unique job/code combinations for the week including regular and night entries
                        let allEntries = weekDates.flatMap { regularEntriesFor(day: $0) + nightEntriesFor(day: $0) }
                        let uniqueEntries = Array(Set(allEntries.map { "\(displayJobText(for: $0))|\(displayLabourCode(for: $0))" }))
                            .sorted()
                            .map { combo -> (jobDisplay: String, code: String) in
                                let parts = combo.split(separator: "|", omittingEmptySubsequences: false)
                                let job = parts.indices.contains(0) ? String(parts[0]) : ""
                                let code = parts.indices.contains(1) ? String(parts[1]) : ""
                                return (jobDisplay: job, code: code)
                            }
                        
                        let columnJobDisplay = colIndex < uniqueEntries.count ? uniqueEntries[colIndex].jobDisplay : ""
                        let columnLabourCode = colIndex < uniqueEntries.count ? uniqueEntries[colIndex].code : ""
                        
                        // Find matching entry for this day and column
                        let matchingEntry = dayEntries.first { entry in
                            displayJobText(for: entry) == columnJobDisplay && displayLabourCode(for: entry) == columnLabourCode
                        }
                        
                        ZStack(alignment: .center) {
                            if let entry = matchingEntry {
                                // Display hours worked centered
                                Text(formatHours(entry.hours))
                                    .font(.custom("Arial", size: 8))
                                    .lineLimit(1)
                                    .bold()
                            }
                        }
                        .frame(width: laborCodeColumnWidth, height: 22)
                        .background(Color.white)
                        .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                    }
                    
                    // Shift hours column - display total hours for day (3)
                    ZStack(alignment: .center) {
                        Text(dayTotalHours > 0 ? formatHours(dayTotalHours) : "")
                            .font(.custom("Arial", size: 8))
                    }
                    .frame(width: shiftHoursWidth, height: 22)
                    .background(Color.white)
                    .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                    
                    // Notes column - replaced with label only for first and second row plus extended labels for rows 2 to 6
                    if i == 0 {
                        ZStack {
                            Color.white
                            HStack(spacing: 4) {
                                Text("Office Use Only Table")
                                    .font(.custom("Arial", size: 10))
                                    .bold()
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.leading, 0)
                            }
                        }
                        .frame(width: notesWidth, height: 22)
                        .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                    } else if i == 1 {
                        ZStack {
                            Color.white
                            HStack {
                                Text("Reg Time:")
                                    .font(.custom("Arial", size: 8))
                                    .frame(width: 70, alignment: .leading)
                                    .padding(.leading, 4)
                                Text(totalRegularTableHoursForWeek())
                                    .font(.custom("Arial", size: 8))
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                        }
                        .frame(width: notesWidth, height: 22)
                        .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                    } else if i == 2 {
                        ZStack {
                            Color.white
                            HStack {
                                Text("OT:")
                                    .font(.custom("Arial", size: 8))
                                    .frame(width: 70, alignment: .leading)
                                    .padding(.leading, 4)
                                Text(weeklyOTForNotes(weekDates: weekDates))
                                    .font(.custom("Arial", size: 8))
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                        }
                        .frame(width: notesWidth, height: 22)
                        .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                    } else if i == 3 {
                        ZStack {
                            Color.white
                            HStack {
                                Text("DT:")
                                    .font(.custom("Arial", size: 8))
                                    .frame(width: 70, alignment: .leading)
                                    .padding(.leading, 4)
                                Text(weeklyDTForNotes(weekDates: weekDates))
                                    .font(.custom("Arial", size: 8))
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                        }
                        .frame(width: notesWidth, height: 22)
                        .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                    } else if i == 4 {
                        ZStack {
                            Color.white
                            HStack {
                                Text("VP:")
                                    .font(.custom("Arial", size: 8))
                                    .frame(width: 70, alignment: .leading)
                                    .padding(.leading, 4)
                                Text(totalHoursFor(type: .vacation))
                                    .font(.custom("Arial", size: 8))
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                        }
                        .frame(width: notesWidth, height: 22)
                        .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                    } else if i == 5 {
                        ZStack {
                            Color.white
                            HStack {
                                Text("NS:")
                                    .font(.custom("Arial", size: 8))
                                    .frame(width: 70, alignment: .leading)
                                    .padding(.leading, 4)
                                Text(totalHoursFor(type: .night))
                                    .font(.custom("Arial", size: 8))
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                        }
                        .frame(width: notesWidth, height: 22)
                        .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                    } else if i == 6 {
                        ZStack {
                            Color.white
                            HStack {
                                Text("STAT:")
                                    .font(.custom("Arial", size: 8))
                                    .frame(width: 70, alignment: .leading)
                                    .padding(.leading, 4)
                                Text(totalHoursFor(type: .stat))
                                    .font(.custom("Arial", size: 8))
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                        }
                        .frame(width: notesWidth, height: 22)
                        .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                    } else {
                        ZStack {
                            Color.white
                        }
                        .frame(width: notesWidth, height: 22)
                        .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                    }
                }
            }
            

            // Total Regular row
            HStack(spacing: 0) {
                Text("Regular Time:")
                    .font(.custom("Arial", size: 8))
                    .bold()
                    .frame(width: dayColumnWidth + dateColumnWidth, height: 18)
                    .background(Color.white)
                    .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                
                // Calculate column totals for regular time - NO CHANGE here to keep totals restricted to Regular table categories
                ForEach(0..<14, id: \.self) { colIndex in
                    // Get unique job/code combinations for the week including regular and night entries
                    let allEntries = weekDates.flatMap { regularEntriesFor(day: $0) + nightEntriesFor(day: $0) }
                    let uniqueEntries = Array(Set(allEntries.map { "\(displayJobText(for: $0))|\(displayLabourCode(for: $0))" }))
                        .sorted()
                        .map { combo -> (jobDisplay: String, code: String) in
                            let parts = combo.split(separator: "|", omittingEmptySubsequences: false)
                            let job = parts.indices.contains(0) ? String(parts[0]) : ""
                            let code = parts.indices.contains(1) ? String(parts[1]) : ""
                            return (jobDisplay: job, code: code)
                        }
                    
                    let columnJobDisplay = colIndex < uniqueEntries.count ? uniqueEntries[colIndex].jobDisplay : ""
                    let columnLabourCode = colIndex < uniqueEntries.count ? uniqueEntries[colIndex].code : ""
                    
                    // Calculate total hours for this column across all days
                    let columnTotal = weekDates.reduce(0.0) { total, date in
                        // ** Keep only regular entries here for totals (no change) **
                        let dayEntries = regularEntriesFor(day: date)
                        let matchingEntry = dayEntries.first { entry in
                            displayJobText(for: entry) == columnJobDisplay && displayLabourCode(for: entry) == columnLabourCode
                        }
                        return total + (matchingEntry?.hours ?? 0.0)
                    }
                    
                    ZStack(alignment: .center) {
                        Text(columnTotal > 0 ? formatHours(columnTotal) : "")
                            .font(.system(size: 8))
                            .bold()
                    }
                    .frame(width: laborCodeColumnWidth, height: 18)
                    .background(Color.white)
                    .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                }
                
                Text(totalRegularTableHoursForWeek())
                    .font(.custom("Arial", size: 8))
                    .bold()
                    .frame(width: shiftHoursWidth, height: 18)
                    .background(Color.white)
                    .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                
                if store.onCallEnabled {
                    ZStack {
                        Color.white
                        HStack {
                            Text("On Call:")
                                .font(.custom("Arial", size: 8))
                                .frame(width: 70, alignment: .leading)
                                .padding(.leading, 4)
                            Text(weekOnCallAmountString())
                                .font(.custom("Arial", size: 8))
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                    .frame(width: notesWidth, height: 18)
                    .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                } else {
                    ZStack { Color.white }
                        .frame(width: notesWidth, height: 18)
                        .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                }
            }
            
            // Total Night row
            HStack(spacing: 0) {
                Text("TOTAL NIGHT")
                    .font(.custom("Arial", size: 8))
                    .bold()
                    .frame(width: dayColumnWidth + dateColumnWidth, height: 18)
                    .background(Color.white)
                    .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                ForEach(0..<14, id: \.self) { colIndex in
                    let allEntries = weekDates.flatMap { regularEntriesFor(day: $0) + nightEntriesFor(day: $0) }
                    let uniqueEntries = Array(Set(allEntries.map { "\(displayJobText(for: $0))|\(displayLabourCode(for: $0))" }))
                        .sorted()
                        .map { combo -> (jobDisplay: String, code: String) in
                            let parts = combo.split(separator: "|", omittingEmptySubsequences: false)
                            let job = parts.indices.contains(0) ? String(parts[0]) : ""
                            let code = parts.indices.contains(1) ? String(parts[1]) : ""
                            return (jobDisplay: job, code: code)
                        }
                    let columnJobDisplay = colIndex < uniqueEntries.count ? uniqueEntries[colIndex].jobDisplay : ""
                    let columnLabourCode = colIndex < uniqueEntries.count ? uniqueEntries[colIndex].code : ""
                    let columnTotal = weekDates.reduce(0.0) { total, date in
                        let dayEntries = nightEntriesFor(day: date)
                        let matchingEntry = dayEntries.first { entry in
                            displayJobText(for: entry) == columnJobDisplay && displayLabourCode(for: entry) == columnLabourCode
                        }
                        return total + (matchingEntry?.hours ?? 0.0)
                    }
                    ZStack(alignment: .center) {
                        Text(columnTotal > 0 ? formatHours(columnTotal) : "")
                            .font(.system(size: 8))
                            .bold()
                    }
                    .frame(width: laborCodeColumnWidth, height: 18)
                    .background(Color.white)
                    .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                }
                Text(totalHoursFor(type: .night))
                    .font(.custom("Arial", size: 8))
                    .bold()
                    .frame(width: shiftHoursWidth, height: 18)
                    .background(Color.white)
                    .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                if store.onCallEnabled {
                    ZStack {
                        Color.white
                        HStack {
                            Text("# On Call:")
                                .font(.custom("Arial", size: 8))
                                .frame(width: 70, alignment: .leading)
                                .padding(.leading, 4)
                            Text(weekOnCallCountString())
                                .font(.custom("Arial", size: 8))
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                    .frame(width: notesWidth, height: 18)
                    .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                } else {
                    ZStack { Color.white }
                        .frame(width: notesWidth, height: 18)
                        .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                }
            }
        }
    }
    
    // MARK: - Overtime Table
    private func overtimeTable(weekDates: [Date], weekdaysShort: [String], df: DateFormatter) -> some View {
        let dayColumnWidth: CGFloat = 60
        let dateColumnWidth: CGFloat = 60
        let laborCodeColumnWidth: CGFloat = 23
        let overtimeWidth: CGFloat = 40
        let doubleTimeWidth: CGFloat = 40
        
        let policyMap = computeWeekOTDT(weekDates: weekDates)
        
        return VStack(spacing: 0) {
            // Header row
            HStack(spacing: 0) {
                // Date header
                Text("Date:")
                    .font(.custom("Arial", size: 8))
                    .bold()
                    .frame(width: dayColumnWidth, height: 60)
                    .background(Color.white)
                    .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                
                // Date value
                Text(df.string(from: weekDates[0]))
                    .font(.custom("Arial", size: 8))
                    .bold()
                    .frame(width: dateColumnWidth, height: 60)
                    .background(Color.white)
                    .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                
                // 8 labor code columns with vertical text
                ForEach(0..<8, id: \.self) { colIndex in
                    // Get unique job/code combinations for the week
                    let allOvertimeEntries = weekDates.flatMap { overtimeEntriesFor(day: $0) }
                    let uniqueEntries = Array(Set(allOvertimeEntries.map { "\(displayJobNumber(for: $0))|\(displayLabourCode(for: $0))" }))
                        .sorted()
                        .map { combo -> (jobNumber: String, code: String) in
                            let parts = combo.split(separator: "|", omittingEmptySubsequences: false)
                            let job = parts.indices.contains(0) ? String(parts[0]) : ""
                            let code = parts.indices.contains(1) ? String(parts[1]) : ""
                            return (job, code)
                        }
                    
                    let jobNumber = colIndex < uniqueEntries.count ? uniqueEntries[colIndex].jobNumber : ""
                    let labourCode = colIndex < uniqueEntries.count ? uniqueEntries[colIndex].code : ""
                    
                    let isPlaceholder = jobNumber.isEmpty && labourCode.isEmpty
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(labourCode.isEmpty ? "Labour Code:" : padToLength(labourCode, length: 10))
                            .font(.custom("Arial", size: 7))
                            .foregroundColor(.black)
                        Text(jobNumber.isEmpty ? "Job:" : padToLength(jobNumber, length: 8))
                            .font(.custom("Arial", size: 7))
                            .foregroundColor(.black)
                    }
                    .frame(width: 60, height: laborCodeColumnWidth, alignment: .trailing)
                    .rotationEffect(.degrees(-90))
                    .padding(.bottom, 0)
                    .offset(y: 0) // Changed from 3 to 0 per instructions
                    .offset(y: isPlaceholder ? -15 : -5) // Changed from -18 to -21 per instructions and per requested replacement
                    .frame(width: laborCodeColumnWidth, height: 60, alignment: .bottom)
                    .background(Color.white)
                    .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                }
                
                // Overtime header
                Text("Overtime")
                    .font(.custom("Arial", size: 7))
                    .bold()
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
                    .rotationEffect(.degrees(-90))
                    .frame(width: overtimeWidth, height: 60, alignment: .center)
                    .background(Color.white)
                    .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                    .padding(.bottom, 0)
                
                // Double-Time header
                Text("Double Time")
                    .font(.custom("Arial", size: 7))
                    .bold()
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
                    .fixedSize()  // ← Add this to prevent truncation
                    .rotationEffect(.degrees(-90))
                    .frame(width: doubleTimeWidth, height: 60, alignment: .center)
                    .background(Color.white)
                    .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
            }
            
            // Week rows
            ForEach(0..<7, id: \.self) { i in
                let day = weekDates[i]
                // Calculate day overtime hours using policy rules (8/12 hour daily limits)
                let dayOvertimeEntries: [Entry] = overtimeEntriesFor(day: day)
                let policy = policyMap[Calendar.current.startOfDay(for: day)] ?? (0,0)
                
                // Use policy-derived values so any OC pushing the day past 12h becomes DT
                let dayOvertimeHours = min(policy.ot, 4.0)
                let dayDoubleTimeHours = policy.dt
                
                HStack(spacing: 0) {
                    // Day column
                    Text(weekdaysShort[i])
                        .font(.custom("Arial", size: 8))
                        .bold()
                        .frame(width: dayColumnWidth, height: 22)
                        .background(Color.white)
                        .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                    
                    // Date column
                    Text(df.string(from: weekDates[i]))
                        .font(.custom("Arial", size: 8))
                        .frame(width: dateColumnWidth, height: 22)
                        .background(Color.white)
                        .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                    
                    // 8 data columns - display hours worked
                    ForEach(0..<8, id: \.self) { colIndex in
                        // Get unique job/code combinations for the week
                        let allOvertimeEntries = weekDates.flatMap { overtimeEntriesFor(day: $0) }
                        let uniqueEntries = Array(Set(allOvertimeEntries.map { "\(displayJobNumber(for: $0))|\(displayLabourCode(for: $0))" }))
                            .sorted()
                            .map { combo -> (jobNumber: String, code: String) in
                                let parts = combo.split(separator: "|", omittingEmptySubsequences: false)
                                let job = parts.indices.contains(0) ? String(parts[0]) : ""
                                let code = parts.indices.contains(1) ? String(parts[1]) : ""
                                return (job, code)
                            }
                        
                        let columnJobNumber = colIndex < uniqueEntries.count ? uniqueEntries[colIndex].jobNumber : ""
                        let columnLabourCode = colIndex < uniqueEntries.count ? uniqueEntries[colIndex].code : ""
                        
                        // Find matching entry for this day and column
                        let matchingEntry = dayOvertimeEntries.first { entry in
                            displayJobNumber(for: entry) == columnJobNumber && displayLabourCode(for: entry) == columnLabourCode
                        }
                        
                        ZStack(alignment: .center) {
                            if let entry = matchingEntry {
                                // Display hours worked centered
                                Text(formatHours(entry.hours))
                                    .font(.custom("Arial", size: 8))
                                    .lineLimit(1)
                                    .bold()
                            }
                        }
                        .frame(width: laborCodeColumnWidth, height: 22)
                        .background(Color.white)
                        .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                    }
                    
                    // Overtime column - centered
                    ZStack(alignment: .center) {
                        Text(dayOvertimeHours > 0 ? formatHours(dayOvertimeHours) : "")
                            .font(.custom("Arial", size: 8))
                    }
                    .frame(width: overtimeWidth, height: 22)
                    .background(Color.white)
                    .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                    
                    // Double-Time column - centered
                    ZStack(alignment: .center) {
                        Text(dayDoubleTimeHours > 0 ? formatHours(dayDoubleTimeHours) : "")
                            .font(.custom("Arial", size: 8))
                    }
                    .frame(width: doubleTimeWidth, height: 22)
                    .background(Color.white)
                    .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                }
            }
            
            // Total Overtime row
            HStack(spacing: 0) {
                // Label spanning the first two columns (day + date)
                Text("TOTAL OVERTIME")
                    .font(.custom("Arial", size: 8))
                    .bold()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 4)
                    .frame(width: dayColumnWidth + dateColumnWidth, height: 18)
                    .background(Color.white)
                    .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                
                // Calculate column totals for overtime
                ForEach(0..<8, id: \.self) { colIndex in
                    // Get unique job/code combinations for the week
                    let allOvertimeEntries = weekDates.flatMap { overtimeEntriesFor(day: $0) }
                    let uniqueEntries = Array(Set(allOvertimeEntries.map { "\(displayJobNumber(for: $0))|\(displayLabourCode(for: $0))" }))
                        .sorted()
                        .map { combo -> (jobNumber: String, code: String) in
                            let parts = combo.split(separator: "|", omittingEmptySubsequences: false)
                            let job = parts.indices.contains(0) ? String(parts[0]) : ""
                            let code = parts.indices.contains(1) ? String(parts[1]) : ""
                            return (job, code)
                        }
                    
                    let columnJobNumber = colIndex < uniqueEntries.count ? uniqueEntries[colIndex].jobNumber : ""
                    let columnLabourCode = colIndex < uniqueEntries.count ? uniqueEntries[colIndex].code : ""
                    
                    // Calculate total hours for this column across all days
                    let columnTotal = weekDates.reduce(0.0) { total, date in
                        let dayEntries = overtimeEntriesFor(day: date)
                        let matchingEntry = dayEntries.first { entry in
                            displayJobNumber(for: entry) == columnJobNumber && displayLabourCode(for: entry) == columnLabourCode
                        }
                        return total + (matchingEntry?.hours ?? 0.0)
                    }
                    
                    ZStack(alignment: .center) {
                        Text(columnTotal > 0 ? formatHours(columnTotal) : "")
                            .font(.system(size: 8))
                            .bold()
                    }
                    .frame(width: laborCodeColumnWidth, height: 18)
                    .background(Color.white)
                    .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                }
                
                // Calculate total overtime hours using policy rules (matching daily calculations)
                let weeklyOTTotal = weekDates.reduce(0.0) { sum, d in
                    let key = Calendar.current.startOfDay(for: d)
                    let policy = policyMap[key] ?? (0,0)
                    return sum + min(policy.ot, 4.0)
                }
                Text(weeklyOTTotal > 0 ? formatHours(weeklyOTTotal) : "")
                    .font(.custom("Arial", size: 8))
                    .bold()
                    .frame(width: overtimeWidth, height: 18)
                    .background(Color.white)
                    .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                
                // Calculate total double-time hours (for consistency, using policy-based calculation as DT is more complex)
                let weeklyDTTotal = weekDates.reduce(0.0) { sum, d in
                    let key = Calendar.current.startOfDay(for: d)
                    let policy = policyMap[key] ?? (0,0)
                    return sum + policy.dt
                }
                Text(weeklyDTTotal > 0 ? formatHours(weeklyDTTotal) : "")
                    .font(.custom("Arial", size: 8))
                    .bold()
                    .frame(width: doubleTimeWidth, height: 18)
                    .background(Color.white)
                    .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
            }
            
            // Approved by row
            HStack(spacing: 0) {
                // Merged Day + Date cell with label
                HStack {
                    Text("Approved by:")
                        .font(.custom("Arial", size: 8))
                        .padding(.leading, 4)
                    Spacer()
                }
                .frame(width: dayColumnWidth + dateColumnWidth, height: 18)
                .background(Color.white)
                .overlay(Rectangle().stroke(Color.black, lineWidth: 1))

                // 8 labor code columns (empty)
                ForEach(0..<8, id: \.self) { _ in
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: laborCodeColumnWidth, height: 18)
                        .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                }
                
                // Overtime column (empty)
                Rectangle()
                    .fill(Color.white)
                    .frame(width: overtimeWidth, height: 18)
                    .overlay(Rectangle().stroke(Color.black, lineWidth: 1))

                // Double-Time column (empty)
                Rectangle()
                    .fill(Color.white)
                    .frame(width: doubleTimeWidth, height: 18)
                    .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
            }
        }
    }
}

// MARK: - Helpers
private func summaryRow(_ label: String, _ value: String, width: CGFloat) -> some View {
    HStack(spacing: 0) {
        Text(label)
            .font(.custom("Arial", size: 8))
            .frame(width: 60, alignment: .leading)
            .padding(.leading, 4)
        Text(value)
            .font(.custom("Arial", size: 8))
            .frame(maxWidth: .infinity, alignment: .center)
    }
    .frame(width: width, height: 16)
    .background(Color.white)
    .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
}
#Preview {
    TimecardPDFView()
        .environmentObject(TimecardStore.sampleStore)
}
