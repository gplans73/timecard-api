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
        return entry.jobNumber
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

        // Consider all entries for the day; no job-number requirement for OT/DT purposes
        let dayEntries = store.entries.filter { entry in
            dayRange.contains(entry.date) &&
            entry.hours != 600 &&
            !entry.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        var overtime = 0.0
        var doubleTime = 0.0
        for entry in dayEntries {
            let category: PayCategory = entry.isNightShift ? .night : store.category(for: entry.code)
            if entry.isOvertime || category == .ot || category == .onCall {
                overtime += entry.hours
            } else if category == .dt {
                doubleTime += entry.hours
            }
        }
        return (overtime: overtime, doubleTime: doubleTime)
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
        let totals = store.totals(for: store.weekRange(offset: weekOffset))
        let amount = totals.onCall // flat $300 per week if any On Call in that week
        guard amount > 0 else { return "" }
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

    var body: some View {
        // A4 landscape: 297mm x 210mm = 842pt x 595pt - using smaller width to reduce blank space
        let pageSize = CGSize(width: 700, height: 595) // Reduced from 842 to 700
        let margin: CGFloat = 16

        let weekDates = self.weekDates
        let df = dateFormatter
        let weekdaysShort = ["Sun","Mon","Tues","Wed","Thurs","Fri","Sat"]

        _ = store.totals(for: store.weekRange(offset: weekOffset))
        let year = Calendar.current.component(.year, from: weekDates.first ?? store.weekStart)

        return ZStack {
            Color.white

            VStack(spacing: 0) {
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
                        .frame(width: 40, height: 40)
                        
                        // Employee info
                        HStack(spacing: 8) { // Added spacing between fields
                            // Employee field
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Employee")
                                    .font(.system(size: 11))
                                    .bold()
                                Rectangle()
                                    .fill(Color.clear)
                                    .frame(height: 20)
                                    .overlay(
                                        VStack(spacing: 0) {
                                            Text(store.employeeName)
                                                .font(.system(size: 10))
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
                                    .font(.system(size: 11))
                                    .bold()
                                    .frame(maxWidth: .infinity, alignment: .center)
                                Rectangle()
                                    .fill(Color.clear)
                                    .frame(height: 20)
                                    .overlay(
                                        VStack(spacing: 0) {
                                            Text("1")
                                                .font(.system(size: 10))
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
                                    .font(.system(size: 11))
                                    .bold()
                                    .frame(maxWidth: .infinity, alignment: .center)
                                Rectangle()
                                    .fill(Color.clear)
                                    .frame(height: 20)
                                    .overlay(
                                        VStack(spacing: 0) {
                                            Text(String(year))
                                                .font(.system(size: 10))
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
                .padding(.top, margin)
                .frame(height: 60)

                // Main content - Compact layout with minimal spacing
                HStack(alignment: .top, spacing: 8) {
                    // Left side - Main timesheet tables
                    VStack(alignment: .leading, spacing: 0) {
                        // Regular Time section
                        HStack {
                            Text("Regular Time")
                                .font(.system(size: 12, weight: .bold))
                            Spacer()
                        }
                        .padding(.bottom, 4)
                        
                        // Regular time table
                        regularTimeTable(weekDates: weekDates, weekdaysShort: weekdaysShort, df: df)
                        
                        Spacer().frame(height: 12)
                        
                        // Overtime & Double-Time section
                        HStack {
                            Text("Overtime & Double-Time")
                                .font(.system(size: 12, weight: .bold))
                            Spacer()
                        }
                        .padding(.bottom, 4)
                        
                        overtimeTable(weekDates: weekDates, weekdaysShort: weekdaysShort, df: df)
                    }
                    .padding(.leading, margin)
                    
                    // Right side panels - positioned close to tables
                    VStack(spacing: 0) {
                        // Week number
                        Text(weekNumberString)
                            .font(.system(size: 14, weight: .bold))
                            .frame(width: 120, height: 30)
                            .background(Color.white)
                            .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                        
                        // Office Use Only
                        VStack(spacing: 0) {
                            Text("Office Use Only")
                                .font(.system(size: 10, weight: .bold))
                                .frame(width: 120, height: 20)
                                .background(Color.gray.opacity(0.3))
                                .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                            
                            summaryRow("Regular Time:", totalHoursRegularIncludingStatForWeek(), width: 120)
                            summaryRow("OT:", totalHoursFor(type: .ot), width: 120)
                            summaryRow("DT:", totalHoursFor(type: .dt), width: 120)
                            summaryRow("VP:", totalHoursFor(type: .vacation), width: 120)
                            summaryRow("NS:", totalHoursFor(type: .night), width: 120)
                            summaryRow("STAT:", totalHoursFor(type: .stat), width: 120)
                            if store.onCallEnabled {
                                summaryRow("On Call:", weekOnCallAmountString(), width: 120)
                                summaryRow("# of On Call", weekOnCallCountString(), width: 120)
                            }
                        }
                        
                        Spacer().frame(height: 12)
                        
                        // Summary Totals (only show on last week of pay period)
                        if weekOffset == max(0, (store.payPeriodWeeks - 1)) {
                            VStack(spacing: 0) {
                                Text("Summary Totals")
                                    .font(.system(size: 10, weight: .bold))
                                    .frame(width: 120, height: 20)
                                    .background(Color.gray.opacity(0.3))
                                    .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                                
                                summaryRow("Regular Time:", totalHoursRegularIncludingStatForPayPeriod(), width: 120)
                                summaryRow("OT:", totalHoursForPayPeriod(type: .ot), width: 120)
                                summaryRow("DT:", totalHoursForPayPeriod(type: .dt), width: 120)
                                summaryRow("VP:", totalHoursForPayPeriod(type: .vacation), width: 120)
                                summaryRow("NS:", totalHoursForPayPeriod(type: .night), width: 120)
                                summaryRow("STAT:", totalHoursForPayPeriod(type: .stat), width: 120)
                                if store.onCallEnabled {
                                    summaryRow("On Call:", payPeriodOnCallAmountString(), width: 120)
                                    summaryRow("# of On Call", payPeriodOnCallCountString(), width: 120)
                                }
                            }
                        }
                        
                        Spacer()
                    }
                    .frame(width: 120)
                    .padding(.trailing, margin) // Small padding from right edge
                }

                Spacer()
            }
            .frame(width: pageSize.width, height: pageSize.height)
        }
    }
    
    // MARK: - Regular Time Table
    private func regularTimeTable(weekDates: [Date], weekdaysShort: [String], df: DateFormatter) -> some View {
        let dayColumnWidth: CGFloat = 60
        let dateColumnWidth: CGFloat = 60
        let laborCodeColumnWidth: CGFloat = 23
        let shiftHoursWidth: CGFloat = 30
        
        return VStack(spacing: 0) {
            // Header row
            HStack(spacing: 0) {
                // Sun Date header
                VStack(alignment: .center, spacing: 1) {
                    Text("Sun")
                        .font(.system(size: 8))
                        .bold()
                    Text("Date")
                        .font(.system(size: 8))
                        .bold()
                }
                .frame(width: dayColumnWidth, height: 50)
                .background(Color.white)
                .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                
                // Date header
                Text(df.string(from: weekDates[0]))
                    .font(.system(size: 8))
                    .bold()
                    .frame(width: dateColumnWidth, height: 50)
                    .background(Color.white)
                    .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                
                // 14 labor code columns with vertical text
                ForEach(0..<14, id: \.self) { colIndex in
                    // Get unique job/code combinations for the week
                    let allEntries = weekDates.flatMap { regularEntriesFor(day: $0) + nightEntriesFor(day: $0) }
                    let uniqueEntries = Array(Set(allEntries.map { "\(displayJobText(for: $0))|\($0.code)" }))
                        .sorted()
                        .map { combo -> (jobDisplay: String, code: String) in
                            let parts = combo.split(separator: "|")
                            return (String(parts[0]), String(parts[1]))
                        }
                    
                    let jobDisplay = colIndex < uniqueEntries.count ? uniqueEntries[colIndex].jobDisplay : ""
                    let labourCode = colIndex < uniqueEntries.count ? uniqueEntries[colIndex].code : ""
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(labourCode.isEmpty ? "Labour Code:" : labourCode)
                            .font(.system(size: 5))
                            .foregroundColor(.black)
                        Text(jobDisplay.isEmpty ? "Job:" : jobDisplay)
                            .font(.system(size: 5))
                            .foregroundColor(.black)
                    }
                    .rotationEffect(.degrees(-90))
                    .fixedSize()
                    .padding(.bottom, 15)
                    .frame(width: laborCodeColumnWidth, height: 50, alignment: .bottom)
                    .background(Color.white)
                    .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                }
                
                // Shift Hours header
                VStack(spacing: 1) {
                    Text("Shift")
                        .font(.system(size: 7))
                        .bold()
                    Text("Hours")
                        .font(.system(size: 7))
                        .bold()
                }
                .frame(width: shiftHoursWidth, height: 50)
                .background(Color.white)
                .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
            }
            
            // Week rows
            ForEach(0..<7, id: \.self) { i in
                let dayEntries = regularEntriesFor(day: weekDates[i])
                let dayTotalHours = dayEntries.reduce(0.0) { $0 + $1.hours }
                
                HStack(spacing: 0) {
                    // Day column
                    VStack(alignment: .center, spacing: 1) {
                        Text(weekdaysShort[i])
                            .font(.system(size: 8))
                            .bold()
                    }
                    .frame(width: dayColumnWidth, height: 22)
                    .background(Color.white)
                    .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                    
                    // Date column
                    Text(df.string(from: weekDates[i]))
                        .font(.system(size: 8))
                        .frame(width: dateColumnWidth, height: 22)
                        .background(Color.white)
                        .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                    
                    // 14 data columns - display hours worked
                    ForEach(0..<14, id: \.self) { colIndex in
                        // Get unique job/code combinations for the week
                        let allEntries = weekDates.flatMap { regularEntriesFor(day: $0) + nightEntriesFor(day: $0) }
                        let uniqueEntries = Array(Set(allEntries.map { "\(displayJobText(for: $0))|\($0.code)" }))
                            .sorted()
                            .map { combo -> (jobDisplay: String, code: String) in
                                let parts = combo.split(separator: "|")
                                return (String(parts[0]), String(parts[1]))
                            }
                        
                        let columnJobDisplay = colIndex < uniqueEntries.count ? uniqueEntries[colIndex].jobDisplay : ""
                        let columnLabourCode = colIndex < uniqueEntries.count ? uniqueEntries[colIndex].code : ""
                        
                        // Find matching entry for this day and column
                        let matchingEntry = dayEntries.first { entry in
                            displayJobText(for: entry) == columnJobDisplay && entry.code == columnLabourCode
                        }
                        
                        VStack(spacing: 1) {
                            if let entry = matchingEntry {
                                // Display hours worked
                                Text(formatHours(entry.hours))
                                    .font(.system(size: 6))
                                    .lineLimit(1)
                                    .bold()
                            }
                        }
                        .frame(width: laborCodeColumnWidth, height: 22)
                        .background(Color.white)
                        .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                    }
                    
                    // Shift hours column - display total hours for day (3)
                    Text(dayTotalHours > 0 ? formatHours(dayTotalHours) : "")
                        .font(.system(size: 6))
                        .frame(width: shiftHoursWidth, height: 22)
                        .background(Color.white)
                        .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                }
            }
            
            // Total Regular row
            HStack(spacing: 0) {
                Text("TOTAL REGULAR")
                    .font(.system(size: 8))
                    .bold()
                    .frame(width: dayColumnWidth + dateColumnWidth, height: 18)
                    .background(Color.white)
                    .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                
                // Calculate column totals for regular time
                ForEach(0..<14, id: \.self) { colIndex in
                    // Get unique job/code combinations for the week
                    let allEntries = weekDates.flatMap { regularEntriesFor(day: $0) + nightEntriesFor(day: $0) }
                    let uniqueEntries = Array(Set(allEntries.map { "\(displayJobText(for: $0))|\($0.code)" }))
                        .sorted()
                        .map { combo -> (jobDisplay: String, code: String) in
                            let parts = combo.split(separator: "|")
                            return (String(parts[0]), String(parts[1]))
                        }
                    
                    let columnJobDisplay = colIndex < uniqueEntries.count ? uniqueEntries[colIndex].jobDisplay : ""
                    let columnLabourCode = colIndex < uniqueEntries.count ? uniqueEntries[colIndex].code : ""
                    
                    // Calculate total hours for this column across all days
                    let columnTotal = weekDates.reduce(0.0) { total, date in
                        let dayEntries = regularEntriesFor(day: date)
                        let matchingEntry = dayEntries.first { entry in
                            displayJobText(for: entry) == columnJobDisplay && entry.code == columnLabourCode
                        }
                        return total + (matchingEntry?.hours ?? 0.0)
                    }
                    
                    Text(columnTotal > 0 ? formatHours(columnTotal) : "")
                        .font(.system(size: 6))
                        .bold()
                        .frame(width: laborCodeColumnWidth, height: 18)
                        .background(Color.white)
                        .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                }
                
                Text(totalRegularTableHoursForWeek())
                    .font(.system(size: 6))
                    .bold()
                    .frame(width: shiftHoursWidth, height: 18)
                    .background(Color.white)
                    .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
            }
            
            // Total Night row
            HStack(spacing: 0) {
                Text("TOTAL NIGHT")
                    .font(.system(size: 8))
                    .bold()
                    .frame(width: dayColumnWidth + dateColumnWidth, height: 18)
                    .background(Color.white)
                    .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                
                ForEach(0..<14, id: \.self) { colIndex in
                    // Get unique job/code combinations for the week (regular + night) to align columns
                    let allEntries = weekDates.flatMap { regularEntriesFor(day: $0) + nightEntriesFor(day: $0) }
                    let uniqueEntries = Array(Set(allEntries.map { "\(displayJobText(for: $0))|\($0.code)" }))
                        .sorted()
                        .map { combo -> (jobDisplay: String, code: String) in
                            let parts = combo.split(separator: "|")
                            return (String(parts[0]), String(parts[1]))
                        }

                    let columnJobDisplay = colIndex < uniqueEntries.count ? uniqueEntries[colIndex].jobDisplay : ""
                    let columnLabourCode = colIndex < uniqueEntries.count ? uniqueEntries[colIndex].code : ""

                    // Calculate total NIGHT hours for this column across all days
                    let columnTotal = weekDates.reduce(0.0) { total, date in
                        let dayEntries = nightEntriesFor(day: date)
                        let matchingEntry = dayEntries.first { entry in
                            displayJobText(for: entry) == columnJobDisplay && entry.code == columnLabourCode
                        }
                        return total + (matchingEntry?.hours ?? 0.0)
                    }

                    Text(columnTotal > 0 ? formatHours(columnTotal) : "")
                        .font(.system(size: 6))
                        .bold()
                        .frame(width: laborCodeColumnWidth, height: 18)
                        .background(Color.white)
                        .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                }
                
                Text(totalHoursFor(type: .night))
                    .font(.system(size: 6))
                    .bold()
                    .frame(width: shiftHoursWidth, height: 18)
                    .background(Color.white)
                    .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
            }
        }
    }
    
    // MARK: - Overtime Table
    private func overtimeTable(weekDates: [Date], weekdaysShort: [String], df: DateFormatter) -> some View {
        let dayColumnWidth: CGFloat = 60
        let dateColumnWidth: CGFloat = 60
        let laborCodeColumnWidth: CGFloat = 23
        let overtimeWidth: CGFloat = 30
        let doubleTimeWidth: CGFloat = 30
        
        return VStack(spacing: 0) {
            // Header row
            HStack(spacing: 0) {
                // Date header
                Text("Date:")
                    .font(.system(size: 8))
                    .bold()
                    .frame(width: dayColumnWidth, height: 50)
                    .background(Color.white)
                    .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                
                // Date value
                Text(df.string(from: weekDates[0]))
                    .font(.system(size: 8))
                    .bold()
                    .frame(width: dateColumnWidth, height: 50)
                    .background(Color.white)
                    .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                
                // 8 labor code columns with vertical text
                ForEach(0..<8, id: \.self) { colIndex in
                    // Get unique job/code combinations for the week
                    let allOvertimeEntries = weekDates.flatMap { overtimeEntriesFor(day: $0) }
                    let uniqueEntries = Array(Set(allOvertimeEntries.map { "\($0.jobNumber)|\($0.code)" }))
                        .sorted()
                        .map { combo -> (jobNumber: String, code: String) in
                            let parts = combo.split(separator: "|")
                            return (String(parts[0]), String(parts[1]))
                        }
                    
                    let jobNumber = colIndex < uniqueEntries.count ? uniqueEntries[colIndex].jobNumber : ""
                    let labourCode = colIndex < uniqueEntries.count ? uniqueEntries[colIndex].code : ""
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(labourCode.isEmpty ? "Labour Code:" : labourCode)
                            .font(.system(size: 6))
                            .foregroundColor(.black)
                        Text(jobNumber.isEmpty ? "Job:" : jobNumber)
                            .font(.system(size: 6))
                            .foregroundColor(.black)
                    }
                    .rotationEffect(.degrees(-90))
                    .fixedSize()
                    .padding(.bottom, 15)
                    .frame(width: laborCodeColumnWidth, height: 50, alignment: .bottom)
                    .background(Color.white)
                    .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                }
                
                // Overtime header
                
                Text("Overtime")
                    .font(.system(size: 6))
                    .bold()
                    .rotationEffect(.degrees(-90))
                    .frame(width: overtimeWidth, height: 50)
                    .background(Color.white)
                    .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                    .padding(.bottom, 0)
                
                // Double-Time header
                Text("Double Time")
                    .font(.system(size: 6))
                    .bold()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .allowsTightening(true)
                    .rotationEffect(.degrees(-90))
                    .frame(width: doubleTimeWidth, height: 50)
                    .background(Color.white)
                    .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                    .padding(.bottom, 0)
            }
            
            // Week rows
            ForEach(0..<7, id: \.self) { i in
                let dayOvertimeEntries = overtimeEntriesFor(day: weekDates[i])
                
                // Calculate daily overtime and double-time based on total hours worked
                let dailyOTAndDT = calculateDailyOvertimeAndDoubleTime(for: weekDates[i])
                let dayOvertimeHours = dailyOTAndDT.overtime
                let dayDoubleTimeHours = dailyOTAndDT.doubleTime
                
                HStack(spacing: 0) {
                    // Day column
                    Text(weekdaysShort[i])
                        .font(.system(size: 8))
                        .bold()
                        .frame(width: dayColumnWidth, height: 22)
                        .background(Color.white)
                        .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                    
                    // Date column
                    Text(df.string(from: weekDates[i]))
                        .font(.system(size: 8))
                        .frame(width: dateColumnWidth, height: 22)
                        .background(Color.white)
                        .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                    
                    // 8 data columns - display hours worked
                    ForEach(0..<8, id: \.self) { colIndex in
                        // Get unique job/code combinations for the week
                        let allOvertimeEntries = weekDates.flatMap { overtimeEntriesFor(day: $0) }
                        let uniqueEntries = Array(Set(allOvertimeEntries.map { "\($0.jobNumber)|\($0.code)" }))
                            .sorted()
                            .map { combo -> (jobNumber: String, code: String) in
                                let parts = combo.split(separator: "|")
                                return (String(parts[0]), String(parts[1]))
                            }
                        
                        let columnJobNumber = colIndex < uniqueEntries.count ? uniqueEntries[colIndex].jobNumber : ""
                        let columnLabourCode = colIndex < uniqueEntries.count ? uniqueEntries[colIndex].code : ""
                        
                        // Find matching entry for this day and column
                        let matchingEntry = dayOvertimeEntries.first { entry in
                            entry.jobNumber == columnJobNumber && entry.code == columnLabourCode
                        }
                        
                        VStack(spacing: 1) {
                            if let entry = matchingEntry {
                                // Display hours worked
                                Text(formatHours(entry.hours))
                                    .font(.system(size: 6))
                                    .lineLimit(1)
                                    .bold()
                            }
                        }
                        .frame(width: laborCodeColumnWidth, height: 22)
                        .background(Color.white)
                        .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                    }
                    
                    // Overtime column - display actual overtime hours from entries
                    Text(dayOvertimeHours > 0 ? formatHours(dayOvertimeHours) : "")
                        .font(.system(size: 6))
                        .frame(width: overtimeWidth, height: 22)
                        .background(Color.white)
                        .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                    
                    // Double-Time column - display actual double-time hours from entries
                    Text(dayDoubleTimeHours > 0 ? formatHours(dayDoubleTimeHours) : "")
                        .font(.system(size: 6))
                        .frame(width: doubleTimeWidth, height: 22)
                        .background(Color.white)
                        .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                }
            }
            
            // Total Overtime row
            HStack(spacing: 0) {
                // Label spanning the first two columns (day + date)
                Text("TOTAL OVERTIME")
                    .font(.system(size: 8))
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
                    let uniqueEntries = Array(Set(allOvertimeEntries.map { "\($0.jobNumber)|\($0.code)" }))
                        .sorted()
                        .map { combo -> (jobNumber: String, code: String) in
                            let parts = combo.split(separator: "|")
                            return (String(parts[0]), String(parts[1]))
                        }
                    
                    let columnJobNumber = colIndex < uniqueEntries.count ? uniqueEntries[colIndex].jobNumber : ""
                    let columnLabourCode = colIndex < uniqueEntries.count ? uniqueEntries[colIndex].code : ""
                    
                    // Calculate total hours for this column across all days
                    let columnTotal = weekDates.reduce(0.0) { total, date in
                        let dayEntries = overtimeEntriesFor(day: date)
                        let matchingEntry = dayEntries.first { entry in
                            entry.jobNumber == columnJobNumber && entry.code == columnLabourCode
                        }
                        return total + (matchingEntry?.hours ?? 0.0)
                    }
                    
                    Text(columnTotal > 0 ? formatHours(columnTotal) : "")
                        .font(.system(size: 6))
                        .bold()
                        .frame(width: laborCodeColumnWidth, height: 18)
                        .background(Color.white)
                        .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                }
                
                // Overtime column - display total overtime hours
                Text(totalHoursFor(type: .ot))
                    .font(.system(size: 6))
                    .bold()
                    .frame(width: overtimeWidth, height: 18)
                    .background(Color.white)
                    .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                
                // Double-Time column - display total double-time hours
                Text(totalHoursFor(type: .dt))
                    .font(.system(size: 6))
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
                        .font(.system(size: 8))
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
            .font(.system(size: 8))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 4)
        Text(value)
            .font(.system(size: 8))
            .frame(width: 35, alignment: .trailing)
            .padding(.trailing, 4)
    }
    .frame(width: width, height: 16)
    .background(Color.white)
    .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
}

#Preview {
    TimecardPDFView()
        .environmentObject(TimecardStore.sampleStore)
}

