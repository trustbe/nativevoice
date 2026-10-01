import Testing
import Foundation
@testable import NativeVoiceCore

/// swift-testing vytvari novou instanci sady na kazdy test, takze `init`
/// a `deinit` nahrazuji setUp a tearDown a kazdy test dostane vlastni
/// prazdnou slozku.
@Suite struct LogTests: ~Copyable {
    private let dir: URL

    init() throws {
        dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("nvlog-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    // deinit nesmi vyhazovat, proto `try?`.
    deinit { try? FileManager.default.removeItem(at: dir) }

    private func makeLog(maxBytes: Int = 1_000_000) -> Log {
        Log(path: dir.appendingPathComponent("nv.log").path, maxBytes: maxBytes)
    }

    @Test func writesLineWithDateAndTime() throws {
        let log = makeLog()
        log.write("hello")
        log.drain()
        let text = try String(contentsOfFile: log.path, encoding: .utf8)
        // Expect "[MM-dd HH:mm:ss] hello". A time without a date made lines
        // from different days indistinguishable in the predecessor.
        #expect(text.range(of: #"^\[\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] hello$"#,
                           options: .regularExpression) != nil)
    }

    @Test func concurrentWritesDoNotInterleave() throws {
        let log = makeLog()
        let count = 400
        DispatchQueue.concurrentPerform(iterations: count) { i in
            log.write("line-\(i)")
        }
        log.drain()
        let text = try String(contentsOfFile: log.path, encoding: .utf8)
        let lines = text.split(separator: "\n")
        #expect(lines.count == count)
        for line in lines {
            #expect(line.range(of: #"^\[\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] line-\d+$"#,
                               options: .regularExpression) != nil,
                    "garbled line: \(line)")
        }
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

    @Test func writingToAnUnwritablePathDoesNotCrash() {
        let log = Log(path: "/this/path/does/not/exist/nv.log", maxBytes: 1000)
        log.write("still alive")
        log.drain()
        log.rotateIfNeeded()
    }
}
