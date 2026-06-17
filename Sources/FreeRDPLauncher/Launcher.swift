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
        case .dynamic:
            a.append("/dynamic-resolution")
        case .fixed:
            a.append("/size:\(c.width)x\(c.height)")
        }

        if c.scale != 100 { a.append("/scale:\(c.scale)") }

        switch c.audio {
        case .off:
            a.append("-sound")
        case .local:
            // A larger jitter buffer (latency:) smooths audio drop-outs on
            // tunneled / VPN links at the cost of a little extra delay.
            var snd = "/sound:sys:mac"
            if c.audioLatency != .off { snd += ",latency:\(c.audioLatency.rawValue)" }
            a.append(snd)
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

    /// Launch a detached session. If it dies quickly with a non-zero exit
    /// (auth failure, unreachable host, …), `onEarlyFailure` is called on the
    /// main thread with a human-readable explanation built from FreeRDP's
    /// stderr — so the window doesn't just vanish without a word.
    @discardableResult
    static func launch(_ c: Connection,
                       password: String,
                       onEarlyFailure: ((String) -> Void)? = nil) throws -> Process {
        guard let bin = FreeRDPLocator.find() else { throw LaunchError.notInstalled }

        let args = arguments(for: c, password: password)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: bin)
        process.arguments = ["/args-from:stdin"]

        let stdin = Pipe()
        let errPipe = Pipe()
        process.standardInput = stdin
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errPipe

        // Drain stderr continuously (so a long session never blocks on a full
        // pipe), keeping only the tail for diagnostics.
        let collector = OutputCollector()
        errPipe.fileHandleForReading.readabilityHandler = { fh in
            let d = fh.availableData
            if !d.isEmpty { collector.append(d) }
        }

        let started = Date()
        process.terminationHandler = { proc in
            errPipe.fileHandleForReading.readabilityHandler = nil
            guard let onEarlyFailure,
                  proc.terminationStatus != 0,
                  Date().timeIntervalSince(started) < 12 else { return }
            let msg = friendlyError(status: proc.terminationStatus, stderr: collector.text())
            DispatchQueue.main.async { onEarlyFailure(msg) }
        }

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

    /// Turn a FreeRDP exit code + stderr tail into a short, useful message.
    static func friendlyError(status: Int32, stderr: String) -> String {
        let s = stderr.uppercased()
        var headline = "The remote session closed unexpectedly (exit code \(status))."
        if s.contains("LOGON_FAILURE") || s.contains("NO_CREDENTIALS")
            || s.contains("SAM DATABASE") || s.contains("AUTHENTICATION FAILURE") {
            headline = "Authentication failed — check the username and password."
        } else if s.contains("MESSAGE ALTERED") || s.contains("MIC ") {
            headline = "NLA/NTLM negotiation failed — this server needs a FreeRDP client (the macOS Windows App can't connect)."
        } else if s.contains("TRANSPORT_FAILED") || s.contains("CONNECT_CANCELLED")
            || s.contains("DNS") || s.contains("CONNECTION RESET") {
            headline = "Couldn't reach the server — check the host, port, and that it's listening."
        } else if s.contains("CERTIFICATE") || s.contains("TLS") {
            headline = "TLS/certificate problem — try enabling “Ignore server certificate (LAN)”."
        }
        let tail = stderr
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .suffix(12)
            .joined(separator: "\n")
        return tail.isEmpty ? headline : "\(headline)\n\n\(tail)"
    }
}

/// Thread-safe, size-capped accumulator for a process's stderr tail.
private final class OutputCollector {
    private let lock = NSLock()
    private var data = Data()
    private let cap = 16_384

    func append(_ d: Data) {
        lock.lock(); defer { lock.unlock() }
        data.append(d)
        if data.count > cap { data.removeFirst(data.count - cap) }
    }

    func text() -> String {
        lock.lock(); defer { lock.unlock() }
        return String(decoding: data, as: UTF8.self)
    }
}
