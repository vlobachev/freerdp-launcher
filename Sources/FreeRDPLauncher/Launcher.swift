import Foundation

enum LaunchError: LocalizedError {
    case notInstalled
    case spawnFailed(String)

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "FreeRDP is not installed. Install it with: brew install freerdp"
        case .spawnFailed(let m):
            return "Could not start FreeRDP: \(m)"
        }
    }
}

/// Finds a FreeRDP binary on a minimal PATH (GUI apps don't inherit the shell PATH).
enum FreeRDPLocator {
    static let candidates = [
        "/opt/homebrew/bin/sdl-freerdp",
        "/usr/local/bin/sdl-freerdp",
        "/opt/homebrew/bin/sdl-freerdp3",
        "/usr/local/bin/sdl-freerdp3",
        "/opt/homebrew/bin/xfreerdp",
        "/usr/local/bin/xfreerdp",
    ]

    static func find() -> String? {
        let fm = FileManager.default
        for path in candidates where fm.isExecutableFile(atPath: path) {
            return path
        }
        // Fallback: ask a login shell.
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-lc", "command -v sdl-freerdp || command -v sdl-freerdp3 || command -v xfreerdp"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            p.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let out = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return out.isEmpty ? nil : out
        } catch {
            return nil
        }
    }
}

/// Builds the FreeRDP argument list and launches a detached session.
/// The whole command line (including the password) is fed via `/args-from:stdin`
/// so the password never appears in `argv` / `ps`.
enum SessionLauncher {

    /// Build the argument lines (everything except the binary itself).
    static func arguments(for c: Connection, password: String) -> [String] {
        var a: [String] = []

        let target = c.port == 3389 ? c.host : "\(c.host):\(c.port)"
        a.append("/v:\(target)")
        a.append("/u:\(c.username)")
        if !c.domain.isEmpty { a.append("/d:\(c.domain)") }
        if c.ignoreCert { a.append("/cert:ignore") }

        switch c.display {
        case .fullscreen:
            a.append("+f")
            a.append("/dynamic-resolution")
        case .dynamic:
            a.append("/dynamic-resolution")
        case .fixed:
            a.append("/size:\(c.width)x\(c.height)")
        }

        if c.scale != 100 { a.append("/scale:\(c.scale)") }

        switch c.audio {
        case .off: a.append("-sound")
        case .local: a.append("/sound:sys:mac")
        }
        a.append(c.clipboard ? "+clipboard" : "-clipboard")
        if c.microphone { a.append("+microphone") }

        // Graphics codec. Default ("Automatic") passes nothing and lets FreeRDP
        // negotiate — forcing a codec (e.g. AVC444) can crash some software-
        // rendered gnome-remote-desktop sessions right after the login screen.
        if let gfx = c.graphics.flag { a.append(gfx) }

        // Extra user flags (whitespace-separated).
        for tok in c.extraFlags.split(whereSeparator: { $0 == " " || $0 == "\t" }) {
            a.append(String(tok))
        }

        if !password.isEmpty { a.append("/p:\(password)") }
        return a
    }

    @discardableResult
    static func launch(_ c: Connection, password: String) throws -> Process {
        guard let bin = FreeRDPLocator.find() else { throw LaunchError.notInstalled }

        let args = arguments(for: c, password: password)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: bin)
        process.arguments = ["/args-from:stdin"]

        let stdin = Pipe()
        process.standardInput = stdin
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw LaunchError.spawnFailed(error.localizedDescription)
        }

        // Feed all arguments (one per line) then close stdin.
        let payload = (args.joined(separator: "\n") + "\n")
        stdin.fileHandleForWriting.write(Data(payload.utf8))
        try? stdin.fileHandleForWriting.close()

        return process
    }
}
