# NativeVoice — plán 1: základ a diktovací smyčka

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Postavit nový projekt NativeVoice a v něm funkční diktovací smyčku — podržení klávesy nahraje hlas, ElevenLabs ho přepíše, text se vloží pod kurzor.

**Architecture:** Swift Package se dvěma cíli. `NativeVoiceCore` je knihovna s veškerou logikou, která nepotřebuje AppKit — sestavení HTTP požadavku, rozbor odpovědi, bity modifikátorů, předvolby, slovník, log. `NativeVoice` je spustitelný cíl s lepidlem na AppKit a AVFoundation. Dělení není akademické: všechno v knihovně se dá otestovat přes `swift test` bez sítě, bez mikrofonu a bez oken, a právě tam leží kód, u kterého čtenář bude chtít ověřit, co se děje s jeho hlasem a klíčem.

**Tech Stack:** Swift 5.9+, Swift Package Manager, AppKit, AVFoundation, ServiceManagement, Security, XCTest. Žádné balíčky třetích stran.

**Spec:** `docs/superpowers/specs/2026-10-01-nativevoice-design.md`

## Global Constraints

Platí pro každý úkol. Hodnoty jsou opsané ze specu doslova.

- **Jazyk kódu, komentářů, dokumentace a rozhraní: angličtina.** Spec: „výsledný kód, dokumentace i web budou anglicky."
- **Žádné balíčky třetích stran.** Jen systémové frameworky.
- **Bundle ID `com.trustbe.nativevoice`.** Nikde `cz.nextup`, nikde `MyVoiceInput`.
- **Minimální systém macOS 13.0.** Univerzální binárka arm64 + x86_64.
- **`CFBundleShortVersionString` = `0.1.0`** po celou dobu vývoje. **`CFBundleVersion` = rostoucí celé číslo**, začíná na `1`. Apple: *„three non-negative, period-separated integers with the first integer being greater than zero"*, jen číslice a tečky — nikdy přípona typu `-dev`, nikdy nula na začátku.
- **Repozitář je soukromý a nic se nevydává.** První vydání je `1.0.0` v den zveřejnění, mimo tento plán.
- **Žádný obchodní otisk.** Nikde Journeyman, CFMOTO, Fakturoid, Helios, Nextup, ISIR, ISDS. Výchozí slovník je prázdný.
- **Žádná čísla ze skutečného účtu** v kódu ani v dokumentaci. Cena se uvádí jako sazba $0.22/hod; se slovníkem $0.27/hod (keyterm prompting je $0.05/hod navíc).
- **Žádné řetězce rozhraní natvrdo v kódu.** Všechny přes String Catalog, i když se ve v1 dodává jen angličtina.
- **Tap poslouchá výhradně `flagsChanged`.** `keyDown` se do masky nesmí dostat za žádných okolností.

## Review Focus

Vstupy, na kterých software potká skutečného člověka a které spec nezmiňuje. Každý řádek má svůj test v úkolu, který ten kód vlastní.

1. **Jazyk systému, který Scribe v nejvyšším pásmu nemá** (třeba `he`, `th`, `ar`) — výchozí volba musí spadnout na angličtinu, ne na prázdnou hodnotu ani na pád. *Test v úkolu 5.*
2. **Slovník přes limity API** — víc než 1000 výrazů nebo položka delší než 50 znaků. Musí se oříznout, ne nechat server odmítnout celý přepis. *Test v úkolu 4.*
3. **Ve schránce není text, ale obrázek nebo soubor** — obnova po vložení nesmí vrátit `nil` jako prázdný řetězec a tím schránku vymazat. *Test v úkolu 7.*
4. **Odpověď serveru, která není přepis** — chybové JSON, prázdné tělo, nevalidní JSON, HTTP 401. Každý případ musí dát vlastní srozumitelnou hlášku. *Test v úkolu 4.*
5. **Ztracená událost o puštění klávesy** — po zastavení stropem musí stav odpovídat skutečnosti, jinak se další stisk zahodí jako „žádná změna". *Test v úkolu 8.*

---

## Struktura souborů

```
Package.swift                                    definice balíčku, dva cíle
.gitignore                                       .build, DerivedData, *.app
LICENSE                                          MIT, Jan Kafka, 2026
README.md                                        zatím kostra, plní plán 3
.github/workflows/ci.yml                         swift build + swift test
docs/
  specs/2026-10-01-nativevoice-design.md         přenesený spec
  plans/2026-10-01-nativevoice-foundation.md     tento plán

Sources/NativeVoiceCore/                         knihovna, testovatelná
  Support/Log.swift                              serializovaný zápis + rotace
  Support/SecretStore.swift                      protokol + Klíčenka + fake
  Support/Vocabulary.swift                       čtení a ořez slovníku
  Transcription/Transcriber.swift                protokol + typ výsledku
  Transcription/ElevenLabsRequest.swift          sestavení multipart požadavku
  Transcription/ElevenLabsResponse.swift         rozbor odpovědi
  Input/TriggerKey.swift                         modifikátory a bity zařízení
  Settings/Language.swift                        36 jazyků pásma ≤5 % WER
  Settings/RecordingLimit.swift                  strop délky nahrávky

Sources/NativeVoice/                             spustitelný cíl, AppKit
  App/main.swift                                 vstupní bod
  App/AppDelegate.swift                          stav, menu, drátování
  Input/EventTap.swift                           CGEventTap, jen flagsChanged
  Audio/Recorder.swift                           AVAudioEngine, hladina, špička
  Transcription/ElevenLabsClient.swift           URLSession
  Output/Paste.swift                             schránka a vložení
  Resources/Localizable.xcstrings                String Catalog
  Resources/Info.plist                           bundle, oprávnění

Tests/NativeVoiceCoreTests/                      jeden soubor na modul
Scripts/build-app.sh                             .app z produktu swift build
```

---

### Task 1: Kostra projektu

Konec úkolu: `swift build` i `swift test` projdou, `Scripts/build-app.sh` vyrobí spustitelný `.app`, který se objeví v liště.

**Files:**
- Create: `~/Devel/NativeVoice/Package.swift`
- Create: `~/Devel/NativeVoice/.gitignore`
- Create: `~/Devel/NativeVoice/LICENSE`
- Create: `~/Devel/NativeVoice/Sources/NativeVoiceCore/Support/Placeholder.swift`
- Create: `~/Devel/NativeVoice/Sources/NativeVoice/App/main.swift`
- Create: `~/Devel/NativeVoice/Sources/NativeVoice/Resources/Info.plist`
- Create: `~/Devel/NativeVoice/Scripts/build-app.sh`
- Create: `~/Devel/NativeVoice/Tests/NativeVoiceCoreTests/PlaceholderTests.swift`
- Create: `~/Devel/NativeVoice/.github/workflows/ci.yml`

**Interfaces:**
- Consumes: nic, je to první úkol
- Produces: cíl knihovny `NativeVoiceCore`, cíl `NativeVoice`, `Scripts/build-app.sh <version> <build>`

- [ ] **Step 1: Založit složku a git**

```bash
mkdir -p ~/Devel/NativeVoice
cd ~/Devel/NativeVoice
git init
git config user.name "Jan Kafka"
git config user.email "jenicek@me.com"
mkdir -p Sources/NativeVoiceCore/{Support,Transcription,Input,Settings,Resources}
mkdir -p Sources/NativeVoice/{App,Input,Audio,Transcription,Output,Resources}
mkdir -p Tests/NativeVoiceCoreTests Scripts docs/specs docs/plans .github/workflows
```

- [ ] **Step 2: Přenést spec a plán**

```bash
cp ~/Devel/MyVoiceInput/docs/superpowers/specs/2026-10-01-nativevoice-design.md docs/specs/
cp ~/Devel/MyVoiceInput/docs/superpowers/plans/2026-10-01-nativevoice-foundation.md docs/plans/
```

- [ ] **Step 3: Package.swift**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NativeVoice",
    platforms: [.macOS(.v13)],
    targets: [
        // Everything that does not need AppKit lives here, so it can be
        // tested with `swift test` — no network, no microphone, no windows.
        // The library gets its own String Catalog: String(localized:) resolves
        // against the calling module's bundle, so strings defined here would
        // never find the executable's catalog.
        .target(name: "NativeVoiceCore",
                resources: [.process("Resources/Localizable.xcstrings")]),
        .executableTarget(
            name: "NativeVoice",
            dependencies: ["NativeVoiceCore"],
            exclude: ["Resources/Info.plist"]
        ),
        .testTarget(name: "NativeVoiceCoreTests", dependencies: ["NativeVoiceCore"]),
    ]
)
```

- [ ] **Step 4: .gitignore a LICENSE**

`.gitignore`:
```
.build/
.swiftpm/
DerivedData/
*.app
*.dmg
*.zip
.DS_Store
```

`LICENSE` — doslovný text MIT s `Copyright (c) 2026 Jan Kafka`.

- [ ] **Step 5: String Catalog pro knihovnu**

`Sources/NativeVoiceCore/Resources/Localizable.xcstrings`:
```json
{
  "sourceLanguage" : "en",
  "strings" : { },
  "version" : "1.0"
}
```

Knihovna má vlastní katalog schválně: `String(localized:)` hledá v bundlu
volajícího modulu, takže řetězce definované v knihovně by katalog
spustitelného cíle nikdy nenašly. Uvnitř knihovny se proto vždy píše
`String(localized: …, bundle: .module)`.

- [ ] **Step 6: Dočasný obsah, aby cíle nebyly prázdné**

`Sources/NativeVoiceCore/Support/Placeholder.swift`:
```swift
/// Removed in Task 2. Exists so the target compiles before Log.swift lands.
enum Placeholder {
    static let marker = "nativevoice"
}
```

`Tests/NativeVoiceCoreTests/PlaceholderTests.swift`:
```swift
import XCTest
@testable import NativeVoiceCore

final class PlaceholderTests: XCTestCase {
    func testTargetCompilesAndTestsRun() {
        XCTAssertEqual(Placeholder.marker, "nativevoice")
    }
}
```

- [ ] **Step 7: Spustit testy — musí projít**

Run: `cd ~/Devel/NativeVoice && swift test`
Expected: PASS, 1 test

- [ ] **Step 8: Info.plist**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>NativeVoice</string>
    <key>CFBundleDisplayName</key><string>NativeVoice</string>
    <key>CFBundleIdentifier</key><string>com.trustbe.nativevoice</string>
    <key>CFBundleExecutable</key><string>NativeVoice</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <!-- Menu bar only: no Dock icon, no window at launch. -->
    <key>LSUIElement</key><true/>
    <!-- Without this key macOS denies microphone access outright. -->
    <key>NSMicrophoneUsageDescription</key>
    <string>NativeVoice records your voice while you hold the trigger key and transcribes it to text.</string>
    <key>NSHumanReadableCopyright</key>
    <string>Jan Kafka · MIT-licensed, contributions welcome</string>
</dict>
</plist>
```

- [ ] **Step 9: Scripts/build-app.sh**

