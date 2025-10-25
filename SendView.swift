//
//  SendView_NoCollision.swift (Swift 6 fix)
//
import SwiftUI
import PDFKit
#if canImport(MessageUI)
import MessageUI
#endif

struct SendView: View {
    @EnvironmentObject var store: TimecardStore
    @AppStorage("emailSubjectTemplate") private var emailSubjectTemplate: String = ""
    @AppStorage("emailBodyTemplate") private var emailBodyTemplate: String = ""
    @State private var pdfData = Data()
    @State private var showMail = false
    @State private var showShare = false
    @State private var previewRefreshID = UUID()
    @State private var zoom: CGFloat = 1.1
    @State private var isPanning: Bool = true
    @State private var pinchScale: CGFloat = 1.0
    @State private var ubiObserver: NSObjectProtocol? = nil
    @State private var attachWeeks: [Bool] = []
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationView {
            VStack(spacing: 12) {
                // Preview area
                TimecardPreviewPane(zoom: $zoom, pinchScale: $pinchScale, isPanning: $isPanning, previewRefreshID: previewRefreshID)
                    .environmentObject(store)

                VStack(alignment: .leading, spacing: 8) {
                    let weekButtonCount = min(4, max(1, store.payPeriodWeeks))
                    let itemWidth: CGFloat = 56
                    let itemHeight: CGFloat = 36
                    let spacing: CGFloat = 8

                    // Top row: Send + toggles only
                    HStack(spacing: spacing) {
                        // Send button
                        Button {
                            if store.attachPDF {
                                pdfData = PDFRenderer.render(view: AnyView(TimecardPDFView(weekOffset: store.selectedWeekIndex).environmentObject(store)),
                                                             size: PDFRenderer.a4Landscape)
                            } else {
                                pdfData = Data()
                            }

                            var additionalAttachmentURLs: [URL] = []
                            if store.attachCSV, let xlsURL = exportEntriesExcelURL() {
                                additionalAttachmentURLs.append(xlsURL)
                            }

                            self.syncEmail(
                                recipients: store.emailRecipients,
                                subjectTemplate: emailSubjectTemplate.isEmpty ? nil : emailSubjectTemplate,
                                bodyTemplate: emailBodyTemplate.isEmpty ? nil : emailBodyTemplate
                            )

                            #if canImport(MessageUI)
                            if MFMailComposeViewController.canSendMail() { showMail = true } else { showShare = true }
                            #else
                            showShare = true
                            #endif
                        } label: {
                            Image(systemName: "envelope.badge")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(width: itemWidth, height: itemHeight)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .buttonBorderShape(.capsule)
                        .clipShape(Capsule())

                        // PDF toggle
                        Button {
                            store.attachPDF.toggle()
                        } label: {
                            Image(systemName: store.attachPDF ? "doc.fill" : "doc")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(width: itemWidth, height: itemHeight)
                                .accessibilityLabel("Attach PDF")
                                .accessibilityValue(store.attachPDF ? "On" : "Off")
                        }
                        .buttonStyle(.bordered)
                        .tint(store.attachPDF ? .accentColor : .secondary)
                        .controlSize(.small)
                        .buttonBorderShape(.capsule)
                        .clipShape(Capsule())

                        // CSV toggle
                        Button {
                            store.attachCSV.toggle()
                        } label: {
                            Image(systemName: store.attachCSV ? "tablecells.fill" : "tablecells")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(width: itemWidth, height: itemHeight)
                                .accessibilityLabel("Attach Excel (XLSX)")
                                .accessibilityValue(store.attachCSV ? "On" : "Off")
                        }
                        .buttonStyle(.bordered)
                        .tint(store.attachCSV ? .accentColor : .secondary)
                        .controlSize(.small)
                        .buttonBorderShape(.capsule)
                        .clipShape(Capsule())

                        Spacer(minLength: 0)
                    }

                    // Bottom row: All week buttons evenly spaced
                    HStack(spacing: spacing) {
                        ForEach(0..<weekButtonCount, id: \.self) { idx in
                            let isOn: Bool = (idx < attachWeeks.count) ? attachWeeks[idx] : false
                            Button {
                                if attachWeeks.count < weekButtonCount {
                                    var newFlags = Array(attachWeeks.prefix(weekButtonCount))
                                    if newFlags.count < weekButtonCount {
                                        newFlags.append(contentsOf: Array(repeating: false, count: weekButtonCount - newFlags.count))
                                    }
                                    attachWeeks = newFlags
                                }
                                attachWeeks[idx].toggle()
                            } label: {
                                ZStack(alignment: .topTrailing) {
                                    Text("W\(idx + 1)")
                                        .font(.system(size: 14, weight: .semibold))
                                        .frame(maxWidth: .infinity, minHeight: itemHeight)
                                    if isOn {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundStyle(.white)
                                            .shadow(radius: 0)
                                            .offset(x: -4, y: 4)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .buttonStyle(.bordered)
                            .tint(isOn ? .accentColor : .secondary)
                            .controlSize(.small)
                            .buttonBorderShape(.capsule)
                            .clipShape(Capsule())
                            .accessibilityLabel("Attach Week \((idx + 1))")
                            .accessibilityValue(isOn ? "On" : "Off")
                        }
                    }
                }

                Text("If Mail isn't available, the share sheet will open instead.")
                    .font(.footnote).foregroundColor(.secondary)

                Spacer()
            }
            .padding()
            .navigationTitle("Preview & Send")
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        isInputFocused = false
                    }
                }
            }
            .onAppear {
                // Prime from iCloud KVS if available
                if UbiquitousSettingsSync.isAvailable {
                    let kvs = NSUbiquitousKeyValueStore.default
                    if let s = kvs.string(forKey: "emailSubjectTemplate") { self.emailSubjectTemplate = s }
                    if let b = kvs.string(forKey: "emailBodyTemplate") { self.emailBodyTemplate = b }
                    kvs.synchronize()

                    // Observe external KVS changes to keep @AppStorage in sync
                    ubiObserver = NotificationCenter.default.addObserver(
                        forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                        object: kvs,
                        queue: .main
                    ) { _ in
                        let store = NSUbiquitousKeyValueStore.default
                        if let s = store.string(forKey: "emailSubjectTemplate") { self.emailSubjectTemplate = s }
                        if let b = store.string(forKey: "emailBodyTemplate") { self.emailBodyTemplate = b }
                    }
                }

                // Ensure stat holidays are added for the current pay period in preview
                if store.autoHolidaysEnabled {
                    store.addStatHolidaysForCurrentPeriod()
                }

                // Initialize week attachment toggles to match pay period size
                let count = min(4, max(1, store.payPeriodWeeks))
                if attachWeeks.count != count {
                    attachWeeks = Array(repeating: false, count: count)
                    let sel = min(max(0, store.selectedWeekIndex), count - 1)
                    attachWeeks[sel] = true
                }
            }
            .onDisappear {
                if let token = ubiObserver {
                    NotificationCenter.default.removeObserver(token)
                    ubiObserver = nil
                }
            }
            
            #if canImport(MessageUI)
            .sheet(isPresented: $showMail) {
                MailComposer(isShowing: $showMail,
                               subject: computedSubject(),
                               recipients: store.emailRecipients,
                               body: computedBody(),
                               attachmentData: (store.attachPDF ? pdfData : nil),
                               mimeType: "application/pdf",
                               fileName: fileName(),
                               additionalFileURLs: {
                                   var urls: [URL] = []
                                   if store.attachCSV, let u = exportEntriesExcelURL() { urls.append(u) }
                                   return urls
                               }())
            }
            #endif

            .sheet(isPresented: $showShare) {
                ActivityView(activityItems: shareActivityItems())
            }
            .onChange(of: store.autoHolidaysEnabled) { _, enabled in
                if enabled {
                    store.addStatHolidaysForCurrentPeriod()
                } else {
                    store.removeStatHolidaysForCurrentPeriod()
                }
            }
            .onChange(of: store.weekStart) { _, _ in
                if store.autoHolidaysEnabled {
                    store.addStatHolidaysForCurrentPeriod()
                } else {
                    store.removeStatHolidaysForCurrentPeriod()
                }
            }
            .onChange(of: store.payPeriodWeeks) { _, _ in
                let count = min(4, max(1, store.payPeriodWeeks))
                if attachWeeks.count != count {
                    // Preserve existing selections up to the new count
                    var newFlags = Array(repeating: false, count: count)
                    for i in 0..<min(attachWeeks.count, count) {
                        newFlags[i] = attachWeeks[i]
                    }
                    // Ensure at least one week is selected
                    if !newFlags.contains(true) {
                        let sel = min(max(0, store.selectedWeekIndex), count - 1)
                        newFlags[sel] = true
                    }
                    attachWeeks = newFlags
                }
            }
        }
    }

