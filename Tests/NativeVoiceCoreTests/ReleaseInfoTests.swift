import Foundation
import Testing
@testable import NativeVoiceCore

@Suite struct ReleaseInfoTests {

    private func payload(tag: String, assets: [String]) -> Data {
        let object: [String: Any] = [
            "tag_name": tag,
            "html_url": "https://github.com/trustbe/nativevoice/releases/tag/\(tag)",
            "assets": assets.map { ["name": $0,
                                    "browser_download_url": "https://example.test/\($0)"] },
        ]
        return try! JSONSerialization.data(withJSONObject: object)
    }

    @Test func readsTheVersionAndTheArchive() {
        let release = ReleaseInfo.parse(payload(tag: "v1.2.0",
                                                assets: ["NativeVoice-v1.2.0.zip"]))
        #expect(release?.version == "1.2.0")
        #expect(release?.archiveURL.lastPathComponent == "NativeVoice-v1.2.0.zip")
    }

    @Test func aTagWithoutALeadingVIsFine() {
        #expect(ReleaseInfo.parse(payload(tag: "1.2.0", assets: ["a.zip"]))?.version == "1.2.0")
    }

    @Test func aReleaseWithNoArchiveIsNotOffered() {
        // Review Focus 1: a release published with only a DMG, or with the
        // upload still running, must not become an update that downloads
        // nothing.
        #expect(ReleaseInfo.parse(payload(tag: "v1.2.0", assets: [])) == nil)
        #expect(ReleaseInfo.parse(payload(tag: "v1.2.0", assets: ["notes.txt"])) == nil)
    }

    @Test func aDmgAloneIsNotAnUpdate() {
        // The DMG is for people. The updater replaces a bundle and needs the zip.
        #expect(ReleaseInfo.parse(payload(tag: "v1.2.0",
                                          assets: ["NativeVoice-v1.2.0.dmg"])) == nil)
    }

    @Test func rubbishIsNotARelease() {
        #expect(ReleaseInfo.parse(Data("{}".utf8)) == nil)
        #expect(ReleaseInfo.parse(Data("not json".utf8)) == nil)
    }

    @Test func newerVersionsAreRecognised() {
        #expect(ReleaseInfo.isNewer("1.2.0", than: "1.1.9"))
        #expect(ReleaseInfo.isNewer("2.0.0", than: "1.9.9"))
        #expect(ReleaseInfo.isNewer("1.0.1", than: "1.0.0"))
    }

    @Test func theSameVersionIsNotNewer() {
        #expect(!ReleaseInfo.isNewer("1.0.0", than: "1.0.0"))
        #expect(!ReleaseInfo.isNewer("1.0.0", than: "1.0.1"))
    }

    @Test func differentLengthsCompareByValue() {
        // Review Focus 3. "1.0" and "1.0.0" are the same release; a build that
        // nags its user to install the version they already have is worse than
        // one that never checks.
        #expect(!ReleaseInfo.isNewer("1.0", than: "1.0.0"))
        #expect(!ReleaseInfo.isNewer("1.0.0", than: "1.0"))
        #expect(ReleaseInfo.isNewer("1.0.1", than: "1.0"))
    }

    @Test func aPrereleaseTagDoesNotParseAsHigher() {
        // Review Focus 2. "1.1.0-beta" must not read as 1.1.0 and offer itself
        // to someone running the finished 1.1.0.
        #expect(!ReleaseInfo.isNewer("1.1.0-beta", than: "1.1.0"))
    }

    @Test func rubbishVersionsDoNotOfferThemselves() {
        #expect(!ReleaseInfo.isNewer("", than: "1.0.0"))
        #expect(!ReleaseInfo.isNewer("not-a-version", than: "1.0.0"))
    }
}