```bash
#!/bin/bash
# Builds a universal .app from the SwiftPM product.
#
# Version arguments are mandatory and validated: CFBundleVersion must be
# digits and periods only with a first integer above zero (Apple's rule),
# and a build that silently carried the wrong version has bitten this
# project's predecessor more than once.
set -euo pipefail

VERSION="${1:-}"
BUILD="${2:-}"
[ -n "$VERSION" ] && [ -n "$BUILD" ] || {
    echo "usage: $0 <short-version> <build-number>   e.g. $0 0.1.0 7" >&2
    exit 2
}
[[ "$BUILD" =~ ^[1-9][0-9]*(\.[0-9]+)*$ ]] || {
    echo "build number must be digits and periods, first integer > 0: got '$BUILD'" >&2
    exit 2
}

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/.build/app"
APP="$OUT/NativeVoice.app"

rm -rf "$OUT"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "▸ building universal binary"
swift build -c release --arch arm64 --arch x86_64 --package-path "$ROOT"
BIN="$(swift build -c release --arch arm64 --arch x86_64 --package-path "$ROOT" --show-bin-path)"
cp "$BIN/NativeVoice" "$APP/Contents/MacOS/NativeVoice"

echo "▸ Info.plist ($VERSION / $BUILD)"
cp "$ROOT/Sources/NativeVoice/Resources/Info.plist" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$APP/Contents/Info.plist"

# Resource bundles produced by SwiftPM (String Catalog) sit next to the binary.
for b in "$BIN"/*.bundle; do
    [ -e "$b" ] && cp -R "$b" "$APP/Contents/Resources/"
done

echo "▸ signing ad-hoc (Developer ID comes in plan 3)"
codesign --force --sign - --timestamp=none "$APP"

echo "✓ $APP"
```

```bash
chmod +x Scripts/build-app.sh
```

- [ ] **Step 10: Minimální main.swift, ať je co spustit**

```swift
import AppKit

/// Menu bar only. A Dock icon and a window at launch would both be wrong
/// for a utility that is driven entirely by one held key.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "mic",
                                           accessibilityDescription: "NativeVoice")
        statusItem.button?.image?.isTemplate = true

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit NativeVoice",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        statusItem.menu = menu
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
```

- [ ] **Step 11: Postavit .app a ověřit, že naskočí do lišty**

Run: `cd ~/Devel/NativeVoice && ./Scripts/build-app.sh 0.1.0 1 && open .build/app/NativeVoice.app`
Expected: v horní liště se objeví ikona mikrofonu; v menu je jediná položka *Quit NativeVoice*.

Ověřit verzi v hotovém balíčku:
```bash
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" .build/app/NativeVoice.app/Contents/Info.plist   # 0.1.0
/usr/libexec/PlistBuddy -c "Print :CFBundleVersion"             .build/app/NativeVoice.app/Contents/Info.plist   # 1
```

Ověřit, že skript odmítne nesmyslné číslo sestavení:
```bash
./Scripts/build-app.sh 0.1.0 0.1-dev; echo "exit=$?"
```
Expected: `build number must be digits and periods, first integer > 0`, `exit=2`

Pak aplikaci ukončit: `pkill -f NativeVoice.app/Contents/MacOS`

- [ ] **Step 12: CI**

`.github/workflows/ci.yml`:
```yaml
name: CI
on: [push, pull_request]
jobs:
  build-and-test:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - name: Build
        run: swift build
      - name: Test
        run: swift test
```

- [ ] **Step 13: Commit**

```bash
cd ~/Devel/NativeVoice
git add -A
git commit -m "chore: project skeleton, SwiftPM package, app build script

Two targets: NativeVoiceCore holds everything testable without AppKit,
NativeVoice holds the AppKit glue. The split exists so the code a reader
will want to audit — what happens to the audio and the key — is reachable
from swift test.

build-app.sh validates the build number: Apple requires digits and periods
with a first integer above zero, and a wrong version string shipped twice
in the predecessor before anyone noticed."
```

---

### Task 2: Log

Konec úkolu: zápis z více vláken se nepromíchá, log se při přerůstání odloží stranou, řádky nesou datum.

**Files:**
- Create: `Sources/NativeVoiceCore/Support/Log.swift`
- Create: `Tests/NativeVoiceCoreTests/LogTests.swift`
- Delete: `Sources/NativeVoiceCore/Support/Placeholder.swift`
- Delete: `Tests/NativeVoiceCoreTests/PlaceholderTests.swift`

**Interfaces:**
- Consumes: nic
- Produces: `Log.shared` typu `Log`, `func log(_ message: String)`, `Log.init(path: String, maxBytes: Int)`, `Log.rotateIfNeeded()`, `Log.path: String`

- [ ] **Step 1: Napsat padající testy**

`Tests/NativeVoiceCoreTests/LogTests.swift`:
```swift
import XCTest
@testable import NativeVoiceCore

final class LogTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("nvlog-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func makeLog(maxBytes: Int = 1_000_000) -> Log {
        Log(path: dir.appendingPathComponent("nv.log").path, maxBytes: maxBytes)
    }

    func testWritesLineWithDateAndTime() throws {
        let log = makeLog()
        log.write("hello")
        log.drain()
        let text = try String(contentsOfFile: log.path, encoding: .utf8)
        // Expect "[MM-dd HH:mm:ss] hello". A time without a date made lines
        // from different days indistinguishable in the predecessor.
        XCTAssertNotNil(text.range(of: #"^\[\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] hello$"#,
                                   options: .regularExpression))
    }

    func testConcurrentWritesDoNotInterleave() throws {
        let log = makeLog()
        let count = 400
        DispatchQueue.concurrentPerform(iterations: count) { i in
            log.write("line-\(i)")
        }
        log.drain()
        let text = try String(contentsOfFile: log.path, encoding: .utf8)
        let lines = text.split(separator: "\n")
        XCTAssertEqual(lines.count, count)
        for line in lines {
            XCTAssertNotNil(line.range(of: #"^\[\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] line-\d+$"#,
                                       options: .regularExpression),
                            "garbled line: \(line)")
        }
    }

    func testSmallLogIsNotRotated() throws {
        let log = makeLog(maxBytes: 1000)
        log.write(String(repeating: "x", count: 100))
        log.drain()
        log.rotateIfNeeded()
        XCTAssertFalse(FileManager.default.fileExists(atPath: log.path + ".1"))
    }

    func testOversizedLogIsMovedAside() throws {
        let log = makeLog(maxBytes: 200)
        for i in 0..<60 { log.write("padding \(i)") }
        log.drain()
        log.rotateIfNeeded()
        XCTAssertTrue(FileManager.default.fileExists(atPath: log.path + ".1"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: log.path))
    }

    func testOnlyOnePreviousBatchIsKept() throws {
        let log = makeLog(maxBytes: 200)
        for i in 0..<60 { log.write("first \(i)") }
        log.drain(); log.rotateIfNeeded()
        for i in 0..<60 { log.write("second \(i)") }
        log.drain(); log.rotateIfNeeded()
        let kept = try String(contentsOfFile: log.path + ".1", encoding: .utf8)
        XCTAssertTrue(kept.contains("second 0"))
        XCTAssertFalse(kept.contains("first 0"))
    }

    func testWritingToAnUnwritablePathDoesNotCrash() {
        let log = Log(path: "/this/path/does/not/exist/nv.log", maxBytes: 1000)
        log.write("still alive")
        log.drain()
        log.rotateIfNeeded()
    }
}
```

- [ ] **Step 2: Spustit a ověřit, že padají**

Run: `swift test --filter LogTests`
Expected: FAIL, `cannot find 'Log' in scope`

- [ ] **Step 3: Implementace**

`Sources/NativeVoiceCore/Support/Log.swift`:
```swift
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
```

- [ ] **Step 4: Smazat dočasné soubory a spustit testy**

```bash
rm Sources/NativeVoiceCore/Support/Placeholder.swift Tests/NativeVoiceCoreTests/PlaceholderTests.swift
swift test --filter LogTests
```
Expected: PASS, 6 testů

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(support): serialized log with rotation and dated lines

Writes go through a private queue because the audio tap, the event tap and
the main thread all log; interleaved writes produced unreadable lines.

Lines carry MM-dd, not just a clock. In the predecessor a bare time made
entries from different days indistinguishable and led to a wrong diagnosis.

Rotation at 1 MB keeps one previous batch; nothing else ever shrank the file."
```

---

### Task 3: Úložiště klíče

Konec úkolu: klíč se ukládá do Klíčenky, prázdná hodnota ho maže, a mazání je trvalé — žádný záložní zdroj ho nevzkřísí.

**Files:**
- Create: `Sources/NativeVoiceCore/Support/SecretStore.swift`
- Create: `Tests/NativeVoiceCoreTests/SecretStoreTests.swift`

**Interfaces:**
- Consumes: `log(_:)` z úkolu 2
- Produces:
  - `public protocol SecretStore { func apiKey() -> String?; @discardableResult func save(_ key: String) -> Bool; @discardableResult func delete() -> Bool }`
  - `public final class KeychainSecretStore: SecretStore` — `init(service: String, account: String)`
  - `public final class InMemorySecretStore: SecretStore` — pro testy a náhledy
  - `public extension SecretStore { var hasKey: Bool }`

- [ ] **Step 1: Napsat padající testy**

`Tests/NativeVoiceCoreTests/SecretStoreTests.swift`:
```swift
import XCTest
@testable import NativeVoiceCore

final class SecretStoreTests: XCTestCase {

    // The real Keychain is not touched here. Tests against the login keychain
    // raise an authorization dialog, which would hang CI and, worse, train
    // the developer to click Allow on prompts they did not read.
    private func makeStore() -> InMemorySecretStore { InMemorySecretStore() }

    func testStartsEmpty() {
        XCTAssertNil(makeStore().apiKey())
        XCTAssertFalse(makeStore().hasKey)
    }

    func testSavesAndReadsBack() {
        let s = makeStore()
        XCTAssertTrue(s.save("sk_example"))
        XCTAssertEqual(s.apiKey(), "sk_example")
        XCTAssertTrue(s.hasKey)
    }

    func testTrimsSurroundingWhitespace() {
        let s = makeStore()
        s.save("  sk_example\n")
        XCTAssertEqual(s.apiKey(), "sk_example")
    }

    func testEmptyStringRemovesTheKey() {
        let s = makeStore()
        s.save("sk_example")
        XCTAssertTrue(s.save(""))
        XCTAssertNil(s.apiKey())
        XCTAssertFalse(s.hasKey)
    }

    func testWhitespaceOnlyAlsoRemovesTheKey() {
        let s = makeStore()
        s.save("sk_example")
        s.save("   \n ")
        XCTAssertNil(s.apiKey())
    }

    func testDeleteIsIdempotent() {
        let s = makeStore()
        XCTAssertTrue(s.delete())
        XCTAssertTrue(s.delete())
        XCTAssertNil(s.apiKey())
    }

    func testDeletedKeyStaysDeleted() {
        // The predecessor read a plain file as a fallback and a deleted key
        // silently came back. There is no fallback source here at all, and
        // this test exists to keep it that way.
        let s = makeStore()
        s.save("sk_example")
        s.delete()
        XCTAssertNil(s.apiKey())
        XCTAssertNil(s.apiKey())
    }
}
```

- [ ] **Step 2: Spustit a ověřit, že padají**

Run: `swift test --filter SecretStoreTests`
Expected: FAIL, `cannot find type 'InMemorySecretStore' in scope`

- [ ] **Step 3: Implementace**

`Sources/NativeVoiceCore/Support/SecretStore.swift`:
```swift
import Foundation
import Security

/// Where the ElevenLabs API key lives.
///
/// A protocol, not a concrete type, for two reasons: tests must not touch the
/// user's login keychain (reading an item raises an authorization dialog), and
/// a reader auditing what happens to their key can see the whole surface in
/// one short file.
public protocol SecretStore {
    func apiKey() -> String?
    @discardableResult func save(_ key: String) -> Bool
    @discardableResult func delete() -> Bool
}

public extension SecretStore {
    var hasKey: Bool { apiKey() != nil }
}

/// Normalizes what a user typed. Empty means "remove", not "store nothing".
func normalizedSecret(_ raw: String) -> String? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

/// Keychain-backed store.
///
/// There is deliberately **no fallback source**. The predecessor also read a
/// plain file, and because the "already migrated" flag was only set on one
/// code path, deleting the key from the Keychain silently restored it from
/// that file. A key the user deleted must stay deleted.
public final class KeychainSecretStore: SecretStore {
    private let service: String
    private let account: String
    private let lock = NSLock()
    private var cache: String??     // nil = not read yet, .some(nil) = no key