    private func fileName() -> String {
        let emp = (store.employeeName.isEmpty ? "Employee" : store.employeeName).replacingOccurrences(of: " ", with: "_")
        return "Timecard_\(emp)_\(store.weekStart.fileSafeDate()).pdf"
    }
    private func tempURL() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName())
        try? pdfData.write(to: url, options: .atomic)
        return url
    }
    private func shareActivityItems() -> [Any] {
        var items: [Any] = []
        if store.attachPDF {
            let pdf = tempURL()
            items.append(pdf)
        }
        if store.attachCSV, let u = exportEntriesExcelURL() { items.append(u) }
        return items
    }

    private func computedSubject() -> String {
        let name = store.employeeName.isEmpty ? "Employee" : store.employeeName
        let range = store.weekStart.weekRangeLabel()
        if emailSubjectTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Timecard — \(name) — \(range)"
        }
        return replaceTokens(in: emailSubjectTemplate, name: name, range: range)
    }

    private func computedBody() -> String {
        let name = store.employeeName.isEmpty ? "Employee" : store.employeeName
        let range = store.weekStart.weekRangeLabel()
        let tpl = emailBodyTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        if tpl.isEmpty {
            return store.emailBody(for: store.selectedWeekStart)
        }
        return replaceTokens(in: tpl, name: name, range: range)
    }

    private func replaceTokens(in template: String, name: String, range: String) -> String {
        var s = template
        s = s.replacingOccurrences(of: "{employee}", with: name)
        s = s.replacingOccurrences(of: "{name}", with: name)
        s = s.replacingOccurrences(of: "{range}", with: range)
        return s
    }

    private func syncEmail(recipients: [String], subjectTemplate: String?, bodyTemplate: String?) {
        // Update local @AppStorage first so UI reflects immediately
        if let subject = subjectTemplate { self.emailSubjectTemplate = subject }
        if let body = bodyTemplate { self.emailBodyTemplate = body }

        // Mirror to iCloud KVS if available via helper
        UbiquitousSettingsSync.shared.pushEmail(recipients: recipients, subjectTemplate: subjectTemplate, bodyTemplate: bodyTemplate)
    }
    
    private func exportEntriesExcelURL() -> URL? {
        return exportEntriesExcelURL(weekOffset: store.selectedWeekIndex)
    }

    private func exportEntriesExcelURL(weekOffset: Int) -> URL? {
        let range = store.weekRange(offset: weekOffset)
        let entries = store.entries(in: range)
        guard !entries.isEmpty else { return nil }

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"

        var rows: [[String]] = [["Date","Job Number","Code","Hours","Notes","Overtime","Night Shift"]]
        for e in entries {
            let date = df.string(from: e.date)
            let job = e.jobNumber
            let code = e.code
            let hours = String(e.hours)
            let notes = e.notes.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
            let ot = e.isOvertime ? "Yes" : "No"
            let night = e.isNightShift ? "Yes" : "No"
            rows.append([date, job, code, hours, notes, ot, night])
        }

        do {
            let data = try XLSXWriter.makeWorkbook(sheetName: "Entries Week \(weekOffset + 1)", rows: rows)
            let fileName = "Entries_\((store.employeeName.isEmpty ? "Employee" : store.employeeName).replacingOccurrences(of: " ", with: "_"))"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(fileName)_Week\(weekOffset + 1)_\(store.weekRange(offset: weekOffset).lowerBound.fileSafeDate()).xlsx")
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            print("Failed to write XLSX for week \(weekOffset + 1): \(error)")
            return nil
        }
    }
}

