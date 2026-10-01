import Foundation
import Testing
@testable import NativeVoiceCore

/// swift-testing builds a fresh instance of the suite for every test, so
/// `init` and `deinit` take the place of setUp and tearDown and each test
/// gets its own empty directory.
@Suite struct LogTests: ~Copyable {
    private let dir: URL

    init() throws {
        dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("nvlog-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    // deinit cannot throw, hence `try?`.
    deinit { try? FileManager.default.removeItem(at: dir) }

    private func makeLog(maxBytes: Int = 1_000_000) -> Log {
        Log(path: dir.appendingPathComponent("nv.log").path, maxBytes: maxBytes)
    }

    @Test func writesLineWithDateAndTime() throws {
        let log = makeLog()
        log.write("hello")
        log.drain()
        // Trailing newline trimmed first: with plain .regularExpression the
        // `$` anchor does not match ahead of it, so the pattern would fail on
        // a line that is in fact correct.
        let text = try String(contentsOfFile: log.path, encoding: .utf8)
            .trimmingCharacters(in: .newlines)
        // Expect "[MM-dd HH:mm:ss] hello". A time without a date made lines
        // from different days indistinguishable in the predecessor.
        #expect(text.range(of: #"^\[\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] hello$"#,
                           options: .regularExpression) != nil)
    }

    @Test func concurrentWritesNeitherInterleaveNorGoMissing() throws {
        let log = makeLog()
        let count = 400
        DispatchQueue.concurrentPerform(iterations: count) { i in
            log.write("line-\(i)")
        }
        log.drain()
        let text = try String(contentsOfFile: log.path, encoding: .utf8)
        let lines = text.split(separator: "\n")
        #expect(lines.count == count)

        // Counting lines is not enough: a race that dropped one write and
        // duplicated another would still produce 400 well-formed lines. The
        // indices have to be exactly 0..<count, each once.
        var seen = Set<Int>()
        for line in lines {
            guard let range = line.range(of: #"^\[\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] line-\d+$"#,
                                         options: .regularExpression),
                  range.lowerBound == line.startIndex else {
                Issue.record("garbled line: \(line)")
                continue
            }
            if let dash = line.range(of: "line-", options: .backwards),
               let index = Int(line[dash.upperBound...]) {
                seen.insert(index)
            }
        }
        #expect(seen == Set(0..<count))
    }

    @Test func smallLogIsNotRotated() throws {
        let log = makeLog(maxBytes: 1000)
        log.write(String(repeating: "x", count: 100))
        log.drain()
        log.rotateIfNeeded()
        #expect(!(FileManager.default.fileExists(atPath: log.path + ".1")))
    }

    @Test func oversizedLogIsMovedAside() throws {
        let log = makeLog(maxBytes: 200)
        for i in 0..<60 { log.write("padding \(i)") }
        log.drain()
        log.rotateIfNeeded()
        #expect(FileManager.default.fileExists(atPath: log.path + ".1"))
        #expect(!(FileManager.default.fileExists(atPath: log.path)))
    }

    @Test func onlyOnePreviousBatchIsKept() throws {
        let log = makeLog(maxBytes: 200)
        for i in 0..<60 { log.write("first \(i)") }
        log.drain(); log.rotateIfNeeded()
        for i in 0..<60 { log.write("second \(i)") }
        log.drain(); log.rotateIfNeeded()
        let kept = try String(contentsOfFile: log.path + ".1", encoding: .utf8)
        #expect(kept.contains("second 0"))
        #expect(!(kept.contains("first 0")))
    }

    @Test func growthIsBoundedWithoutAnyoneCallingRotate() throws {
        // Rotation has to happen by itself. A logger that only shrinks when
        // some caller remembers to ask would grow without bound on a machine
        // that stays awake for weeks — and nothing in the app would notice.
        let log = makeLog(maxBytes: 200)
        for i in 0..<600 { log.write("line \(i)") }
        log.drain()
        #expect(FileManager.default.fileExists(atPath: log.path + ".1"))
    }

    @Test func writingToAMissingDirectoryDoesNotCrash() {
        let log = Log(path: "/this/path/does/not/exist/nv.log", maxBytes: 1000)
        log.write("still alive")
        log.drain()
        log.rotateIfNeeded()
    }

    @Test func aFileItCannotWriteNeitherCrashesNorWedgesTheLogger() throws {
        // The missing-directory case short-circuits before any real I/O. This
        // one actually attempts a write that the file system refuses, and
        // then proves the logger still works afterwards — a logger that dies
        // on one bad write would take the whole app with it.
        let file = dir.appendingPathComponent("readonly.log")
        try Data().write(to: file)
        let fm = FileManager.default
        try fm.setAttributes([.posixPermissions: 0o444], ofItemAtPath: file.path)

        let log = Log(path: file.path, maxBytes: 1_000_000)
        log.write("this one cannot land")
        log.drain()

        try fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        log.write("this one can")
        log.drain()

        let text = try String(contentsOfFile: file.path, encoding: .utf8)
        #expect(text.contains("this one can"))
        #expect(!(text.contains("this one cannot land")))
    }
}