    public init(service: String = "com.trustbe.nativevoice",
                account: String = "elevenlabs-api-key") {
        self.service = service
        self.account = account
    }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    public func apiKey() -> String? {
        lock.lock()
        if let cached = cache { lock.unlock(); return cached }
        lock.unlock()

        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var out: AnyObject?
        var result: String?
        if SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
           let data = out as? Data, let text = String(data: data, encoding: .utf8) {
            result = normalizedSecret(text)
        }

        lock.lock(); cache = .some(result); lock.unlock()
        return result
    }

    @discardableResult
    public func save(_ key: String) -> Bool {
        guard let value = normalizedSecret(key) else { return delete() }
        let data = Data(value.utf8)

        let update = SecItemUpdate(baseQuery as CFDictionary,
                                   [kSecValueData as String: data] as CFDictionary)
        switch update {
        case errSecSuccess:
            invalidate(); return true
        case errSecItemNotFound:
            break
        default:
            // Falling through on every error made SecItemAdd report a
            // duplicate instead of the real cause, such as a denied dialog.
            log("keychain update failed: OSStatus \(update)")
            return false
        }

        var add = baseQuery
        add[kSecValueData as String] = data
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else {
            log("keychain add failed: OSStatus \(status)")
            return false
        }
        invalidate()
        return true
    }

    @discardableResult
    public func delete() -> Bool {
        let status = SecItemDelete(baseQuery as CFDictionary)
        invalidate()
        return status == errSecSuccess || status == errSecItemNotFound
    }

    private func invalidate() { lock.lock(); cache = nil; lock.unlock() }
}

/// Used by tests and by previews. Never reaches a shipping build path.
public final class InMemorySecretStore: SecretStore {
    private let lock = NSLock()
    private var value: String?

    public init(initial: String? = nil) { self.value = initial }

    public func apiKey() -> String? { lock.lock(); defer { lock.unlock() }; return value }

    @discardableResult
    public func save(_ key: String) -> Bool {
        guard let normalized = normalizedSecret(key) else { return delete() }
        lock.lock(); value = normalized; lock.unlock()
        return true
    }

    @discardableResult
    public func delete() -> Bool {
        lock.lock(); value = nil; lock.unlock()
        return true
    }
}
```

- [ ] **Step 4: Spustit testy**

Run: `swift test --filter SecretStoreTests`
Expected: PASS, 7 testů

- [ ] **Step 5: Ověřit skutečnou Klíčenku ručně, jednou**

Automatický test to dělat nebude — čtení položky vyvolá potvrzovací dialog, a nacvičovat si klikání na *Povolit* u dialogů, které nikdo nečetl, je přesně špatný návyk.

```bash
swift -e '
import Foundation
// paste the contents of SecretStore.swift above this line when running manually
' 2>/dev/null || true
```

Místo toho po úkolu 8, kdy aplikace existuje: zadat klíč v aplikaci, ukončit ji, spustit znovu a ověřit, že ho zná. Zapsat výsledek do commitu.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(support): Keychain-backed secret store behind a protocol

No fallback source of any kind. In the predecessor a plain file acted as a
backup and a key deleted from the Keychain silently came back, because the
'already migrated' flag was set on one code path only.

Tests run against an in-memory store: reading a real Keychain item raises an
authorization dialog, which would hang CI and teach the wrong habit."
```

---

### Task 4: Slovník a požadavek na ElevenLabs

Konec úkolu: požadavek se sestaví bez sítě a dá otestovat bajt po bajtu; odpověď se rozebere včetně všech způsobů selhání.

**Files:**
- Create: `Sources/NativeVoiceCore/Support/Vocabulary.swift`
- Create: `Sources/NativeVoiceCore/Transcription/Transcriber.swift`
- Create: `Sources/NativeVoiceCore/Transcription/ElevenLabsRequest.swift`
- Create: `Sources/NativeVoiceCore/Transcription/ElevenLabsResponse.swift`
- Create: `Tests/NativeVoiceCoreTests/VocabularyTests.swift`
- Create: `Tests/NativeVoiceCoreTests/ElevenLabsTests.swift`

**Interfaces:**
- Consumes: `log(_:)`
- Produces:
  - `public enum TranscriptionResult { case text(String); case failure(TranscriptionError) }`
  - `public enum TranscriptionError { case noAPIKey, unreachable, badResponse, server(String); var userMessage: String }`
  - `public protocol Transcriber { func transcribe(audio: URL, language: String, keyterms: [String], removeFillers: Bool) async -> TranscriptionResult }`
  - `public enum Vocabulary { static func terms(from text: String) -> [String]; static let maxTerms = 1000; static let maxTermLength = 50; static let template: String }`
  - `public struct ElevenLabsRequest { static func build(audio: Data, filename: String, language: String, keyterms: [String], removeFillers: Bool, apiKey: String, boundary: String) -> URLRequest }`
  - `public enum ElevenLabsResponse { static func parse(data: Data, httpStatus: Int) -> TranscriptionResult }`

- [ ] **Step 1: Napsat padající testy slovníku**

`Tests/NativeVoiceCoreTests/VocabularyTests.swift`:
```swift
import XCTest
@testable import NativeVoiceCore

final class VocabularyTests: XCTestCase {

    func testOneTermPerLine() {
        let terms = Vocabulary.terms(from: "Journeyman\nsafetensors\nWER")
        XCTAssertEqual(terms, ["Journeyman", "safetensors", "WER"])
    }

    func testIgnoresCommentsAndBlankLines() {
        let text = """
        # One term per line
        Journeyman

           # indented comment
        safetensors
        """
        XCTAssertEqual(Vocabulary.terms(from: text), ["Journeyman", "safetensors"])
    }

    func testTrimsSurroundingWhitespace() {
        XCTAssertEqual(Vocabulary.terms(from: "  Journeyman  \n\tsafetensors\t"),
                       ["Journeyman", "safetensors"])
    }

    func testDropsDuplicatesKeepingFirst() {
        XCTAssertEqual(Vocabulary.terms(from: "a\nb\na"), ["a", "b"])
    }

    func testTermLongerThanFiftyCharactersIsTruncated() {
        // The API accepts at most 50 characters per term. Sending a longer one
        // must not cost the user the whole transcription.
        let long = String(repeating: "x", count: 80)
        let terms = Vocabulary.terms(from: long)
        XCTAssertEqual(terms.count, 1)
        XCTAssertEqual(terms[0].count, 50)
    }

    func testAtMostOneThousandTerms() {
        let text = (1...1500).map { "term\($0)" }.joined(separator: "\n")
        XCTAssertEqual(Vocabulary.terms(from: text).count, 1000)
    }

    func testEmptyFileYieldsNoTerms() {
        XCTAssertTrue(Vocabulary.terms(from: "").isEmpty)
        XCTAssertTrue(Vocabulary.terms(from: "# only a comment\n\n").isEmpty)
    }

    func testTemplateIsEmptyOfTermsAndNamesNoCustomer() {
        // The predecessor shipped a vocabulary naming the author's clients.
        XCTAssertTrue(Vocabulary.terms(from: Vocabulary.template).isEmpty)
        let forbidden = ["Journeyman", "CFMOTO", "Fakturoid", "Helios",
                         "Nextup", "ISIR", "ISDS"]
        for name in forbidden {
            XCTAssertFalse(Vocabulary.template.contains(name), "template mentions \(name)")
        }
    }
}
```

- [ ] **Step 2: Napsat padající testy požadavku a odpovědi**

`Tests/NativeVoiceCoreTests/ElevenLabsTests.swift`:
```swift
import XCTest
@testable import NativeVoiceCore

final class ElevenLabsTests: XCTestCase {

    private let boundary = "TESTBOUNDARY"

    private func build(language: String = "ces",
                       keyterms: [String] = [],
                       removeFillers: Bool = false,
                       apiKey: String = "sk_test") -> URLRequest {
        ElevenLabsRequest.build(audio: Data("RIFFfake".utf8),
                                filename: "speech.wav",
                                language: language,
                                keyterms: keyterms,
                                removeFillers: removeFillers,
                                apiKey: apiKey,
                                boundary: boundary)
    }

    private func body(_ request: URLRequest) -> String {
        String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
    }

    // MARK: - Request

    func testPostsToTheSpeechToTextEndpoint() {
        let r = build()
        XCTAssertEqual(r.httpMethod, "POST")
        XCTAssertEqual(r.url?.absoluteString,
                       "https://api.elevenlabs.io/v1/speech-to-text")
    }

    func testCarriesTheKeyInAHeaderAndNowhereElse() {
        // The key must never end up in a URL, a query string or a process
        // argument. `ps -ww` shows arguments to every user on the machine.
        let r = build(apiKey: "sk_secret")
        XCTAssertEqual(r.value(forHTTPHeaderField: "xi-api-key"), "sk_secret")
        XCTAssertFalse(r.url!.absoluteString.contains("sk_secret"))
        XCTAssertFalse(body(r).contains("sk_secret"))
    }

    func testSendsModelAndLanguage() {
        let b = body(build(language: "mkd"))
        XCTAssertTrue(b.contains("name=\"model_id\"\r\n\r\nscribe_v2"))
        XCTAssertTrue(b.contains("name=\"language_code\"\r\n\r\nmkd"))
    }

    func testSendsOneFieldPerKeyterm() {
        let b = body(build(keyterms: ["Journeyman", "safetensors"]))
        XCTAssertTrue(b.contains("name=\"keyterms\"\r\n\r\nJourneyman"))
        XCTAssertTrue(b.contains("name=\"keyterms\"\r\n\r\nsafetensors"))
    }

    func testOmitsKeytermsWhenThereAreNone() {
        XCTAssertFalse(body(build(keyterms: [])).contains("keyterms"))
    }

    func testFillerRemovalIsOptOut() {
        XCTAssertFalse(body(build(removeFillers: false)).contains("no_verbatim"))
        XCTAssertTrue(body(build(removeFillers: true))
            .contains("name=\"no_verbatim\"\r\n\r\ntrue"))
    }

    func testBodyIsWellFormedMultipart() {
        let r = build(keyterms: ["a"])
        XCTAssertEqual(r.value(forHTTPHeaderField: "Content-Type"),
                       "multipart/form-data; boundary=\(boundary)")
        let b = body(r)
        XCTAssertTrue(b.hasPrefix("--\(boundary)\r\n"))
        XCTAssertTrue(b.hasSuffix("--\(boundary)--\r\n"))
        XCTAssertTrue(b.contains(
            "name=\"file\"; filename=\"speech.wav\"\r\nContent-Type: audio/wav"))
    }

    // MARK: - Response

    func testParsesTranscript() {
        let data = Data(#"{"text":"toto je zkouška"}"#.utf8)
        guard case .text(let t) = ElevenLabsResponse.parse(data: data, httpStatus: 200) else {
            return XCTFail("expected text")
        }
        XCTAssertEqual(t, "toto je zkouška")
    }

    func testEmptyTranscriptIsStillASuccess() {
        // Silence is not an error of the request. The caller decides what to
        // tell the user, because only it knows the measured input level.
        let data = Data(#"{"text":""}"#.utf8)
        guard case .text(let t) = ElevenLabsResponse.parse(data: data, httpStatus: 200) else {
            return XCTFail("expected text")
        }
        XCTAssertEqual(t, "")
    }

    func testEmptyBodyMeansUnreachable() {
        guard case .failure(let e) = ElevenLabsResponse.parse(data: Data(), httpStatus: 0) else {
            return XCTFail("expected failure")
        }
        XCTAssertEqual(e, .unreachable)
    }

    func testNonJSONBodyMeansBadResponse() {
        let data = Data("<html>502 Bad Gateway</html>".utf8)
        guard case .failure(let e) = ElevenLabsResponse.parse(data: data, httpStatus: 502) else {
            return XCTFail("expected failure")
        }
        XCTAssertEqual(e, .badResponse)
    }

    func testServerMessageIsSurfacedFromDetailObject() {
        let data = Data(#"{"detail":{"message":"Invalid API key"}}"#.utf8)
        guard case .failure(let e) = ElevenLabsResponse.parse(data: data, httpStatus: 401) else {
            return XCTFail("expected failure")
        }
        XCTAssertEqual(e, .server("Invalid API key"))
    }

    func testServerMessageIsSurfacedFromDetailString() {
        let data = Data(#"{"detail":"quota exceeded"}"#.utf8)
        guard case .failure(let e) = ElevenLabsResponse.parse(data: data, httpStatus: 429) else {
            return XCTFail("expected failure")
        }
        XCTAssertEqual(e, .server("quota exceeded"))
    }

    func testJSONWithoutTextOrDetailMeansBadResponse() {
        let data = Data(#"{"unexpected":1}"#.utf8)
        guard case .failure(let e) = ElevenLabsResponse.parse(data: data, httpStatus: 200) else {
            return XCTFail("expected failure")
        }
        XCTAssertEqual(e, .badResponse)
    }

    func testLongServerMessageIsShortenedForTheHUD() {
        let long = String(repeating: "e", count: 300)
        let data = Data(#"{"detail":"\#(long)"}"#.utf8)
        guard case .failure(.server(let message)) =
                ElevenLabsResponse.parse(data: data, httpStatus: 400) else {
            return XCTFail("expected server failure")
        }
        XCTAssertLessThanOrEqual(message.count, 90)
    }

    func testEveryErrorHasANonEmptyUserMessage() {
        let all: [TranscriptionError] = [.noAPIKey, .unreachable, .badResponse,
                                         .server("boom")]
        for e in all { XCTAssertFalse(e.userMessage.isEmpty, "\(e)") }
    }
}
```

