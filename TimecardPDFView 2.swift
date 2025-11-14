import SwiftUI

struct TimecardPDFView: View {
    @EnvironmentObject var store: TimecardStore
    let weekOffset: Int

    private var weekRange: ClosedRange<Date> {
        store.weekRange(offset: weekOffset)
    }

    private var entriesForWeek: [Entry] {
        store.entries(in: weekRange)
    }

    private var totals: SummaryTotals { store.totals(for: weekRange) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.white
            VStack(alignment: .leading, spacing: 12) {
                header
                Divider()
                entriesSection
                Divider()
                totalsSection
                Spacer(minLength: 0)
            }
            .padding(24)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 12) {
                if let logo = store.companyLogoImage {
                    logo
                        .resizable()
                        .scaledToFit()
                        .frame(height: 36)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Timecard").font(.title2).fontWeight(.semibold)
                    Text(store.employeeName.isEmpty ? "Employee" : store.employeeName)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Pay Period #\(store.payPeriodNumber)")
                        .font(.subheadline).fontWeight(.medium)
                    Text(store.weekRange(offset: weekOffset).lowerBound.weekRangeLabel())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var entriesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Date").font(.footnote).fontWeight(.semibold)
                Spacer()
                Text("Job").font(.footnote).fontWeight(.semibold).frame(width: 120, alignment: .leading)
                Text("Code").font(.footnote).fontWeight(.semibold).frame(width: 60, alignment: .leading)
                Text("Hours").font(.footnote).fontWeight(.semibold).frame(width: 60, alignment: .trailing)
            }
            .foregroundStyle(.secondary)

            ForEach(entriesForWeek) { e in
                HStack(alignment: .top, spacing: 8) {
                    Text(dateString(e.date)).frame(minWidth: 90, alignment: .leading)
                    Spacer(minLength: 0)
                    Text(e.jobNumber).frame(width: 120, alignment: .leading)
                    Text(e.code).frame(width: 60, alignment: .leading)
                    Text(numberString(e.hours)).frame(width: 60, alignment: .trailing).monospacedDigit()
                }
                .font(.callout)
            }

            if entriesForWeek.isEmpty {
                Text("No entries for this week.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var totalsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Totals").font(.headline)
            HStack {
                totalRow("Regular", totals.regular)
                Spacer()
                totalRow("OT", totals.ot)
                Spacer()
                totalRow("DT", totals.dt)
                Spacer()
                totalRow("Vacation", totals.vacation)
                Spacer()
                totalRow("STAT", totals.stat)
                Spacer()
                totalRow("Night", totals.night)
            }
            HStack {
                Text("Total Hours").font(.subheadline).fontWeight(.semibold)
                Spacer()
                Text(numberString(totals.totalHours)).font(.subheadline).fontWeight(.semibold).monospacedDigit()
            }
        }
    }

    private func totalRow(_ title: String, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.footnote).foregroundStyle(.secondary)
            Text(numberString(value)).font(.callout).monospacedDigit()
        }
    }

    private func dateString(_ d: Date) -> String {
        let df = DateFormatter(); df.dateStyle = .medium
        return df.string(from: d)
    }

    private func numberString(_ n: Double) -> String {
        let f = NumberFormatter(); f.minimumFractionDigits = 0; f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: n)) ?? String(format: "%.2f", n)
    }
}

#Preview {
    TimecardPDFView(weekOffset: 0)
        .environmentObject(TimecardStore.sampleStore)
        .frame(width: PDFRenderer.a4Landscape.width, height: PDFRenderer.a4Landscape.height)
}
