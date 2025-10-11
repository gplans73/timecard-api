import Foundation

struct Timecard: Identifiable, Hashable {
    let id: UUID
    var start: Date
    var end: Date
    var approved: Bool
    var project: String

    init(
        id: UUID = UUID(),
        start: Date = .now,
        end: Date = .now,
        approved: Bool = false,
        project: String = ""
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.approved = approved
        self.project = project
    }
}

extension Timecard {
    static let samples: [Timecard] = [
        .init(start: .now.addingTimeInterval(-8*3600), end: .now, approved: false, project: "iOS"),
        .init(start: .now.addingTimeInterval(-16*3600), end: .now.addingTimeInterval(-8*3600), approved: true, project: "API"),
    ]
}