- [ ] **Step 3: Spustit a ověřit, že padají**

Run: `swift test --filter VocabularyTests && swift test --filter ElevenLabsTests`
Expected: FAIL, `cannot find 'Vocabulary' in scope`

- [ ] **Step 4: Implementace slovníku**

`Sources/NativeVoiceCore/Support/Vocabulary.swift`:
```swift
import Foundation

/// Custom terms sent along with the audio.
///
/// This is the single most effective lever on quality the app has — measured,
/// not assumed. On one recording, with nothing else changed: `Journeyman`
/// became `German`, `Cloudflare Worker` became `Cloud for Work`,
/// `safetensors` became `Sage Sensor`. With the vocabulary, all correct.
///
/// It works because proper nouns and jargon are a finite known list.
public enum Vocabulary {
    /// API limits. Exceeding either costs the whole transcription, so the
    /// list is clipped here rather than letting the server reject it.
    public static let maxTerms = 1000
    public static let maxTermLength = 50

    public static func terms(from text: String) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            let term = String(line.prefix(maxTermLength))
            guard seen.insert(term).inserted else { continue }
            out.append(term)
            if out.count == maxTerms { break }
        }
        return out
    }

    /// Shipped as the initial file. Deliberately empty of actual terms: the
    /// predecessor shipped a vocabulary naming the author's clients.
    public static let template = """
    # Custom vocabulary — one term per line, # starts a comment.
    #
    # This is the most effective way to improve accuracy. Proper nouns and
    # jargon are what transcription gets wrong, and they are a finite list
    # only you know. Add the names of people, products and projects you say
    # out loud.
    #
    # Read before every transcription, so changes apply immediately.
    # At most 1000 terms, 50 characters each.
    #
    # For example, a developer might add:
    #   PostgreSQL
    #   Kubernetes
    #   OAuth

    """
}
```

- [ ] **Step 5: Implementace rozhraní přepisu**

`Sources/NativeVoiceCore/Transcription/Transcriber.swift`:
```swift
import Foundation

/// Why a transcription did not produce text.
///
/// Separate cases, not one catch-all. The predecessor reported every failure
/// as "Transcription failed — check the API key and connection", from which a
/// missing key could not be told apart from a dropped network.
public enum TranscriptionError: Equatable {
    case noAPIKey
    case unreachable
    case badResponse
    case server(String)

    /// Short enough for the HUD, specific enough to act on.
    public var userMessage: String {
        switch self {
        // `bundle: .module` is mandatory inside the library: without it the
        // lookup goes to the main bundle and silently returns the key.
        case .noAPIKey:
            return String(localized: "No API key. Add one in the menu.", bundle: .module)
        case .unreachable:
            return String(localized: "Could not reach the server.", bundle: .module)
        case .badResponse:
            return String(localized: "Unexpected reply from the server.", bundle: .module)
        case .server(let text): return text
        }
    }
}

public enum TranscriptionResult: Equatable {
    case text(String)
    case failure(TranscriptionError)
}

/// One engine. The app talks to this, never to a concrete client, so a second
/// engine is a new conformance rather than a rewrite — and so tests can run
/// the whole dictation loop without a network.
public protocol Transcriber {
    func transcribe(audio: URL,
                    language: String,
                    keyterms: [String],
                    removeFillers: Bool) async -> TranscriptionResult
}
```

- [ ] **Step 6: Implementace sestavení požadavku**

`Sources/NativeVoiceCore/Transcription/ElevenLabsRequest.swift`:
```swift
import Foundation

/// Builds the multipart request. Pure: no network, no file system, so every
/// byte that leaves this machine can be asserted on in a test.
///
/// The key travels in a header. It must never reach a URL, a query string or
/// a process argument — `ps -ww` shows arguments to every user on the machine,
/// which is why the predecessor had to pipe them into `curl` instead. Here the
/// key does not leave the process at all.
public struct ElevenLabsRequest {
    public static let endpoint = URL(string: "https://api.elevenlabs.io/v1/speech-to-text")!
    public static let model = "scribe_v2"

    public static func build(audio: Data,
                             filename: String,
                             language: String,
                             keyterms: [String],
                             removeFillers: Bool,
                             apiKey: String,
                             boundary: String = "nativevoice-\(UUID().uuidString)") -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("multipart/form-data; boundary=\(boundary)",
                         forHTTPHeaderField: "Content-Type")

        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            body.append("\(value)\r\n")
        }

        field("model_id", model)
        field("language_code", language)
        if removeFillers { field("no_verbatim", "true") }
        for term in keyterms { field("keyterms", term) }

        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        body.append("Content-Type: audio/wav\r\n\r\n")
        body.append(audio)
        body.append("\r\n")
        body.append("--\(boundary)--\r\n")

        request.httpBody = body
        return request
    }
}

private extension Data {
    mutating func append(_ text: String) {
        if let d = text.data(using: .utf8) { append(d) }
    }
}
```

- [ ] **Step 7: Implementace rozboru odpovědi**

`Sources/NativeVoiceCore/Transcription/ElevenLabsResponse.swift`:
```swift
import Foundation

public enum ElevenLabsResponse {
    /// Longest server message shown in the HUD. Beyond this it stops being a
    /// message and starts being a wall.
    static let maxServerMessage = 90

    public static func parse(data: Data, httpStatus: Int) -> TranscriptionResult {
        // An empty body means the connection never arrived anywhere. A server
        // that rejected the request would have sent one.
        guard !data.isEmpty else { return .failure(.unreachable) }

        guard let object = try? JSONSerialization.jsonObject(with: data),
              let json = object as? [String: Any] else {
            log("unparseable response (HTTP \(httpStatus)): "
                + String(decoding: data.prefix(300), as: UTF8.self))
            return .failure(.badResponse)
        }

        if let text = json["text"] as? String {
            if let seconds = json["audio_duration_secs"] as? Double {
                log(String(format: "API received %.2fs of audio", seconds))
            }
            return .text(text)
        }

        // The shape of an error body is not guaranteed anywhere, so it is read
        // defensively and falls back to a generic message.
        let detail = (json["detail"] as? [String: Any])?["message"] as? String
            ?? json["detail"] as? String
            ?? json["message"] as? String

        log("no transcript in response (HTTP \(httpStatus)): "
            + String(decoding: data.prefix(300), as: UTF8.self))

        guard let detail, !detail.isEmpty else { return .failure(.badResponse) }
        return .failure(.server(String(detail.prefix(maxServerMessage))))
    }
}
```

- [ ] **Step 8: Spustit testy**

Run: `swift test --filter VocabularyTests && swift test --filter ElevenLabsTests`
Expected: PASS, 8 + 16 testů

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "feat(transcription): pure request builder, response parser, vocabulary

Request building and response parsing are pure functions, so every byte that
leaves the machine is asserted in a test and no test needs a network.

The key travels in a header and never reaches a URL or a process argument.
URLSession replaces the predecessor's curl subprocess, which had to pipe the
key through stdin because 'ps -ww' shows arguments to every local user.

Failures are distinct cases. The predecessor reported all of them as one
message, from which a missing key could not be told from a dropped network.

Vocabulary clips to the API limits (1000 terms, 50 characters) rather than
letting the server reject the whole transcription, and ships empty: the
predecessor's default vocabulary named the author's clients."
```

---

### Task 5: Jazyky a strop délky nahrávky

Konec úkolu: 36 jazyků nejvyššího pásma Scribe, výchozí podle systému s poctivým náhradním řešením, a nastavitelný strop.

**Files:**
- Create: `Sources/NativeVoiceCore/Settings/Language.swift`
- Create: `Sources/NativeVoiceCore/Settings/RecordingLimit.swift`
- Create: `Tests/NativeVoiceCoreTests/LanguageTests.swift`
- Create: `Tests/NativeVoiceCoreTests/RecordingLimitTests.swift`

**Interfaces:**
- Consumes: nic
- Produces:
  - `public struct Language: Equatable { public let code: String; public var name: String }`, `Language.all: [Language]`, `Language.named(_ code: String) -> Language?`, `Language.forSystem(preferred: [String]) -> Language`, `Language.sortedForDisplay() -> [Language]`
  - `public enum RecordingLimit: Int, CaseIterable { case oneMinute = 60, twoMinutes = 120, fiveMinutes = 300, tenMinutes = 600, none = 0 }`, `.seconds: TimeInterval?`, `RecordingLimit.default` = `.twoMinutes`, `RecordingLimit(storedSeconds:)`

- [ ] **Step 1: Napsat padající testy jazyků**

`Tests/NativeVoiceCoreTests/LanguageTests.swift`:
```swift
import XCTest
@testable import NativeVoiceCore

final class LanguageTests: XCTestCase {

    func testOffersTheWholeTopAccuracyTier() {
        // 36 languages, the tier ElevenLabs places at 5% WER or better.
        XCTAssertEqual(Language.all.count, 36)
    }

    func testKeepsTheSmallLanguagesTheProjectExistsFor() {
        // Dropping these would contradict the point of the project: Scribe
        // rates them as accurately as English, and that is the documented
        // difference from every other tool.
        let required = ["bel", "bos", "mkd", "isl", "glg", "lav", "est",
                        "kan", "mal", "ces", "slk", "ukr"]
        for code in required {
            XCTAssertNotNil(Language.named(code), "missing \(code)")
        }
    }

    func testCodesAreThreeLetterAndUnique() {
        let codes = Language.all.map(\.code)
        XCTAssertEqual(Set(codes).count, codes.count, "duplicate language code")
        for code in codes { XCTAssertEqual(code.count, 3, "not ISO-639-3: \(code)") }
    }

    func testEveryLanguageHasAName() {
        for language in Language.all {
            XCTAssertFalse(language.name.isEmpty, "no name for \(language.code)")
        }
    }

    func testSystemLanguageIsMatchedFromATwoLetterTag() {
        XCTAssertEqual(Language.forSystem(preferred: ["cs-CZ"]).code, "ces")
        XCTAssertEqual(Language.forSystem(preferred: ["pl"]).code, "pol")
        XCTAssertEqual(Language.forSystem(preferred: ["pt-BR"]).code, "por")
    }

