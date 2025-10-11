import Foundation
import Combine

final class JobsStore: ObservableObject {
    // A stable placeholder job that appears first in lists for manual entry
    private static let manualPlaceholderID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private static let manualPlaceholder = Job(id: JobsStore.manualPlaceholderID, code: "Job:", name: "Manual Entry")

    struct Job: Identifiable, Codable, Hashable {
        var id: UUID
        var code: String   // Short display code, e.g., "ES"
        var name: String   // Full name, e.g., "Electrical Services"

        init(id: UUID = UUID(), code: String, name: String) {
            self.id = id
            self.code = code
            self.name = name
        }
    }

    @Published private(set) var jobs: [Job] = [] {
        didSet { save() }
    }

    private let storageKey = "JobsStore.jobs"

    init() {
        load()
    }

    // Expose placeholder to UI for detection and comparison
    var manualEntryJobID: UUID { Self.manualPlaceholderID }
    var manualEntryJob: Job { Self.manualPlaceholder }

    // MARK: - CRUD

    func addJob(code: String, name: String) {
        let newJob = Job(code: code, name: name)
        jobs.append(newJob)
    }

    /// Adds a manual job using a human-readable name. A short code is auto-generated from the name's initials.
    func addManualJob(name: String) {
        let code = JobsStore.makeCode(from: name)
        addJob(code: code, name: name)
    }

    func updateJob(_ job: Job) {
        guard let idx = jobs.firstIndex(where: { $0.id == job.id }) else { return }
        jobs[idx] = job
    }

    func removeJob(id: UUID) {
        // Prevent removing the manual placeholder
        guard id != Self.manualPlaceholderID else { return }
        jobs.removeAll { $0.id == id }
    }

    func moveJobs(from source: IndexSet, to destination: Int) {
        let indices = source.sorted()
        let items = indices.map { jobs[$0] }
        for i in indices.reversed() {
            jobs.remove(at: i)
        }
        let removedBefore = indices.filter { $0 < destination }.count
        var insertIndex = destination - removedBefore
        jobs.insert(contentsOf: items, at: insertIndex)
        // Keep the manual placeholder at the top if it exists
        if let idx = jobs.firstIndex(where: { $0.id == Self.manualPlaceholderID }), idx != 0 {
            let placeholder = jobs.remove(at: idx)
            jobs.insert(placeholder, at: 0)
            // If we inserted before our last insert, adjust insertIndex (not strictly needed post-operation)
            if idx < insertIndex { insertIndex -= 1 }
        }
    }

    // Generates a short uppercase code from a name (e.g., "Electrical Services" -> "ES")
    private static func makeCode(from name: String) -> String {
        let parts = name.split(separator: " ")
        let initials = parts.compactMap { $0.first }.map { String($0).uppercased() }
        let joined = initials.joined()
        if joined.isEmpty {
            return "JOB"
        }
        // Limit to a few characters for display
        return String(joined.prefix(4))
    }

    /// Returns an existing job matching the given name (case-insensitive), or creates one if missing.
    /// If the input is empty/whitespace, the manual placeholder is returned.
    @discardableResult
    func ensureJob(named rawName: String) -> Job {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return Self.manualPlaceholder }
        if let existing = jobs.first(where: { $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) {
            return existing
        }
        let code = JobsStore.makeCode(from: name)
        let newJob = Job(code: code, name: name)
        jobs.append(newJob)
        return newJob
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            // Seed with a couple of example jobs if none exist
            jobs = [
                Self.manualPlaceholder,
                Job(code: "ES", name: "Electrical Services"),
                Job(code: "HVAC", name: "HVAC")
            ]
            save()
            return
        }
        do {
            let decoded = try JSONDecoder().decode([Job].self, from: data)
            var list = decoded
            if let idx = list.firstIndex(where: { $0.id == Self.manualPlaceholderID }) {
                // Ensure it's at the top
                if idx != 0 {
                    let placeholder = list.remove(at: idx)
                    list.insert(placeholder, at: 0)
                }
            } else {
                // Insert placeholder at the top if missing
                list.insert(Self.manualPlaceholder, at: 0)
            }
            jobs = list
        } catch {
            // If decoding fails, start with an empty list to avoid crashes
            jobs = []
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(jobs)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            // In production you might want to log this
        }
    }
}

// MARK: - Convenience accessors for UI
extension JobsStore.Job {
    var displayCode: String { code }
    var displayName: String { name }
    var combinedDisplay: String { "\(code) – \(name)" }
}
