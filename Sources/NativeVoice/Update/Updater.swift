import AppKit
import NativeVoiceCore

/// Checks for a newer release and, if asked, installs it.
///
/// No Sparkle and no framework: this is one request, one download and one
/// directory swap, and a dependency that updates itself is a strange thing to
/// take on in a tool whose argument is that you can read what it does.
enum Updater {
    static let feedURL = URL(string:
        "https://api.github.com/repos/trustbe/nativevoice/releases/latest")!

    /// The signing identity every build of this app carries. A downloaded
    /// bundle that does not match is not ours, and installing it would make
    /// the updater a way to put somebody else's code on the machine.
    static let teamID = "5XJALC3SPQ"

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String ?? "0"
    }

    static func check() async -> ReleaseInfo? {
        var request = URLRequest(url: feedURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let code = (response as? HTTPURLResponse)?.statusCode,
               !(200..<300).contains(code) {
                appLog("update check: HTTP \(code)")
                return nil
            }
            guard let release = ReleaseInfo.parse(data) else {
                appLog("update check: no installable release in the answer")
                return nil
            }
            guard ReleaseInfo.isNewer(release.version, than: currentVersion) else {
                appLog("update check: \(currentVersion) is current")
                return nil
            }
            return release
        } catch {
            appLog("update check: \(error.localizedDescription)")
            return nil
        }
    }

    /// Downloads, verifies the signature, and swaps the bundle.
    ///
    /// Returns a message to show, or nil when it worked. Every failure says
    /// which step failed: an updater that reports "something went wrong" after
    /// moving a directory leaves somebody not knowing whether their app is
    /// still there.
    static func install(_ release: ReleaseInfo) async -> String? {
        let manager = FileManager.default
        let scratch = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("nativevoice-update-\(UUID().uuidString)")
        defer { try? manager.removeItem(at: scratch) }

        do {
            try manager.createDirectory(at: scratch, withIntermediateDirectories: true)
        } catch {
            return String(localized: "Could not prepare a download folder.", bundle: .module)
        }

        let zip = scratch.appendingPathComponent("update.zip")
        do {
            let (downloaded, response) = try await URLSession.shared.download(from: release.archiveURL)
            if let code = (response as? HTTPURLResponse)?.statusCode,
               !(200..<300).contains(code) {
                return String(localized: "The download failed (HTTP \(code)).", bundle: .module)
            }
            try manager.moveItem(at: downloaded, to: zip)
        } catch {
            appLog("update: download failed: \(error.localizedDescription)")
            return String(localized: "The download failed.", bundle: .module)
        }

        guard run("/usr/bin/ditto", ["-x", "-k", zip.path, scratch.path]) else {
            return String(localized: "The download could not be unpacked.", bundle: .module)
        }

        guard let unpacked = (try? manager.contentsOfDirectory(at: scratch,
                                                              includingPropertiesForKeys: nil))?
            .first(where: { $0.pathExtension == "app" })
        else {
            return String(localized: "The download did not contain an application.",
                          bundle: .module)
        }

        // Review Focus 4. Without this the updater is a way to install
        // anything that can answer the feed URL.
        guard isSignedByUs(unpacked) else {
            appLog("update: refused — \(unpacked.lastPathComponent) is not signed by \(teamID)")
            return String(localized: """
                The download was not signed by the same developer as this copy, \
                so it was not installed.
                """, bundle: .module)
        }

        let destination = Bundle.main.bundleURL
        let backup = scratch.appendingPathComponent("previous.app")
        do {
            try manager.moveItem(at: destination, to: backup)
        } catch {
            appLog("update: could not move the old bundle: \(error.localizedDescription)")
            return String(localized: """
                The old version could not be moved aside. Nothing was changed.
                """, bundle: .module)
        }
        do {
            try manager.moveItem(at: unpacked, to: destination)
        } catch {
            // Put it back. Leaving no application at all is the one outcome
            // worse than failing to update.
            try? manager.moveItem(at: backup, to: destination)
            appLog("update: install failed, old version restored: \(error.localizedDescription)")
            return String(localized: """
                The new version could not be put in place, so the old one was \
                restored.
                """, bundle: .module)
        }
        appLog("update: installed \(release.version)")
        return nil
    }

    private static func isSignedByUs(_ bundle: URL) -> Bool {
        let output = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["-dv", "--verbose=2", bundle.path]
        process.standardError = output
        process.standardOutput = output
        do { try process.run() } catch { return false }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return false }
        return String(decoding: data, as: UTF8.self).contains("TeamIdentifier=\(teamID)")
    }

    private static func run(_ tool: String, _ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}