    func testUnsupportedSystemLanguageFallsBackToEnglish() {
        // Hebrew, Thai and Arabic are not in the top tier. The app must pick
        // English rather than nothing — a user whose system is in an
        // unsupported language still has to be able to dictate.
        XCTAssertEqual(Language.forSystem(preferred: ["he-IL"]).code, "eng")
        XCTAssertEqual(Language.forSystem(preferred: ["th"]).code, "eng")
        XCTAssertEqual(Language.forSystem(preferred: []).code, "eng")
        XCTAssertEqual(Language.forSystem(preferred: ["zz-ZZ", "qq"]).code, "eng")
    }

    func testFirstSupportedPreferenceWins() {
        XCTAssertEqual(Language.forSystem(preferred: ["he-IL", "cs-CZ", "pl"]).code, "ces")
    }

    func testDisplayOrderIsAlphabeticalWithoutFavourites() {
        // No "popular" languages pinned on top. Privileging the big ones
        // would undercut what the project is for.
        let names = Language.sortedForDisplay().map(\.name)
        XCTAssertEqual(names, names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
    }
}
```

- [ ] **Step 2: Napsat padající testy stropu**

`Tests/NativeVoiceCoreTests/RecordingLimitTests.swift`:
```swift
import XCTest
@testable import NativeVoiceCore

final class RecordingLimitTests: XCTestCase {

    func testDefaultIsTwoMinutes() {
        XCTAssertEqual(RecordingLimit.default, .twoMinutes)
        XCTAssertEqual(RecordingLimit.default.seconds, 120)
    }

    func testNoLimitMeansNoDeadline() {
        XCTAssertNil(RecordingLimit.none.seconds)
    }

    func testEveryChoiceHasSecondsExceptNone() {
        for limit in RecordingLimit.allCases where limit != .none {
            XCTAssertNotNil(limit.seconds, "\(limit)")
            XCTAssertGreaterThan(limit.seconds!, 0)
        }
    }

    func testUnknownStoredValueFallsBackToTheDefault() {
        XCTAssertEqual(RecordingLimit(storedSeconds: 999), .default)
        XCTAssertEqual(RecordingLimit(storedSeconds: -1), .default)
    }

    func testStoredZeroMeansNoLimitAndIsNotMistakenForMissing() {
        // Zero is a real choice here, not an absent one. Reading it as
        // "unset" would quietly re-impose a cap the user turned off.
        XCTAssertEqual(RecordingLimit(storedSeconds: 0), RecordingLimit.none)
    }

    func testRoundTripsThroughItsStoredValue() {
        for limit in RecordingLimit.allCases {
            XCTAssertEqual(RecordingLimit(storedSeconds: limit.rawValue), limit)
        }
    }
}
```

- [ ] **Step 3: Spustit a ověřit, že padají**

Run: `swift test --filter LanguageTests && swift test --filter RecordingLimitTests`
Expected: FAIL, `cannot find 'Language' in scope`

- [ ] **Step 4: Implementace jazyků**

`Sources/NativeVoiceCore/Settings/Language.swift`:
```swift
import Foundation

/// A transcription language.
///
/// The list is Scribe's top accuracy tier — the 36 languages the provider
/// places at 5% word error rate or better. It is **not narrowed**. Belarusian,
/// Bosnian, Macedonian, Icelandic, Galician, Latvian, Estonian, Kannada and
/// Malayalam are in it, which is precisely why this project exists: a small
/// language rated as accurately as English is the documented difference from
/// every other tool. Dropping them to keep the menu short would contradict
/// the product.
///
/// Tiers below this one (High to 10%, Good to 20%, Moderate to 50%) are not
/// offered. Dictation with one word in five wrong is not usable, and offering
/// it would promise something it cannot carry.
public struct Language: Equatable, Hashable {
    /// ISO-639-3. The API accepts both 639-1 and 639-3; the longer form is
    /// unambiguous.
    public let code: String
    /// Shown in the menu, localized by the system where a translation exists.
    public var name: String {
        Locale.current.localizedString(forLanguageCode: code)?.capitalized
            ?? fallbackName
    }
    private let fallbackName: String

    init(_ code: String, _ fallbackName: String) {
        self.code = code
        self.fallbackName = fallbackName
    }

    public static let all: [Language] = [
        Language("bel", "Belarusian"),   Language("bos", "Bosnian"),
        Language("bul", "Bulgarian"),    Language("cat", "Catalan"),
        Language("hrv", "Croatian"),     Language("ces", "Czech"),
        Language("dan", "Danish"),       Language("nld", "Dutch"),
        Language("eng", "English"),      Language("est", "Estonian"),
        Language("fin", "Finnish"),      Language("fra", "French"),
        Language("glg", "Galician"),     Language("deu", "German"),
        Language("ell", "Greek"),        Language("hun", "Hungarian"),
        Language("isl", "Icelandic"),    Language("ind", "Indonesian"),
        Language("ita", "Italian"),      Language("jpn", "Japanese"),
        Language("kan", "Kannada"),      Language("lav", "Latvian"),
        Language("mkd", "Macedonian"),   Language("msa", "Malay"),
        Language("mal", "Malayalam"),    Language("nor", "Norwegian"),
        Language("pol", "Polish"),       Language("por", "Portuguese"),
        Language("ron", "Romanian"),     Language("rus", "Russian"),
        Language("slk", "Slovak"),       Language("spa", "Spanish"),
        Language("swe", "Swedish"),      Language("tur", "Turkish"),
        Language("ukr", "Ukrainian"),    Language("vie", "Vietnamese"),
    ]

    public static let english = Language("eng", "English")

    public static func named(_ code: String) -> Language? {
        all.first { $0.code == code }
    }

    /// Alphabetical by display name, with **no favourites pinned on top**.
    /// Putting the big languages first would weaken what the list says.
    public static func sortedForDisplay() -> [Language] {
        all.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// First preferred system language that Scribe transcribes well.
    ///
    /// Falls back to English, never to nothing: a user whose system runs in
    /// Hebrew or Thai — neither is in the top tier — still has to be able to
    /// dictate the moment the app starts.
    public static func forSystem(preferred: [String] = Locale.preferredLanguages) -> Language {
        for tag in preferred {
            guard let short = tag.split(separator: "-").first.map(String.init) else { continue }
            if let match = all.first(where: {
                Locale(identifier: $0.code).language.languageCode?.identifier == short
                    || $0.code == short
            }) {
                return match
            }
        }
        return english
    }
}
```

- [ ] **Step 5: Implementace stropu**

`Sources/NativeVoiceCore/Settings/RecordingLimit.swift`:
```swift
import Foundation

/// Longest a single recording may run.
///
/// Not a cost control. Recording stops when the key is released, and release
/// is learned from a tap event. If that one event never arrives — the system
/// disabled the tap, the machine slept with the key held — nothing stops the
/// recording and it runs until somebody notices. A multi-minute file would
/// then be uploaded and paid for.
///
/// On reaching the cap the recording is **closed and transcribed, not
/// discarded**. Throwing it away would throw away what the user actually said.
public enum RecordingLimit: Int, CaseIterable, Equatable {
    case oneMinute = 60
    case twoMinutes = 120
    case fiveMinutes = 300
    case tenMinutes = 600
    case none = 0

    /// Two minutes by default: continuous dictation longer than that is rare,
    /// while a stuck recording is exactly what the cap is for.
    public static let `default` = RecordingLimit.twoMinutes

    public var seconds: TimeInterval? { self == .none ? nil : TimeInterval(rawValue) }

