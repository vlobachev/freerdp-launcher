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

/// Graphics pipeline / codec selection.
enum GraphicsMode: String, Codable, CaseIterable, Identifiable {
    case auto
    case avc444
    case avc420
    case rfx
    case progressive
    case legacy

    var id: String { rawValue }
    var label: String {
        switch self {
        case .auto: return "Automatic (recommended)"
        case .avc444: return "H.264 AVC 4:4:4"
        case .avc420: return "H.264 AVC 4:2:0"
        case .rfx: return "RemoteFX"
        case .progressive: return "Progressive"
        case .legacy: return "Legacy (no GFX)"
        }
    }
    /// The FreeRDP flag, or nil to let FreeRDP negotiate.
    var flag: String? {
        switch self {
        case .auto: return nil
        case .avc444: return "/gfx:AVC444"
        case .avc420: return "/gfx:AVC420"
        case .rfx: return "/gfx:RFX"
        case .progressive: return "/gfx:progressive"
        case .legacy: return "-gfx"
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

    var graphics: GraphicsMode = .auto
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

// Tolerant decoding: missing keys fall back to defaults, so adding new fields
// never invalidates an existing connections.json.
extension Connection {
    enum CodingKeys: String, CodingKey {
        case id, name, host, port, username, domain, display, width, height
        case scale, graphics, audio, clipboard, microphone, ignoreCert
        case extraFlags, savePassword, lastUsed
    }

    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? id
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? name
        host = try c.decodeIfPresent(String.self, forKey: .host) ?? host
        port = try c.decodeIfPresent(Int.self, forKey: .port) ?? port
        username = try c.decodeIfPresent(String.self, forKey: .username) ?? username
        domain = try c.decodeIfPresent(String.self, forKey: .domain) ?? domain
        display = try c.decodeIfPresent(DisplayMode.self, forKey: .display) ?? display
        width = try c.decodeIfPresent(Int.self, forKey: .width) ?? width
        height = try c.decodeIfPresent(Int.self, forKey: .height) ?? height
        scale = try c.decodeIfPresent(Int.self, forKey: .scale) ?? scale
        graphics = try c.decodeIfPresent(GraphicsMode.self, forKey: .graphics) ?? graphics
        audio = try c.decodeIfPresent(AudioMode.self, forKey: .audio) ?? audio
        clipboard = try c.decodeIfPresent(Bool.self, forKey: .clipboard) ?? clipboard
        microphone = try c.decodeIfPresent(Bool.self, forKey: .microphone) ?? microphone
        ignoreCert = try c.decodeIfPresent(Bool.self, forKey: .ignoreCert) ?? ignoreCert
        extraFlags = try c.decodeIfPresent(String.self, forKey: .extraFlags) ?? extraFlags
        savePassword = try c.decodeIfPresent(Bool.self, forKey: .savePassword) ?? savePassword
        lastUsed = try c.decodeIfPresent(Date.self, forKey: .lastUsed) ?? lastUsed
    }
}