struct TimecardPreviewPane: View {
    @EnvironmentObject var store: TimecardStore
    @Binding var zoom: CGFloat
    @Binding var pinchScale: CGFloat
    @Binding var isPanning: Bool
    let previewRefreshID: UUID

    var body: some View {
        GroupBox(label: Label("Timecard Preview", systemImage: "doc.text.magnifyingglass")) {
            // This picker is linked to the Time tab; both use store.selectedWeekIndex
            Picker("Week", selection: $store.selectedWeekIndex) {
                ForEach(0..<(max(1, store.payPeriodWeeks)), id: \.self) { idx in
                    Text("Week \(idx + 1)").tag(idx)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 6)

            GeometryReader { geo in
                ScrollView([.horizontal, .vertical], showsIndicators: true) {
                    ZStack(alignment: .topLeading) {
                        let metrics = computeMetrics(availSize: geo.size)

                        if metrics.hasValidSize {
                            // Fixed-size page content at 1x; use scaleEffect to fit
                            ZStack(alignment: .topLeading) {
                                Rectangle()
                                    .fill(Color.white)
                                    .frame(width: metrics.page.width, height: metrics.page.height)
                                    .fixedSize()

                                TimecardPDFView(weekOffset: store.selectedWeekIndex)
                                    .environmentObject(store)
                                    .frame(width: metrics.page.width, height: metrics.page.height)
                                    .id(previewRefreshID)
                                    .fixedSize()
                            }
                            .scaleEffect(metrics.effectiveScale, anchor: .topLeading)
                            .frame(width: metrics.scaled.width, height: metrics.scaled.height, alignment: .topLeading)
                            .simultaneousGesture(
                                MagnificationGesture()
                                    .onChanged { value in
                                        // Update live pinch scale without committing to persistent zoom
                                        pinchScale = value
                                    }
                                    .onEnded { value in
                                        let spring = Animation.spring(response: 0.25, dampingFraction: 0.9, blendDuration: 0.2)
                                        withAnimation(spring) {
                                            let newZoom = (zoom * value).rounded(toPlaces: 2)
                                            zoom = min(8.0, max(0.5, newZoom))
                                            pinchScale = 1.0
                                        }
                                    }
                            )
                            .onTapGesture(count: 2) {
                                let spring = Animation.spring(response: 0.25, dampingFraction: 0.9, blendDuration: 0.2)
                                withAnimation(spring) {
                                    let target: CGFloat = (zoom < 2.0) ? 4.0 : 1.0
                                    zoom = target
                                }
                            }

                        } else {
                            // Avoid any fixed-size frames when invalid; fill available safely
                            Color.clear
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        }
                    }
                }
                .disabled(!isPanning)
            }
            .frame(minHeight: 380, maxHeight: 500)
        }
        .padding(.top, 2)
        .padding(.bottom, 8)
    }

    private func computeMetrics(availSize: CGSize) -> (page: CGSize, avail: CGSize, baseScale: CGFloat, effectiveScale: CGFloat, scaled: CGSize, hasValidSize: Bool) {
        let page = PDFRenderer.a4Landscape

        // Protect against zero/negative geometry and non-finite values
        let availW = max(0, availSize.width - 16)
        let availH = max(0, availSize.height - 16)
        let pageW = max(page.width, 1)
        let pageH = max(page.height, 1)

        // Scale so that the entire page fits in the available area
        let fitScaleW = availW / pageW
        let fitScaleH = availH / pageH
        var baseScale = min(fitScaleW, fitScaleH)
        if !baseScale.isFinite || baseScale <= 0 { baseScale = 0 }

        let safeZoom = (zoom.isFinite && zoom > 0) ? zoom : 1
        let gestureScale = (pinchScale.isFinite && pinchScale > 0) ? pinchScale : 1
        let effectiveScale = baseScale * safeZoom * gestureScale
        // Compute scaled dimensions; clamp to non-negative finite
        var scaledW = pageW * effectiveScale
        var scaledH = pageH * effectiveScale
        if !scaledW.isFinite || scaledW < 0 { scaledW = 0 }
        if !scaledH.isFinite || scaledH < 0 { scaledH = 0 }

        let hasValidSize = (scaledW > 0 && scaledH > 0)
        return (
            page: CGSize(width: pageW, height: pageH),
            avail: CGSize(width: availW, height: availH),
            baseScale: baseScale,
            effectiveScale: effectiveScale,
            scaled: CGSize(width: scaledW, height: scaledH),
            hasValidSize: hasValidSize
        )
    }
}

#if canImport(MessageUI)
struct MailComposer: UIViewControllerRepresentable {
    @Binding var isShowing: Bool
    let subject: String; let recipients: [String]; let body: String
    let attachmentData: Data?; let mimeType: String; let fileName: String
    let additionalFileURLs: [URL]

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.setSubject(subject)
        vc.setToRecipients(recipients)
        vc.setMessageBody(body, isHTML: false)
        if let data = attachmentData, !data.isEmpty {
            vc.addAttachmentData(data, mimeType: mimeType, fileName: fileName)
        }
        for url in additionalFileURLs {
            let data = (try? Data(contentsOf: url)) ?? Data()
            let ext = url.pathExtension.lowercased()
            let type: String
            switch ext {
            case "csv": type = "text/csv"
            case "json": type = "application/json"
            case "xls": type = "application/vnd.ms-excel"
            case "xlsx": type = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
            case "pdf": type = "application/pdf"
            default: type = "application/octet-stream"
            }
            vc.addAttachmentData(data, mimeType: type, fileName: url.lastPathComponent)
        }
        vc.mailComposeDelegate = context.coordinator
        return vc
    }
    func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) { }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let parent: MailComposer
        init(_ p: MailComposer) { self.parent = p }
        func mailComposeController(_ controller: MFMailComposeViewController,
                                   didFinishWith result: MFMailComposeResult,
                                   error: Error?) {
            controller.dismiss(animated: true) { self.parent.isShowing = false }
        }
    }
}
#endif

#if canImport(UIKit)
import UIKit
struct ActivityView: UIViewControllerRepresentable {
    var activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }
}
#elseif canImport(AppKit)
import AppKit
struct ActivityView: View {
    var activityItems: [Any]
    var body: some View {
        if #available(macOS 13.0, *), let url = activityItems.first as? URL {
            ShareLink(item: url) { Label("Share PDF", systemImage: "square.and.arrow.up") }.padding()
        } else {
            Text("PDF saved to a temporary file. Please attach/share manually.")
                .padding()
        }
    }
}
#else
struct ActivityView: View {
    var activityItems: [Any]
    var body: some View { Text("Sharing not supported on this platform.") }
}
#endif

extension CGFloat {
    func rounded(toPlaces places: Int) -> CGFloat {
        let divisor = pow(10.0, CGFloat(places))
        return (self * divisor).rounded() / divisor
    }
}