    /// Zero is a real choice ("no limit"), so it must not be read as "unset".
    public init(storedSeconds: Int) {
        self = RecordingLimit(rawValue: storedSeconds) ?? .default
    }
}
```

- [ ] **Step 6: Spustit testy**

Run: `swift test --filter LanguageTests && swift test --filter RecordingLimitTests`
Expected: PASS, 8 + 6 testů

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat(settings): 36-language top tier and a recording length cap

The language list is Scribe's top accuracy tier and is not narrowed.
Belarusian, Macedonian, Icelandic, Galician, Kannada and Malayalam are the
reason the project exists; trimming them for a shorter menu would contradict
the product. Lower tiers are not offered at all — one word in five wrong is
not dictation.

A system language outside the tier falls back to English rather than nothing.

The cap is a safety net, not a budget: release is learned from a tap event,
and if that event is lost nothing else stops the recording. On reaching the
cap the audio is transcribed, never discarded."
```

---

### Task 6: Spouštěcí klávesa

Konec úkolu: osm modifikátorů, rozlišení levé a pravé strany podle bitu zařízení, ověřené na syntetických příznacích.

**Files:**
- Create: `Sources/NativeVoiceCore/Input/TriggerKey.swift`
- Create: `Tests/NativeVoiceCoreTests/TriggerKeyTests.swift`

**Interfaces:**
- Consumes: nic
- Produces: `public enum TriggerKey: String, CaseIterable`, `.keyCode: UInt16`, `.deviceMask: UInt64`, `.menuTitle: String`, `.symbol: String`, `func isHeld(flags: UInt64) -> Bool`, `TriggerKey.default` = `.rightCommand`

- [ ] **Step 1: Napsat padající testy**

`Tests/NativeVoiceCoreTests/TriggerKeyTests.swift`:
```swift
import XCTest
@testable import NativeVoiceCore

final class TriggerKeyTests: XCTestCase {

    // Values from IOLLEvent.h, verified against the header rather than guessed.
    private let NX_DEVICELCTLKEYMASK: UInt64   = 0x00000001
    private let NX_DEVICELSHIFTKEYMASK: UInt64 = 0x00000002
    private let NX_DEVICERSHIFTKEYMASK: UInt64 = 0x00000004
    private let NX_DEVICELCMDKEYMASK: UInt64   = 0x00000008
    private let NX_DEVICERCMDKEYMASK: UInt64   = 0x00000010
    private let NX_DEVICELALTKEYMASK: UInt64   = 0x00000020
    private let NX_DEVICERALTKEYMASK: UInt64   = 0x00000040
    private let NX_DEVICERCTLKEYMASK: UInt64   = 0x00002000

    func testOffersEveryModifierOnBothSides() {
        XCTAssertEqual(TriggerKey.allCases.count, 8)
    }

    func testDefaultIsRightCommand() {
        XCTAssertEqual(TriggerKey.default, .rightCommand)
    }

    func testDeviceMasksMatchTheHeader() {
        XCTAssertEqual(TriggerKey.leftControl.deviceMask,  NX_DEVICELCTLKEYMASK)
        XCTAssertEqual(TriggerKey.leftShift.deviceMask,    NX_DEVICELSHIFTKEYMASK)
        XCTAssertEqual(TriggerKey.rightShift.deviceMask,   NX_DEVICERSHIFTKEYMASK)
        XCTAssertEqual(TriggerKey.leftCommand.deviceMask,  NX_DEVICELCMDKEYMASK)
        XCTAssertEqual(TriggerKey.rightCommand.deviceMask, NX_DEVICERCMDKEYMASK)
        XCTAssertEqual(TriggerKey.leftOption.deviceMask,   NX_DEVICELALTKEYMASK)
        XCTAssertEqual(TriggerKey.rightOption.deviceMask,  NX_DEVICERALTKEYMASK)
        XCTAssertEqual(TriggerKey.rightControl.deviceMask, NX_DEVICERCTLKEYMASK)
    }

    func testMasksAreUnique() {
        let masks = TriggerKey.allCases.map(\.deviceMask)
        XCTAssertEqual(Set(masks).count, masks.count)
    }

    func testRightCommandIsNotConfusedWithLeftCommand() {
        // This is the whole point of reading device bits: the generic
        // maskCommand flag is set for both sides, so it cannot tell them
        // apart. Holding left Command must not start a recording bound to
        // the right one.
        XCTAssertTrue(TriggerKey.rightCommand.isHeld(flags: NX_DEVICERCMDKEYMASK))
        XCTAssertFalse(TriggerKey.rightCommand.isHeld(flags: NX_DEVICELCMDKEYMASK))
        XCTAssertFalse(TriggerKey.leftCommand.isHeld(flags: NX_DEVICERCMDKEYMASK))
    }

    func testHeldWhileOtherModifiersAreAlsoDown() {
        let both = NX_DEVICERCMDKEYMASK | NX_DEVICELSHIFTKEYMASK | 0x20000
        XCTAssertTrue(TriggerKey.rightCommand.isHeld(flags: both))
        XCTAssertTrue(TriggerKey.leftShift.isHeld(flags: both))
        XCTAssertFalse(TriggerKey.rightOption.isHeld(flags: both))
    }

    func testNotHeldWhenNoFlagsAreSet() {
        for key in TriggerKey.allCases {
            XCTAssertFalse(key.isHeld(flags: 0), "\(key)")
        }
    }

    func testKeyCodesAreUnique() {
        let codes = TriggerKey.allCases.map(\.keyCode)
        XCTAssertEqual(Set(codes).count, codes.count)
    }

    func testEveryKeyHasATitleAndASymbol() {
        for key in TriggerKey.allCases {
            XCTAssertFalse(key.menuTitle.isEmpty, "\(key)")
            XCTAssertFalse(key.symbol.isEmpty, "\(key)")
        }
    }

    func testRawValuesAreStableForStorage() {
        // These strings land in UserDefaults. Renaming a case silently resets
        // the user's choice, so the mapping is pinned here.
        XCTAssertEqual(TriggerKey.rightCommand.rawValue, "rightCommand")
        XCTAssertEqual(TriggerKey(rawValue: "leftOption"), .leftOption)
        XCTAssertNil(TriggerKey(rawValue: "middleCommand"))
    }
}
```

- [ ] **Step 2: Spustit a ověřit, že padají**

Run: `swift test --filter TriggerKeyTests`
Expected: FAIL, `cannot find 'TriggerKey' in scope`

- [ ] **Step 3: Implementace**

`Sources/NativeVoiceCore/Input/TriggerKey.swift`:
```swift
import Carbon.HIToolbox
import Foundation

/// The key held to dictate.
///
/// Modifiers only. An ordinary key could not be used: the event tap listens to
/// `flagsChanged` and nothing else. That is a deliberate constraint, not an
/// oversight — a version that also tapped `keyDown` coincided with every
/// keyboard shortcut in the system breaking. The mechanism was never proven;
/// the difference was reproducible, and the narrow mask has run without a
/// repeat ever since.
///
/// Left and right cannot be told apart from `event.flags` alone: the generic
/// command flag is set for both. The side is read from the device-specific bit
/// (`NX_DEVICE*KEYMASK` in `IOLLEvent.h`).
public enum TriggerKey: String, CaseIterable, Equatable {
    case rightCommand, leftCommand
    case rightOption, leftOption
    case rightControl, leftControl
    case rightShift, leftShift

    public static let `default` = TriggerKey.rightCommand

    public var keyCode: UInt16 {
        switch self {
        case .rightCommand: return UInt16(kVK_RightCommand)
        case .leftCommand:  return UInt16(kVK_Command)
        case .rightOption:  return UInt16(kVK_RightOption)
        case .leftOption:   return UInt16(kVK_Option)
        case .rightControl: return UInt16(kVK_RightControl)
        case .leftControl:  return UInt16(kVK_Control)
        case .rightShift:   return UInt16(kVK_RightShift)
        case .leftShift:    return UInt16(kVK_Shift)
        }
    }

    /// Bit set while this specific key is down. Values taken from
    /// `IOLLEvent.h`, not inferred.
    public var deviceMask: UInt64 {
        switch self {
        case .leftControl:  return 0x00000001   // NX_DEVICELCTLKEYMASK
        case .leftShift:    return 0x00000002   // NX_DEVICELSHIFTKEYMASK
        case .rightShift:   return 0x00000004   // NX_DEVICERSHIFTKEYMASK
        case .leftCommand:  return 0x00000008   // NX_DEVICELCMDKEYMASK
        case .rightCommand: return 0x00000010   // NX_DEVICERCMDKEYMASK
        case .leftOption:   return 0x00000020   // NX_DEVICELALTKEYMASK
        case .rightOption:  return 0x00000040   // NX_DEVICERALTKEYMASK
        case .rightControl: return 0x00002000   // NX_DEVICERCTLKEYMASK
        }
    }

    public func isHeld(flags: UInt64) -> Bool { flags & deviceMask != 0 }

    public var menuTitle: String {
        switch self {
        case .rightCommand: return String(localized: "Right Command (⌘)", bundle: .module)
        case .leftCommand:  return String(localized: "Left Command (⌘)", bundle: .module)
        case .rightOption:  return String(localized: "Right Option (⌥)", bundle: .module)
        case .leftOption:   return String(localized: "Left Option (⌥)", bundle: .module)
        case .rightControl: return String(localized: "Right Control (⌃)", bundle: .module)
        case .leftControl:  return String(localized: "Left Control (⌃)", bundle: .module)
        case .rightShift:   return String(localized: "Right Shift (⇧)", bundle: .module)
        case .leftShift:    return String(localized: "Left Shift (⇧)", bundle: .module)
        }
    }

    public var symbol: String {
        switch self {
        case .rightCommand, .leftCommand: return "⌘"
        case .rightOption,  .leftOption:  return "⌥"
        case .rightControl, .leftControl: return "⌃"
        case .rightShift,   .leftShift:   return "⇧"
        }
    }
}
```

- [ ] **Step 4: Spustit testy**

Run: `swift test --filter TriggerKeyTests`
Expected: PASS, 10 testů

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(input): trigger key with device-specific modifier bits

Left and right cannot be distinguished from event.flags: the generic command
flag is set for both sides. The side comes from NX_DEVICE*KEYMASK, and the
tests pin every mask against the values in IOLLEvent.h.

Modifiers only, because the tap listens to flagsChanged and nothing else. A
version that also tapped keyDown coincided with every keyboard shortcut in the
system breaking; the mechanism was never proven but the difference was
reproducible."
```

---

### Task 7: Schránka a vložení

Konec úkolu: text se vloží pod kurzor a původní obsah schránky se vrátí — i když to byl obrázek, a i když mezitím uživatel dal do schránky něco jiného.

**Files:**
- Create: `Sources/NativeVoice/Output/Paste.swift`
- Create: `Sources/NativeVoiceCore/Support/ClipboardRestore.swift`
- Create: `Tests/NativeVoiceCoreTests/ClipboardRestoreTests.swift`

**Interfaces:**
- Consumes: `log(_:)`
- Produces:
  - `public final class ClipboardRestore` — `init(delay: TimeInterval)`, `func schedule(previous: String?, restore: @escaping (String?) -> Void)`, `func cancel()`, `var isPending: Bool`
  - `Paste.deliver(_ text: String, autoPaste: Bool, restore: ClipboardRestore)` ve spustitelném cíli

- [ ] **Step 1: Napsat padající testy**

`Tests/NativeVoiceCoreTests/ClipboardRestoreTests.swift`:
```swift
import XCTest
@testable import NativeVoiceCore

final class ClipboardRestoreTests: XCTestCase {

    func testRestoresThePreviousStringAfterTheDelay() {
        let restore = ClipboardRestore(delay: 0.05)
        let done = expectation(description: "restored")
        var received: String?? = nil
        restore.schedule(previous: "old text") { value in
            received = .some(value); done.fulfill()
        }
        wait(for: [done], timeout: 1)
        XCTAssertEqual(received ?? nil, "old text")
    }

    func testCancelPreventsTheRestore() {
        // Clicking a history entry right after dictating must not have the
        // pending restore throw that entry back out of the clipboard.
        let restore = ClipboardRestore(delay: 0.1)
        var fired = false
        restore.schedule(previous: "old") { _ in fired = true }
        restore.cancel()
        let waited = expectation(description: "waited")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { waited.fulfill() }
        wait(for: [waited], timeout: 1)
        XCTAssertFalse(fired)
    }

    func testSchedulingAgainReplacesThePendingRestore() {
        let restore = ClipboardRestore(delay: 0.05)
        var values: [String?] = []
        let done = expectation(description: "restored once")
        done.expectedFulfillmentCount = 1
        done.assertForOverFulfill = true
        restore.schedule(previous: "first") { v in values.append(v); done.fulfill() }
        restore.schedule(previous: "second") { v in values.append(v); done.fulfill() }
        wait(for: [done], timeout: 1)
        XCTAssertEqual(values, ["second"])
    }

    func testNilPreviousIsPassedThroughAsNil() {
        // The clipboard held an image or a file, so there is no string to put
        // back. Turning that into an empty string would wipe the clipboard.
        let restore = ClipboardRestore(delay: 0.05)
        let done = expectation(description: "restored")
        var received: String?? = nil
        restore.schedule(previous: nil) { value in received = .some(value); done.fulfill() }
        wait(for: [done], timeout: 1)
        XCTAssertNotNil(received)
        XCTAssertNil(received ?? "not nil")
    }

    func testIsPendingReflectsState() {
        let restore = ClipboardRestore(delay: 0.2)
        XCTAssertFalse(restore.isPending)
        restore.schedule(previous: "x") { _ in }
        XCTAssertTrue(restore.isPending)
        restore.cancel()
        XCTAssertFalse(restore.isPending)
    }
}
```

- [ ] **Step 2: Spustit a ověřit, že padají**

Run: `swift test --filter ClipboardRestoreTests`
Expected: FAIL, `cannot find 'ClipboardRestore' in scope`

- [ ] **Step 3: Implementace odložené obnovy**

`Sources/NativeVoiceCore/Support/ClipboardRestore.swift`:
```swift
import Foundation

/// Puts back whatever was on the clipboard before a transcript was pasted.
///
/// Two things this has to get right, both learned the hard way:
///
/// The delay has to outlast a slow receiver. At 0.45 s an Electron app or a
/// remote desktop read the clipboard only after it had been restored and
/// pasted the old contents instead of the transcript.
///
/// The pending restore has to be cancellable. It overwrites the clipboard
/// unconditionally, so anything the user put there in the meantime — a history
/// entry they clicked — would be thrown straight back out.
public final class ClipboardRestore {
    private let delay: TimeInterval
    private let queue: DispatchQueue
    private var work: DispatchWorkItem?

    public init(delay: TimeInterval = 1.2, queue: DispatchQueue = .main) {
        self.delay = delay
        self.queue = queue
    }

    public var isPending: Bool { work != nil }

    /// `previous` stays optional all the way through: the clipboard may have
    /// held an image or a file, and substituting an empty string for that
    /// would wipe it instead of restoring it.
    public func schedule(previous: String?, restore: @escaping (String?) -> Void) {
        cancel()
        let item = DispatchWorkItem { [weak self] in
            restore(previous)
            self?.work = nil
        }
        work = item
        queue.asyncAfter(deadline: .now() + delay, execute: item)
    }

