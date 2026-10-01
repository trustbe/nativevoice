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

        // `replaceItemAt` is only atomic — and only documented to leave the
        // original item untouched on failure — when the original and the
        // replacement are on the same volume; across volumes it simply
        // errors. The download was unpacked under `scratch`, which is
        // wherever `NSTemporaryDirectory()` happens to be, so it is staged
        // again here into a directory the OS hands back on the destination's
        // own volume before the swap is attempted.
        let staged: URL
        let replacementDir: URL
        do {
            replacementDir = try manager.url(for: .itemReplacementDirectory,
                                              in: .userDomainMask,
                                              appropriateFor: destination,
                                              create: true)
            staged = replacementDir.appendingPathComponent(unpacked.lastPathComponent)
            if manager.fileExists(atPath: staged.path) {
                try manager.removeItem(at: staged)
            }
            try manager.moveItem(at: unpacked, to: staged)
        } catch {
            appLog("update: could not stage the new bundle: \(error.localizedDescription)")
            return String(localized: """
                Could not prepare the new version for installation. Nothing \
                was changed.
                """, bundle: .module)
        }
        defer { try? manager.removeItem(at: replacementDir) }

        // Review Focus (data loss). The previous version of this swap moved
        // the old bundle aside by hand, moved the new one in, and on failure
        // tried to move the old one back with `try?` — discarding whether
        // that worked — and then told the user their old version "was
        // restored" unconditionally. Reproduced: with `TMPDIR` on another
        // volume, the move-aside succeeds (the app is now gone from
        // /Applications), the move-in fails, the silently-discarded restore
        // also fails, and the message still claims a restore that did not
        // happen — right before the enclosing `defer` deletes the one copy
        // that could have put it back. `replaceItemAt` performs the same
        // exchange as one operation that is documented to guarantee no data
        // loss: on failure the original item is left either at its original
        // location or, if something unusual happened to it, at a location
        // named in the thrown error's `NSFileOriginalItemLocationKey`. So
        // the failure path below reports whichever of those is actually
        // true instead of asserting a restore nothing confirmed.
        do {
            _ = try manager.replaceItemAt(destination, withItemAt: staged)
        } catch {
            let stillAt = (error as NSError).userInfo["NSFileOriginalItemLocationKey"] as? URL
            let path = stillAt?.path ?? destination.path
            appLog("update: install failed, previous version left at \(path): \(error.localizedDescription)")
            return String(localized: """
                The new version could not be installed. Your previous copy \
                was not touched; it is still at \(path).
                """, bundle: .module)
        }
        appLog("update: installed \(release.version)")
        return nil
    }

    /// Verifies the downloaded bundle is genuinely signed with our team ID.
    ///
    /// `codesign -d`/`-dv` is a *display* command, not a verification one: it
    /// prints whatever is in the signature's own free-form fields and does
    /// not check that the signature is intact. Both its exit status and its
    /// output are attacker-controlled, which made the previous version of
    /// this check — exit 0 plus a substring search for
    /// `TeamIdentifier=<ours>` in that output — bypassable two ways, both
    /// reproduced: (1) `codesign --identifier 'x TeamIdentifier=<ours>' …`
    /// signs ad hoc with anyone's key and echoes our team ID verbatim on an
    /// `Identifier=` line that the substring match cannot tell apart from
    /// the real `TeamIdentifier=` line; (2) a signed bundle with a file
    /// added afterwards, so `_CodeSignature` no longer matches the contents,
    /// still prints the genuine ID and still exits 0. `codesign --verify` is
    /// the actual verification command, and `-R` constrains what it accepts
    /// to a code requirement anchored on Apple's root with our team ID in
    /// the certificate — not a line of text anywhere in the output — so only
    /// its exit status is read here; nothing from codesign is parsed.
    private static func isSignedByUs(_ bundle: URL) -> Bool {
        run("/usr/bin/codesign", [
            "--verify", "--deep", "--strict",
            "-R", #"=anchor apple generic and certificate leaf[subject.OU] = "\#(teamID)""#,
            bundle.path,
        ])
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
