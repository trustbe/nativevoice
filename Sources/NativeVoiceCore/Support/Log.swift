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

    public init(path: String, maxBytes: Int = 1_000_000) {
        self.path = path
        self.maxBytes = maxBytes
        self.queue = DispatchQueue(label: "com.trustbe.nativevoice.log")
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        self.formatter = f
    }

    public func write(_ message: String) {
        let line = "[\(formatter.string(from: Date()))] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        queue.async { [path] in
            FileHandle.standardError.write(data)
            if let handle = FileHandle(forWritingAtPath: path) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            } else {
                try? data.write(to: URL(fileURLWithPath: path))
            }
        }
    }

    /// Waits for queued writes to reach the file. Tests need it; production
    /// never calls it.
    public func drain() {
        queue.sync { }
    }

    /// Moves the log aside once it outgrows `maxBytes`, keeping one previous
    /// batch. Without this the file grows forever — every key press adds
    /// lines and nothing ever removes them.
    public func rotateIfNeeded() {
        queue.sync { [path, maxBytes] in
            let fm = FileManager.default
            guard let attrs = try? fm.attributesOfItem(atPath: path),
                  let size = attrs[.size] as? Int, size > maxBytes else { return }
            let previous = path + ".1"
            try? fm.removeItem(atPath: previous)
            try? fm.moveItem(atPath: path, toPath: previous)
        }
    }
}

extension Log {
    public static let shared = Log(
        path: NSString(string: "~/Library/Logs/NativeVoice.log").expandingTildeInPath)
}

/// Shorthand used throughout the app.
public func log(_ message: String) { Log.shared.write(message) }