    public func cancel() {
        work?.cancel()
        work = nil
    }
}
```

- [ ] **Step 4: Implementace vložení**

`Sources/NativeVoice/Output/Paste.swift`:
```swift
import AppKit
import NativeVoiceCore

/// Delivers a transcript to wherever the cursor is.
enum Paste {
    /// Synthesizes ⌘V. Posting to the annotated session tap is what reaches
    /// the frontmost application.
    private static func pressCommandV() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        let v: CGKeyCode = 9
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: false)
        else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cgAnnotatedSessionEventTap)
        up.post(tap: .cgAnnotatedSessionEventTap)
    }

    static func deliver(_ text: String, autoPaste: Bool, restore: ClipboardRestore) {
        let board = NSPasteboard.general
        let previous = autoPaste ? board.string(forType: .string) : nil

        board.clearContents()
        board.setString(text, forType: .string)
        guard autoPaste else { return }

        pressCommandV()

        // Put back what the user had. Without this, every dictation silently
        // destroys whatever they had copied.
        restore.schedule(previous: previous) { old in
            let board = NSPasteboard.general
            board.clearContents()
            if let old { board.setString(old, forType: .string) }
        }
    }
}
```

- [ ] **Step 5: Spustit testy**

Run: `swift test --filter ClipboardRestoreTests`
Expected: PASS, 5 testů

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(output): paste under the cursor and restore the clipboard

The restore is a cancellable work item. It overwrites the clipboard
unconditionally, so in the predecessor anything the user put there within the
delay — a history entry they clicked — was thrown straight back out.

The previous value stays optional end to end: the clipboard may have held an
image, and substituting an empty string would wipe it rather than restore it.

1.2 s, not less: at 0.45 s a slow receiver read the clipboard only after the
restore and pasted the old contents instead of the transcript."
```

---

### Task 8: Drátování — celá smyčka

Konec úkolu: podržení klávesy nahraje hlas, ElevenLabs ho přepíše a text se objeví pod kurzorem. Strop funguje a po něm je stav klávesy srovnaný.

**Files:**
- Create: `Sources/NativeVoice/Input/EventTap.swift`
- Create: `Sources/NativeVoice/Audio/Recorder.swift`
- Create: `Sources/NativeVoice/Transcription/ElevenLabsClient.swift`
- Create: `Sources/NativeVoiceCore/Input/HoldTracker.swift`
- Create: `Tests/NativeVoiceCoreTests/HoldTrackerTests.swift`
- Modify: `Sources/NativeVoice/App/main.swift` (rozdělit na `main.swift` + `AppDelegate.swift`)
- Create: `Sources/NativeVoice/App/AppDelegate.swift`
- Create: `Sources/NativeVoice/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: všechno z úkolů 2–7
- Produces: `HoldTracker`, `EventTap`, `Recorder`, `ElevenLabsClient: Transcriber`, `AppDelegate`

- [ ] **Step 1: Napsat padající testy stavu stisku**

`Tests/NativeVoiceCoreTests/HoldTrackerTests.swift`:
```swift
import XCTest
@testable import NativeVoiceCore

final class HoldTrackerTests: XCTestCase {

    private let rightCommand: UInt64 = 0x10
    private let leftCommand: UInt64  = 0x08

    func testFirstPressStartsAHold() {
        var tracker = HoldTracker(key: .rightCommand)
        XCTAssertEqual(tracker.update(flags: rightCommand), .pressed)
    }

    func testReleaseEndsTheHold() {
        var tracker = HoldTracker(key: .rightCommand)
        _ = tracker.update(flags: rightCommand)
        XCTAssertEqual(tracker.update(flags: 0), .released)
    }

    func testRepeatedSameStateIsIgnored() {
        // flagsChanged fires for every modifier, including ones we do not
        // care about. Only a change of our own key is an event.
        var tracker = HoldTracker(key: .rightCommand)
        _ = tracker.update(flags: rightCommand)
        XCTAssertEqual(tracker.update(flags: rightCommand | leftCommand), .unchanged)
        XCTAssertEqual(tracker.update(flags: rightCommand), .unchanged)
    }

    func testOtherModifiersDoNotStartAHold() {
        var tracker = HoldTracker(key: .rightCommand)
        XCTAssertEqual(tracker.update(flags: leftCommand), .unchanged)
    }

    func testForceReleaseMakesTheNextPressRegister() {
        // This is the recording-cap case. The cap exists because a release
        // event can go missing; if the tracker still believed the key was
        // down, the next genuine press would read as "no change" and be
        // dropped — the user would say a whole sentence into nothing.
        var tracker = HoldTracker(key: .rightCommand)
        _ = tracker.update(flags: rightCommand)
        tracker.forceRelease()
        XCTAssertEqual(tracker.update(flags: rightCommand), .pressed)
    }

    func testChangingKeyWhileHeldDoesNotLeaveItStuck() {
        var tracker = HoldTracker(key: .rightCommand)
        _ = tracker.update(flags: rightCommand)
        tracker.key = .leftOption
        XCTAssertFalse(tracker.isHolding)
    }
}
```

- [ ] **Step 2: Spustit a ověřit, že padají**

Run: `swift test --filter HoldTrackerTests`
Expected: FAIL, `cannot find 'HoldTracker' in scope`

- [ ] **Step 3: Implementace stavu stisku**

`Sources/NativeVoiceCore/Input/HoldTracker.swift`:
```swift
import Foundation

/// Turns a stream of `flagsChanged` flag words into press and release events.
///
/// The held state is derived from the device bit in each event, never from a
/// counter this type increments on its own. With a counter, one lost event is
/// enough to invert everything: a *release* is then read as a *press*, and a
/// recording starts with no key held and nothing to stop it.
public struct HoldTracker {
    public enum Change: Equatable { case pressed, released, unchanged }

    public var key: TriggerKey {
        didSet {
            // Switching keys mid-hold would otherwise leave the old one
            // latched down forever.
            if key != oldValue { holding = false }
        }
    }
    private var holding = false

    public init(key: TriggerKey) { self.key = key }

    public var isHolding: Bool { holding }

    public mutating func update(flags: UInt64) -> Change {
        let down = key.isHeld(flags: flags)
        guard down != holding else { return .unchanged }
        holding = down
        return down ? .pressed : .released
    }

    /// Clears the held state without an event. Used when something other than
    /// a key release stopped the recording — the length cap — so that the next
    /// real press is not swallowed as "no change".
    public mutating func forceRelease() { holding = false }
}
```

- [ ] **Step 4: Spustit testy**

Run: `swift test --filter HoldTrackerTests`
Expected: PASS, 6 testů

- [ ] **Step 5: Event tap**

`Sources/NativeVoice/Input/EventTap.swift`:
```swift
import AppKit
import NativeVoiceCore

/// Watches modifier keys system-wide.
///
/// The mask is `flagsChanged` and nothing else. **`keyDown` must never be
/// added.** A version that included it coincided with every keyboard shortcut
/// in the system breaking; the mechanism was never proven, but the difference
/// was reproducible and the narrow mask has never repeated it.
final class EventTap {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private let onChange: (UInt64) -> Void

    init(onChange: @escaping (UInt64) -> Void) {
        self.onChange = onChange
    }

    @discardableResult
    func start() -> Bool {
        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)

        // userInfo must carry self. Passing nil left refcon nil in the
        // callback, so the branch that re-enables a timed-out tap could never
        // run and the app went deaf without saying so.
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let me = Unmanaged<EventTap>.fromOpaque(refcon).takeUnretainedValue()
                me.handle(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: refcon
        ) else {
            log("event tap could not be created — Accessibility not granted yet")
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        log("event tap active — ready")
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            log("event tap re-enabled after \(type == .tapDisabledByTimeout ? "timeout" : "user input")")
            return
        }
        guard type == .flagsChanged else { return }
        onChange(event.flags.rawValue)
    }
}
```

- [ ] **Step 6: Nahrávání**

`Sources/NativeVoice/Audio/Recorder.swift`:
```swift
import AVFoundation
import NativeVoiceCore

/// Records audio and reports the input level.
///
/// The engine starts on key press, before the hold threshold, and writing
/// begins only once the threshold passes. Opening an audio device takes real
/// time — measured at over a second with an `ffmpeg` subprocess, which ate the
/// first word of every sentence. Starting early puts that cost outside the
/// recording.
///
/// Recording happens in-process for the same reason: a subprocess was both
/// slower to start and harder to reason about.
final class Recorder {
    private let engine = AVAudioEngine()
    private var file: AVAudioFile?
    private let lock = NSLock()
    private var running = false
    private var writing = false
    private var peak: Float = -200

    /// Normalized 0…1 level for the meter.
    var onLevel: ((Double) -> Void)?

    /// Loudest point since writing began, in dB. When a transcript comes back
    /// empty this is the only thing that tells silence on the input apart from
    /// speech the model did not recognize.
    var peakDecibels: Float { lock.lock(); defer { lock.unlock() }; return peak }

    private let floorDb: Float = -72
    private var ceilDb: Float = -38
    private let ceilFloor: Float = -50

    func warmUp() {
        guard !running else { return }
        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            log("audio input unavailable: \(format)")
            return
        }

        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            guard let self else { return }

            self.lock.lock()
            let target = self.writing ? self.file : nil
            try? target?.write(from: buffer)
            let isWriting = self.writing
            self.lock.unlock()

            guard let channel = buffer.floatChannelData?[0] else { return }
            let count = Int(buffer.frameLength)
            guard count > 0 else { return }
            var sum: Float = 0
            for i in 0..<count { sum += channel[i] * channel[i] }
            let rms = (sum / Float(count)).squareRoot()
            let db = 20 * log10(max(rms, 1e-7))

            if isWriting {
                self.lock.lock()
                if db > self.peak { self.peak = db }
                self.lock.unlock()
            }

            // The ceiling follows recent peaks so the meter stays lively on a
            // quiet microphone instead of sitting flat.
            if db > self.ceilDb { self.ceilDb = db }
            else { self.ceilDb = max(self.ceilFloor, self.ceilDb - 0.06) }
            let span = max(6, self.ceilDb - self.floorDb)
            let level = Double(max(0, min(1, (db - self.floorDb) / span)))
            DispatchQueue.main.async { self.onLevel?(level) }
        }

        do {
            engine.prepare()
            try engine.start()
            running = true
        } catch {
            input.removeTap(onBus: 0)
            log("audio engine failed to start: \(error.localizedDescription)")
        }
    }

    func startWriting(to url: URL) -> Bool {
        guard running else { return false }
        let format = engine.inputNode.inputFormat(forBus: 0)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        do {
            let file = try AVAudioFile(forWriting: url, settings: settings)
            lock.lock(); self.file = file; writing = true; peak = -200; lock.unlock()
            let device = AVCaptureDevice.default(for: .audio)?.localizedName ?? "unknown"
            log(String(format: "recording from %@ at %.0f Hz, %d ch",
                       device, format.sampleRate, format.channelCount))
            return true
        } catch {
            log("could not open the recording file: \(error.localizedDescription)")
            return false
        }
    }

    func stop() {
        lock.lock(); writing = false; file = nil; lock.unlock()
        guard running else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        running = false
    }
}
```

- [ ] **Step 7: Klient ElevenLabs**

`Sources/NativeVoice/Transcription/ElevenLabsClient.swift`:
```swift
import Foundation
import NativeVoiceCore

/// Sends audio to ElevenLabs Scribe.
///
/// All the logic worth auditing — what is sent, how a reply is read — lives in
/// `NativeVoiceCore` and is covered by tests. This type is the thin part: read
/// the file, make the call.
struct ElevenLabsClient: Transcriber {
    let secrets: SecretStore
    let session: URLSession

    init(secrets: SecretStore, session: URLSession = .shared) {
        self.secrets = secrets
        self.session = session
    }

