import Foundation

/// Append-only log file.
///
/// Writes are serialized on a private queue. Two threads writing at once is
/// not hypothetical here: the audio tap callback, the event tap callback and
/// the main thread all log, and interleaved writes produce lines that cannot
/// be read back.
///
/// Lines carry a date, not just a time. The log survives restarts and days of
/// uptime, and a bare clock made lines from different days indistinguishable —
/// which once led to a wrong conclusion while diagnosing a real problem.
public final class Log {
    public let path: String
    private let maxBytes: Int
    private let queue: DispatchQueue
    private let formatter: DateFormatter

    /// Rotation is checked every N lines rather than on each one. Stat-ing
    /// the file per line would be a syscall on a hot path; checking only at
    /// launch would let a machine that stays awake for weeks grow the log
    /// without bound.
    private let linesBetweenRotationChecks = 500
    private var linesSinceRotationCheck = 0

    public init(path: String, maxBytes: Int = 1_000_000) {
        self.path = path
        self.maxBytes = maxBytes
        self.queue = DispatchQueue(label: "com.trustbe.nativevoice.log")
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm:ss"
        // Pinning the locale keeps the output parseable for a user whose own
        // calendar is not Gregorian. Apple documents this in QA1480.
        f.locale = Locale(identifier: "en_US_POSIX")
        self.formatter = f
    }

    public func write(_ message: String) {
        let line = "[\(formatter.string(from: Date()))] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        queue.async { [self] in
            append(data)
            linesSinceRotationCheck += 1
            if linesSinceRotationCheck >= linesBetweenRotationChecks {
                linesSinceRotationCheck = 0
                rotateOnQueue()
            }
        }
    }

    /// Waits for queued writes to reach the file. Tests need it; production
    /// never calls it.
    ///
    /// Uses `queue.sync`, so it must never be called from inside work already
    /// running on `queue` — that would deadlock a serial queue against
    /// itself. Nothing does today; `queue` is private, so the hazard stays
    /// inside this file.
    public func drain() {
        queue.sync { }
    }

    /// Moves the log aside once it outgrows `maxBytes`, keeping one previous
    /// batch. Without this the file grows forever — every key press adds
    /// lines and nothing ever removes them.
    public func rotateIfNeeded() {
        queue.sync { rotateOnQueue() }
    }

    // MARK: - Must run on `queue`

    private func append(_ data: Data) {
        // The throwing API is not a style preference. The legacy
        // `FileHandle.write(_:)` turns an I/O error into an Objective-C
        // exception that Swift cannot catch, and the process dies. Measured:
        // writing to a pipe whose read end is closed exits 134 (SIGABRT) with
        // the legacy call and exits 0, with the error caught, using this one.
        // Every thread that matters funnels through here, so one bad write
        // must never take the app down.
        try? FileHandle.standardError.write(contentsOf: data)

        if let handle = FileHandle(forWritingAtPath: path) {
            defer { try? handle.close() }
            do {
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } catch {
                note("log write failed: \(error.localizedDescription)")
            }
        } else {
            // No file yet, or it cannot be opened for writing.
            do {
                try data.write(to: URL(fileURLWithPath: path))
            } catch {
                note("log could not be created at \(path): "
                     + error.localizedDescription)
            }
        }
    }

    private func rotateOnQueue() {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: path),
              let size = attrs[.size] as? Int, size > maxBytes else { return }
        let previous = path + ".1"
        try? fm.removeItem(atPath: previous)
        do {
            try fm.moveItem(atPath: path, toPath: previous)
        } catch {
            // Silence here would be the worst case: the log keeps growing
            // unbounded precisely when the bound matters, with no trail.
            note("log rotation failed: \(error.localizedDescription)")
        }
    }

    /// Reports a logging failure without recursing back into the log.
    private func note(_ message: String) {
        guard let data = "[log] \(message)\n".data(using: .utf8) else { return }
        try? FileHandle.standardError.write(contentsOf: data)
    }
}

extension Log {
    public static let shared = Log(
        path: NSString(string: "~/Library/Logs/NativeVoice.log").expandingTildeInPath)
}

/// Shorthand used throughout the app.
///
/// Named `appLog`, not `log`: `import Foundation` re-exports Darwin's
/// `log(_:)`, the natural logarithm. Overload resolution would pick correctly
/// by argument type, but a symbol every file reaches for should not share a
/// name with a maths function.
public func appLog(_ message: String) { Log.shared.write(message) }
