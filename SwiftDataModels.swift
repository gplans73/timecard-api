import Foundation
import SwiftData

// MARK: - SwiftData Models (Scaffolding for CloudKit Sync)

@Model
final class EntryModel {
    var id: UUID = UUID()
    var date: Date = Date.now
    var jobNumber: String = ""
    var code: String = ""
    var hours: Double = 0
    var notes: String = ""
    var isOvertime: Bool = false
    var isNightShift: Bool = false

    init(id: UUID = UUID(),
         date: Date,
         jobNumber: String = "",
         code: String = "",
         hours: Double = 0,
         notes: String = "",
         isOvertime: Bool = false,
         isNightShift: Bool = false) {
        self.id = id
        self.date = date
        self.jobNumber = jobNumber
        self.code = code
        self.hours = hours
        self.notes = notes
        self.isOvertime = isOvertime
        self.isNightShift = isNightShift
    }
}

@Model
final class LabourCodeModel {
    var id: UUID = UUID()
    var name: String = ""
    var code: String = ""

    init(id: UUID = UUID(), name: String, code: String) {
        self.id = id
        self.name = name
        self.code = code
    }
}

@Model
final class JobModel {
    var id: UUID = UUID()
    var name: String = ""
    var code: String = ""

    init(id: UUID = UUID(), name: String, code: String) {
        self.id = id
        self.name = name
        self.code = code
    }
}