    func transcribe(audio url: URL,
                    language: String,
                    keyterms: [String],
                    removeFillers: Bool) async -> TranscriptionResult {
        guard let key = secrets.apiKey() else { return .failure(.noAPIKey) }
        guard let data = try? Data(contentsOf: url) else {
            log("recording could not be read back from \(url.path)")
            return .failure(.badResponse)
        }

        let request = ElevenLabsRequest.build(audio: data,
                                              filename: url.lastPathComponent,
                                              language: language,
                                              keyterms: keyterms,
                                              removeFillers: removeFillers,
                                              apiKey: key)
        do {
            let (body, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            return ElevenLabsResponse.parse(data: body, httpStatus: status)
        } catch {
            log("request failed: \(error.localizedDescription)")
            return .failure(.unreachable)
        }
    }
}
```

- [ ] **Step 8: String Catalog**

Vytvořit `Sources/NativeVoice/Resources/Localizable.xcstrings` s prázdným katalogem; `swift build` ho doplní z `String(localized:)` v kódu.

**I tady se píše `bundle: .module`.** SwiftPM ukládá katalog do vnořeného `.bundle`, který `Scripts/build-app.sh` kopíruje do `Contents/Resources` — `Bundle.main` ho tam nenajde, `Bundle.module` ano.

```json
{
  "sourceLanguage" : "en",
  "strings" : { },
  "version" : "1.0"
}
```

Do `Package.swift` přidat k `executableTarget` zdroj:
```swift
resources: [.process("Resources/Localizable.xcstrings")]
```

- [ ] **Step 9: AppDelegate — celá smyčka**

`Sources/NativeVoice/App/AppDelegate.swift`:
```swift
import AppKit
import AVFoundation
import NativeVoiceCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private enum State { case idle, recording, transcribing }

    private var statusItem: NSStatusItem!
    private let recorder = Recorder()
    private let secrets = KeychainSecretStore()
    private lazy var transcriber: Transcriber = ElevenLabsClient(secrets: secrets)
    private let clipboardRestore = ClipboardRestore()

    private var tap: EventTap?
    private var hold = HoldTracker(key: .default)
    private var state: State = .idle { didSet { updateStatusIcon() } }

    /// A press shorter than this is a shortcut, not dictation. The tap does
    /// not see ordinary keys, so it cannot tell that ⌘C used the same key —
    /// the threshold is what keeps a quick shortcut from starting a recording.
    private let holdThreshold: TimeInterval = 0.4
    private var pendingStart: DispatchWorkItem?
    private var limitWork: DispatchWorkItem?
    private var audioURL: URL?
    private var startedAt = Date()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.shared.rotateIfNeeded()
        log("launched from \(Bundle.main.bundlePath)")
        log("accessibility trusted: \(AXIsProcessTrusted())")

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusIcon()
        statusItem.menu = buildMenu()

        requestMicrophone()

        let tap = EventTap { [weak self] flags in
            Task { @MainActor in self?.handle(flags: flags) }
        }
        self.tap = tap
        tap.start()
    }

    // MARK: - Status item

    private func updateStatusIcon() {
        // SF Symbols as template images, not text glyphs: they adapt to a
        // light or dark menu bar and to the highlight when the menu is open.
        let name: String
        switch state {
        case .idle:         name = "mic"
        case .recording:    name = "mic.fill"
        case .transcribing: name = "waveform"
        }
        let image = NSImage(systemSymbolName: name,
                            accessibilityDescription: String(localized: "NativeVoice", bundle: .module))
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        let hint = NSMenuItem(
            title: String(localized: "Hold \(hold.key.menuTitle) and speak", bundle: .module),
            action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: String(localized: "Quit NativeVoice", bundle: .module),
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        return menu
    }

    private func requestMicrophone() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        log("microphone authorization: \(status.rawValue)")
        if status == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                log("microphone access \(granted ? "granted" : "denied")")
            }
        }
    }

    // MARK: - Key handling

    private func handle(flags: UInt64) {
        switch hold.update(flags: flags) {
        case .unchanged: return
        case .pressed:   pressed()
        case .released:  released()
        }
    }

    private func pressed() {
        log("\(hold.key.rawValue) pressed")
        recorder.onLevel = { _ in }     // HUD arrives in plan 2
        recorder.warmUp()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.hold.isHolding, self.state == .idle else { return }
            self.startRecording()
        }
        pendingStart = work
        DispatchQueue.main.asyncAfter(deadline: .now() + holdThreshold, execute: work)
    }

    private func released() {
        log("\(hold.key.rawValue) released")
        pendingStart?.cancel(); pendingStart = nil
        limitWork?.cancel(); limitWork = nil
        guard state == .recording else {
            recorder.stop()             // short press, nothing was written
            return
        }
        stopAndTranscribe()
    }

    // MARK: - Recording

    private func startRecording() {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("nativevoice-\(UUID().uuidString).wav")
        guard recorder.startWriting(to: url) else {
            recorder.stop()
            log("could not open the audio input")
            return
        }
        audioURL = url
        startedAt = Date()
        state = .recording
        armLimit(RecordingLimit.default)
    }

    private func armLimit(_ limit: RecordingLimit) {
        limitWork?.cancel()
        guard let seconds = limit.seconds else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.state == .recording else { return }
            log("recording limit \(Int(seconds))s reached — stopping")
            // The cap covers a lost key-release event. Leaving the tracker
            // latched would make the next genuine press read as "no change"
            // and be dropped, so the user would say a whole sentence into
            // nothing.
            self.hold.forceRelease()
            self.pendingStart?.cancel(); self.pendingStart = nil
            self.stopAndTranscribe()
        }
        limitWork = work
        // Subtracting the elapsed time matters when the limit is changed
        // mid-recording: scheduling from now would extend the recording
        // instead of shortening it.
        let remaining = max(0, seconds - Date().timeIntervalSince(startedAt))
        DispatchQueue.main.asyncAfter(deadline: .now() + remaining, execute: work)
    }

    private func stopAndTranscribe() {
        limitWork?.cancel(); limitWork = nil
        guard let url = audioURL else { return }
        audioURL = nil
        let spoken = Date().timeIntervalSince(startedAt)
        recorder.stop()
        state = .transcribing

        let peak = recorder.peakDecibels
        let vocabulary = loadVocabulary()
        let language = Language.forSystem().code

        Task { [weak self] in
            defer { try? FileManager.default.removeItem(at: url) }
            guard let self else { return }

            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            guard ((attributes?[.size] as? Int) ?? 0) > 2000 else {
                log("nothing was recorded")
                await MainActor.run { self.state = .idle }
                return
            }

            let started = Date()
            let outcome = await self.transcriber.transcribe(
                audio: url, language: language,
                keyterms: vocabulary, removeFillers: false)
            log(String(format: "spoken %.1fs | peak %.0f dB | transcribe %.2fs",
                       spoken, peak, Date().timeIntervalSince(started)))

            await MainActor.run {
                self.state = .idle
                switch outcome {
                case .failure(let error):
                    log("error: \(error.userMessage)")
                case .text(let text) where text.isEmpty:
                    log(peak < -55 ? "empty transcript — the input was silent"
                                   : "empty transcript although there was sound")
                case .text(let text):
                    Paste.deliver(text, autoPaste: true, restore: self.clipboardRestore)
                }
            }
        }
    }

    private func loadVocabulary() -> [String] {
        let path = NSString(string: "~/.config/nativevoice/vocabulary.txt")
            .expandingTildeInPath
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            try? FileManager.default.createDirectory(
                atPath: (path as NSString).deletingLastPathComponent,
                withIntermediateDirectories: true)
            try? Vocabulary.template.write(toFile: path, atomically: true, encoding: .utf8)
            return []
        }
        return Vocabulary.terms(from: text)
    }
}
```

`Sources/NativeVoice/App/main.swift` se zkrátí na:
```swift
import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
```

- [ ] **Step 10: Spustit celou sadu testů**

Run: `swift test`
Expected: PASS, 72 testů (6 Log + 7 SecretStore + 8 Vocabulary + 16 ElevenLabs + 8 Language + 6 RecordingLimit + 10 TriggerKey + 5 ClipboardRestore + 6 HoldTracker — bez PlaceholderTests)

- [ ] **Step 11: Ruční ověření celé smyčky**

```bash
./Scripts/build-app.sh 0.1.0 2
open .build/app/NativeVoice.app
```

1. Povolit mikrofon, když se zeptá.
2. **Nastavení → Soukromí a zabezpečení → Zpřístupnění** přidat NativeVoice a zapnout. Ad-hoc podpis znamená, že se oprávnění po každé přestavbě odvolá — v logu to pozná podle `event tap could not be created`.
3. Ukončit a spustit znovu, aby se tap chytil.
4. Zadat klíč — ve v1 dočasně přes `security`, protože dialog přijde v plánu 2:
```bash
security add-generic-password -s com.trustbe.nativevoice -a elevenlabs-api-key -w
```
5. Otevřít TextEdit, podržet pravý Cmd přes vteřinu, něco říct, pustit.

Expected: text se objeví v TextEditu; v `~/Library/Logs/NativeVoice.log` je `pressed`, `recording from …`, `API received …s of audio`, `spoken … | peak … | transcribe …`.

6. Ověřit zachování schránky: zkopírovat `MARKER`, nadiktovat větu, počkat dvě vteřiny, vložit → musí se vložit `MARKER`.
7. Ověřit strop: v `armLimit` dočasně předat `.oneMinute`, přestavět, podržet klávesu přes minutu bez mluvení. V logu musí být `recording limit 60s reached`. Pak klávesu pustit, znovu podržet a nadiktovat větu — **musí se nahrát**; kdyby se zahodila, `forceRelease()` nefunguje. Vrátit zpět na `.default`.

Výsledky každého bodu zapsat do commitu.

- [ ] **Step 12: Commit**

```bash
git add -A
git commit -m "feat(app): wire the dictation loop end to end

Hold the trigger key, speak, release: the audio goes to Scribe and the
transcript lands under the cursor.

The hold state is derived from the device bit in each event, never from a
counter. With a counter one lost event inverts everything and a release reads
as a press.

The engine starts on key press and writing begins after the threshold, so the
cost of opening the audio device falls outside the recording. A subprocess
took over a second and ate the first word of every sentence.

Reaching the length cap force-releases the tracker. Without that the next
genuine press reads as 'no change' and is dropped — in exactly the failure the
cap exists to cover.

Verified by hand: dictation into TextEdit, clipboard preserved across a
dictation, and the cap stopping a recording with the next press still working."
```

---

## Co zůstává na další plány

Z kapitoly specu „Chyby, které se nesmí zopakovat" jsou v tomto plánu
vypořádané čtyři: pád buildu na `git describe` (skript verzi nehádá, bere ji
jako argument a ověřuje), formát `CFBundleVersion`, odečtení uběhlého času při
přeplánování stropu, a zrušitelná obnova schránky. Zbylé čtyři se týkají
položky po přihlášení a přestavby menu, tedy kódu, který vzniká až v plánu 2,
a jsou tam uvedené jmenovitě.

**Plán 2 — rozhraní a nastavení.** Panel s osciloskopem na `CGShieldingWindowLevel()`, chyby v panelu, okno nastavení otevírané ⌘, , historie, výběr jazyka a klávesy, dialog pro klíč s odkazy, `UserNotifications` místo zastaralého `NSUserNotification`, *Omezit pohyb* a *Omezit průhlednost*, popisky pro VoiceOver, velká písmena v menu podle konvence macOS.

Spolu s položkou „spustit po přihlášení" se tam musí vypořádat čtyři zbylé
nálezy: `SMAppService.mainApp.status` vrací pro nikdy neregistrovanou aplikaci
`.notFound` (ověřeno měřením), takže se stavy vyjmenovávají kladně; příznak
„už nastaveno" se zapisuje až po úspěšné registraci; heuristika „je to
upgrade" se opírá jen o předvolby, které zapisuje uživatel, nikdy o ty
zapsané jako vedlejší efekt; a obsah menu se obnovuje v
`NSMenuDelegate.menuNeedsUpdate`, ne výměnou celého menu po události — ta
zavře menu uživateli pod kurzorem.

**Plán 3 — distribuce a zveřejnění.** Ikona na mřížce 824/1024 px, podepisování Developer ID, notarizace přes API klíč, aktualizátor s ověřením requirementem a zálohou mimo dočasnou složku, README s doklady, `FUNDING.yml`, stránka na GitHub Pages, DNS záznam `nativevoice CNAME trustbe.github.io`, kontrolní seznam ke dni zveřejnění (ověřit, že odkazy z aplikace vedou kam mají) a vydání `1.0.0`.
