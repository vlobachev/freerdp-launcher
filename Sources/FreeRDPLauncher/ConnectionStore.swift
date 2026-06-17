import Foundation
import Observation

/// Loads/saves connections as JSON in Application Support. Observable for SwiftUI.
@Observable
final class ConnectionStore {
    var connections: [Connection] = []

    private let fileURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("FreeRDP Launcher", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("connections.json")
    }()

    init() {
        load()
        if connections.isEmpty { importLegacyTSV() }
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        if let decoded = try? JSONDecoder().decode([Connection].self, from: data) {
            connections = decoded
        }
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(connections) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    func add(_ c: Connection) {
        connections.append(c)
        save()
    }

    func update(_ c: Connection) {
        if let idx = connections.firstIndex(where: { $0.id == c.id }) {
            connections[idx] = c
            save()
        }
    }

    func delete(_ c: Connection) {
        connections.removeAll { $0.id == c.id }
        Keychain.delete(for: c.id)
        save()
    }

    func markUsed(_ id: UUID) {
        if let idx = connections.firstIndex(where: { $0.id == id }) {
            connections[idx].lastUsed = Date()
            save()
        }
    }

    /// One-shot import of the legacy AppleScript-era ~/.config/freerdp-launcher/connections.tsv
    private func importLegacyTSV() {
        let tsv = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/freerdp-launcher/connections.tsv")
        guard let raw = try? String(contentsOf: tsv, encoding: .utf8) else { return }
        var imported: [Connection] = []
        for line in raw.split(separator: "\n") {
            let s = line.trimmingCharacters(in: .whitespaces)
            if s.isEmpty || s.hasPrefix("#") { continue }
            let parts = s.components(separatedBy: "\t")
            guard parts.count >= 3 else { continue }
            var c = Connection()
            c.name = parts[0]
            c.host = parts[1]
            c.username = parts[2]
            if parts.count >= 4 { c.extraFlags = parts[3] }
            c.display = .dynamic
            imported.append(c)
        }
        if !imported.isEmpty {
            connections = imported
            save()
        }
    }
}
