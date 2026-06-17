import Foundation

/// How the remote desktop is sized on screen.
enum DisplayMode: String, Codable, CaseIterable, Identifiable {
    case dynamic
    case fullscreen
    case fixed

    var id: String { rawValue }
    var label: String {
        switch self {
        case .dynamic: return "Dynamic (resize freely)"
        case .fullscreen: return "Fullscreen"
        case .fixed: return "Fixed size"
        }
    }
}

/// Where session audio is played.
enum AudioMode: String, Codable, CaseIterable, Identifiable {
    case off
    case local

    var id: String { rawValue }
    var label: String {
        switch self {
        case .off: return "Off"
        case .local: return "Play on this Mac"
        }
    }
}

/// A common fixed resolution preset.
struct SizePreset: Identifiable, Hashable {
    let width: Int
    let height: Int
    var id: String { "\(width)x\(height)" }
    var label: String { "\(width) × \(height)" }

    static let presets: [SizePreset] = [
        .init(width: 1280, height: 800),
        .init(width: 1920, height: 1080),
        .init(width: 2560, height: 1440),
        .init(width: 2560, height: 1600),
        .init(width: 3024, height: 1890),
        .init(width: 3456, height: 2234),
        .init(width: 3840, height: 2160),
    ]
}

/// A saved RDP connection. Passwords are NEVER stored here — only in the Keychain.
struct Connection: Codable, Identifiable, Hashable {
    var id = UUID()
    var name = ""
    var host = ""
    var port = 3389
    var username = ""
    var domain = ""

    var display: DisplayMode = .fixed
    var width = 2560
    var height = 1440
    /// FreeRDP `/scale:` DPI hint. Only 100, 140, 180 are accepted by FreeRDP.
    var scale = 140

    var audio: AudioMode = .local
    var clipboard = true
    var microphone = false
    var ignoreCert = true
    var extraFlags = ""

    var savePassword = true
    var lastUsed: Date?

    /// Valid FreeRDP `/scale:` values.
    static let scaleOptions = [100, 140, 180]
}
