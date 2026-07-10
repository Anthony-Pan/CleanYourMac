# Privacy Scan v2 — whole-machine privacy scan (FINAL SPEC)

Repo: /Users/anthonypan/Developer/CleanYourMac/app (SwiftPM, tools 6.0, lang mode v5, macOS 14+).
Build: `cd app && swift build`. Test: `cd app && swift test`. XCTest (not swift-testing).

Today the Privacy module only scans a fixed table of 10 browsers + macOS Recent
Items. v2 adds three layers:

1. Generic Chromium/Electron app trace detection (cleanable) — every app under
   `~/Library/Application Support` that embeds Chromium, found by signature.
2. System-wide macOS traces (cleanable) — QuickLook thumbnails, window states,
   download provenance (QuarantineEventsV2), shell history, diagnostic reports.
3. Privacy audit (report-only findings) — TCC permissions, network exposure,
   firewall/FileVault/analytics/guest/AirDrop posture, credential hygiene,
   shell-history secrets heuristic. Findings are structurally un-deletable.

## Hard safety rules (inviolable)

- Scanning read-only; removal ONLY via `Cleaner` + `SafetyPolicy`, Trash only.
- `allowedRoots` declarative. Electron roots = signature-verified dirs read from
  the real disk (sanctioned Chromium/Firefox-profile precedent). NEVER from items.
- Exact-target locations (quarantine DB, shell history files, QuickLook cache
  dir) use NEW `SafetyPolicy.allowedExactTargets` — fixed list of exact
  canonical URLs; depth + protected-path checks still apply; even stricter than
  a root.
- `neverRemoveBasenames` denylist applies in ALL new scanners and in clear().
- clear() gains a structural check: items attributed to an electron source must
  have a basename in the fixed electron trace-name set (after sidecar
  normalisation) or be blocked `.protectedContent`.
- Audit findings carry NO deletable URL (no URL field routed anywhere).
- Opt-in (defaultOn=false): cookies, siteData, sessions (existing) + NEW
  shellHistory, windowState. Electron cookies/siteData also opt-in via same kinds.
- Existing safety tests keep passing; test sandboxes must never reach real
  machine paths (see injection rules below).

## Machine probe facts (verified on this Mac, macOS 27.0 beta 26A5378j)

- QuickLook cache actual path: `<DARWIN_USER_CACHE_DIR>/com.apple.quicklook.ThumbnailsAgent/com.apple.QuickLook.thumbnailcache`
  (TCC-protected; unreadable without FDA → yields no item, that's fine).
  Older macOS candidates to also probe: `<DARWIN_USER_CACHE_DIR>/com.apple.QuickLook.thumbnailcache`
  and `~/Library/Containers/com.apple.quicklook.ThumbnailsAgent/Data/Library/Caches/com.apple.QuickLook.thumbnailcache`.
  DARWIN_USER_CACHE_DIR via `confstr(_CS_DARWIN_USER_CACHE_DIR)`.
- `~/Library/Saved Application State` absent on macOS 27, present on ≤15 — scan
  it; absent ⇒ no group.
- `~/Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2` exists,
  SQLite, plus possible -wal/-shm sidecars.
- `~/Library/Logs/DiagnosticReports`: .ips/.diag files + `Retired/` subdir
  (64 MB here). Item per top-level file, plus `Retired` dir as ONE item.
- Shell traces here: `~/.zsh_history` (112 KB), `~/.zsh_sessions/`. Fixed list to
  scan: .zsh_history, .bash_history, .zsh_sessions (dir), .python_history,
  .node_repl_history, .lesshst.
- sharedfilelist on macOS 27 uses `.sfl4`; the per-app dir is now named
  `com.apple.LSSharedFileList.ApplicationRecentDocuments` (prefixed!). BUG FIX:
  systemRecentsItems() must match `name == "ApplicationRecentDocuments" ||
  name.hasPrefix("com.apple.LSSharedFileList.ApplicationRecentDocuments")`.
- TCC: user DB `~/Library/Application Support/com.apple.TCC/TCC.db` does NOT
  exist on macOS 27 (query it only when present — older macOS). System DB
  `/Library/Application Support/com.apple.TCC/TCC.db` readable WITH FDA.
  Schema: `access(service, client, client_type, auth_value, ...)`;
  auth_value 2=allowed, 3=limited. Interesting services: kTCCServiceCamera,
  kTCCServiceMicrophone, kTCCServiceScreenCapture, kTCCServiceSystemPolicyAllFiles,
  kTCCServiceAccessibility, kTCCServiceListenEvent, kTCCServicePostEvent.
- Firewall: `/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate`
  works without root → "Firewall is disabled. (State = 0)". The com.apple.alf
  defaults domain is GONE on macOS 15+ — do not use.
- Sharing detection: TCP connect probe to 127.0.0.1 ports 22/5900/445 (NWConnection,
  ~1 s timeout). launchctl print system/* unusable without root.
- `defaults read /Library/Application Support/CrashReporter/DiagnosticMessagesHistory.plist AutoSubmit` → works, 0/1.
- `defaults read /Library/Preferences/com.apple.loginwindow GuestEnabled` → works; key may be absent (treat absent as off).
- `defaults read com.apple.sharingd DiscoverableMode` → "Everyone"/"Contacts Only"/"Off"; key may be absent.
- `fdesetup status` works without root → "FileVault is On." / "Off.".
- Electron signature (STRICT, validated against 12 real apps + 3 false-positive
  natives): a dir matches iff it contains ≥1 of {"Code Cache","GPUCache",
  "Session Storage"} AND ≥1 of {"Local Storage","Cookies"(file),"IndexedDB",
  "Local State"(file)}. Check three tiers: top level, `Partitions/<p>/` (one
  level), `Default/`. Lone "Cache"/"IndexedDB"/"Cookies" is NOT sufficient.
- Never touch siblings: e.g. Claude claude_desktop_config.json, Cursor `User/`,
  obsidian obsidian.json, UnityHub projects-v1.json/encryptedTokens.json,
  LogiOptionsPlus macros.db. Only offer FIXED trace names (below).

## CleanCore changes

### PrivacyModels.swift (modify)

`PrivacyApp` drops `: String` raw value (Swift forbids raw values with payload
cases). Becomes:

```swift
public enum PrivacyApp: Sendable, Hashable, Identifiable {
    case safari, chrome, edge, brave, vivaldi, firefox
    case arc, opera, operaGX, chromium
    case systemRecents
    /// Auto-discovered Chromium-embedded app under ~/Library/Application Support.
    case electron(name: String, bundleID: String?)
    // System-wide subsystems:
    case quickLook, savedState, quarantine, shellHistory, diagnostics

    /// Stable string key — replaces rawValue. Known cases keep their OLD raw
    /// strings ("system-recents" etc.) so categoryIDs stay stable.
    public var key: String   // electron → "electron:<name>", new: "quicklook",
                             // "saved-state", "download-records", "shell-history", "diagnostics"
    public var id: String { key }
    public var displayName: String  // electron → name; quickLook "Thumbnail Cache";
        // savedState "App Window States"; quarantine "Download Records";
        // shellHistory "Terminal History"; diagnostics "Crash & Diagnostic Reports"
    public var symbol: String       // electron "app.dashed"; quickLook "photo.on.rectangle";
        // savedState "macwindow.on.rectangle"; quarantine "arrow.down.doc.fill";
        // shellHistory "terminal.fill"; diagnostics "stethoscope"
    public var bundleIDs: [String]  // electron → [bundleID].compactMap; system → []
    /// Known browser cases only (used by the browser scanner loop).
    public static let browsers: [PrivacyApp] = [.safari, .chrome, .edge, .brave,
        .vivaldi, .firefox, .arc, .opera, .operaGX, .chromium]
}
```
(CaseIterable is removed; `PrivacyGroup.id` uses `app.key`.)

New `PrivacyItemKind` cases (existing test `test_cookiesAndSessionsAreOptInByDefault`
has an exhaustive switch — update it mechanically):

| case | titleEN | titleCN | defaultOn | impactNote | symbol |
|---|---|---|---|---|---|
| .thumbnails | Thumbnail Cache | 缩略图缓存 | true | nil | photo.stack |
| .windowState | Window States | 窗口状态 | false | "Apps forget window layout" | macwindow |
| .downloadRecords | Where-from Records | 下载来源记录 | true | nil | arrow.down.circle.dotted |
| .shellHistory | Shell Command History | 终端命令历史 | false | "Clears your command history" | terminal |
| .crashReports | Crash Reports | 崩溃报告 | true | nil | doc.badge.gearshape |

detailEN (honest, one line):
- thumbnails: "Previews macOS generated for your documents and images. Rebuilt on demand."
- windowState: "Saved window layouts apps restore on relaunch. Apps will open fresh windows."
- downloadRecords: "The database recording where every downloaded file came from."
- shellHistory: "Commands you typed in Terminal. Clearing cannot be undone from the shell."
- crashReports: "Crash and diagnostic logs. They can contain file paths and app data."

### SafetyPolicy.swift (modify)

```swift
public let allowedExactTargets: [URL]   // canonicalized; default []
public init(allowedRoots: [URL], allowedExactTargets: [URL] = [],
            protectedPaths: [URL] = SafetyPolicy.defaultProtectedPaths,
            minimumDepth: Int = 4)
```
`validate()` order: tooShallow → protectedPath → isAllowedRootItself →
(exact-target match ⇒ nil / pass) → outsideAllowedRoots.

### ElectronTraceScanner.swift (NEW, CleanCore)

```swift
struct ElectronTraceScanner {   // internal; composed by PrivacyScanner
    let libraryURL: URL
    func groups() -> [PrivacyGroup]
    func detectedRoots() -> [URL]   // for allowedRoots(): the trace PARENT dirs
}
```
- Enumerate `libraryURL/Application Support/*` (one level, skipsHiddenFiles).
- SKIP the known browser vendor dirs (they belong to the browser scanner):
  "Google", "Microsoft Edge", "Microsoft Edge Beta/Dev/Canary", "BraveSoftware",
  "Vivaldi", "Arc", "Chromium", "Firefox", "com.operasoftware.Opera",
  "com.operasoftware.OperaGX". Also skip "com.apple.sharedfilelist" and any
  dir starting "com.apple.".
- Signature (strict, per probe): tier dirs = [appDir] + [appDir/Partitions/<p>
  for each subdir p] + [appDir/Default]. A tier matches iff (≥1 of "Code Cache",
  "GPUCache", "Session Storage") AND (≥1 of "Local Storage", "Cookies" file,
  "IndexedDB", "Local State" file at appDir top level OR in the tier).
  App matches iff any tier matches.
- For each MATCHED tier dir, offer ONLY these fixed entries (skip missing/empty;
  reuse denylist + add() semantics from PrivacyScanner):
  - `.caches`: "Cache", "Code Cache", "GPUCache", "DawnCache",
    "DawnGraphiteCache", "DawnWebGPUCache", "GrShaderCache", "ShaderCache",
    "GraphiteDawnCache", "blob_storage"
  - `.cookies` (+ SQLite sidecars): "Cookies", "Network/Cookies"
  - `.siteData`: "Local Storage", "Session Storage", "IndexedDB",
    "Service Worker", "SharedStorage", "Shared Dictionary"
  NO History, NO Sessions for electron apps (unknown app semantics — a
  full-Chromium app's Default/History may matter; we deliberately leave it).
- context badge: partition name for Partitions tiers; nil for top/Default.
- One PrivacyGroup per app: `.electron(name: dirName, bundleID: knownBundleIDs[dirName])`.
- `knownBundleIDs` static table (Running badge + icon): Slack→com.tinyspeck.slackmacgap,
  discord→com.hnc.Discord, Microsoft Teams→com.microsoft.teams2, Notion→notion.id,
  obsidian→md.obsidian, Figma→com.figma.Desktop, Signal→org.whispersystems.signal-desktop,
  Postman→com.postmanlabs.mac, Code→com.microsoft.VSCode, Code - Insiders→com.microsoft.VSCodeInsiders,
  Cursor→com.todesktop.230313mzl4w4u92, Claude→com.anthropic.claudefordesktop,
  UnityHub→com.unity3d.unityhub, WhatsApp→net.whatsapp.WhatsApp.
- `detectedRoots()` returns each matched TIER dir plus its `Network` subdir
  (cookies sidecar parent) — read from disk, independent of items.
- Static (internal, for clear() defense): `electronTraceBasenames: Set<String>`
  = all offered entry basenames above, lowercased (compare after the same
  normalizeBasename sidecar-stripping).

### SystemTraceScanner.swift (NEW, CleanCore)

```swift
struct SystemTraceScanner {
    let libraryURL: URL
    let homeURL: URL            // = libraryURL.deletingLastPathComponent() by default
    let darwinCacheURL: URL?    // nil in tests unless injected; REAL only in production
    func groups() -> [PrivacyGroup]
    func roots() -> [URL]           // DiagnosticReports dir, Saved Application State dir
    func exactTargets() -> [URL]    // quarantine DB(+sidecars), shell files, .zsh_sessions dir, QuickLook cache dir candidates
}
```
- quickLook (kind .thumbnails): candidates (whichever exists & non-empty ⇒ item):
  darwinCacheURL?/"com.apple.quicklook.ThumbnailsAgent/com.apple.QuickLook.thumbnailcache",
  darwinCacheURL?/"com.apple.QuickLook.thumbnailcache",
  libraryURL/"Containers/com.apple.quicklook.ThumbnailsAgent/Data/Library/Caches/com.apple.QuickLook.thumbnailcache".
  Each candidate is an exact target (whole dir trashed as one item).
- savedState (kind .windowState): items = subdirs of
  libraryURL/"Saved Application State" whose name ends ".savedState".
  Root = that parent dir.
- quarantine (kind .downloadRecords): exact files
  libraryURL/"Preferences/com.apple.LaunchServices.QuarantineEventsV2" + "-wal"/"-shm"/"-journal".
- shellHistory (kind .shellHistory): exact files under homeURL: .zsh_history,
  .bash_history, .python_history, .node_repl_history, .lesshst, plus
  .zsh_sessions as ONE dir item. ALL opt-in (kind defaultOn=false).
- diagnostics (kind .crashReports): items = files directly in
  libraryURL/"Logs/DiagnosticReports" (.ips/.crash/.diag/.panic/.spin/.hang etc.
  — any regular file) + "Retired" subdir as ONE item. Root = that dir.
- IMPORTANT: everything derives from libraryURL/homeURL/darwinCacheURL —
  no direct real-machine paths, so test sandboxes stay hermetic.

### PrivacyScanner.swift (modify)

- `init(libraryURL: URL = real ~/Library, homeURL: URL? = nil,
  darwinCacheURL: URL? = nil, disposer: FileDisposer = TrashDisposer())`.
  homeURL default = libraryURL.deletingLastPathComponent().
  darwinCacheURL default nil (hermetic). ADD
  `public static func production() -> PrivacyScanner` that passes the REAL
  confstr(_CS_DARWIN_USER_CACHE_DIR) URL. PrivacyViewModel switches to it.
- `scan()` = browser groups (PrivacyApp.browsers loop, unchanged logic)
  + systemRecentsItems() + ElectronTraceScanner.groups()
  + SystemTraceScanner.groups(); filter non-empty; sort by totalBytes desc.
- systemRecentsItems(): apply the sfl4 ApplicationRecentDocuments prefix fix.
- `clear(_:dryRun:)` extra defense-in-depth BEFORE the Cleaner gate:
  for items whose `app` is `.electron`, require
  normalizeBasename(basename) ∈ ElectronTraceScanner.electronTraceBasenames,
  else block `.protectedContent`. (Denylist check stays for everything.)
- `allowedRoots()` adds: SystemTraceScanner.roots() + ElectronTraceScanner
  .detectedRoots(). Policy construction becomes
  `SafetyPolicy(allowedRoots: allowedRoots(), allowedExactTargets: exactTargets())`
  where exactTargets() = SystemTraceScanner.exactTargets().
- categoryID: `"privacy-\(item.app.key)"`.

### PrivacyAuditModels.swift (NEW) + PrivacyAuditor.swift (NEW)

```swift
public struct PrivacyFinding: Identifiable, Sendable, Hashable {
    public enum Severity: Int, Sendable, Comparable { case info = 0, advisory = 1, warning = 2 }
    public enum Category: String, Sendable { case permissions, networkExposure,
        systemSettings, credentialHygiene, historyHygiene }
    public let id: String
    public let severity: Severity
    public let category: Category
    public let title: String            // EN, e.g. "Firewall is turned off"
    public let detail: String           // what we observed, honest and specific
    public let recommendation: String   // one sentence
    public let settingsURLString: String?  // x-apple.systempreferences deep link
    public let apps: [String]           // bundle ids (permissions findings)
}
// NO file URL anywhere — findings can never route into the Cleaner.

public protocol CommandRunning: Sendable {
    func run(_ launchPath: String, _ arguments: [String]) -> String?  // nil on failure; 5 s timeout
}
public protocol PortProbing: Sendable {
    func isOpen(_ port: UInt16) async -> Bool   // 127.0.0.1, ~1 s timeout
}

public struct PrivacyAuditor: Sendable {
    // init(homeURL:libraryURL:runner:prober:userTCCPath:systemTCCPath:) — all injectable
    public func audit() async -> [PrivacyFinding]   // severity desc, stable order; every check isolated (failure ⇒ skip)
}
```
Checks:
1. TCC permissions — SQLite3 C API (`import SQLite3`), sqlite3_open_v2
   READONLY on user DB (if file exists) and system DB (if readable).
   `SELECT service, client, client_type, auth_value FROM access WHERE auth_value IN (2,3)`.
   client_type 0 ⇒ bundle id. One finding per interesting service present:
   Camera (warning if >3 apps else info… keep simple: advisory), Microphone
   (advisory), ScreenCapture (warning), SystemPolicyAllFiles (warning),
   Accessibility (warning), ListenEvent (warning), PostEvent (advisory).
   Title e.g. "3 apps can record your screen", detail lists app bundle ids,
   settings deep link per service (Privacy_ScreenCapture etc.).
   If NEITHER db readable ⇒ one info finding "Grant Full Disk Access to audit
   app permissions" (link Privacy_AllFiles).
2. Ports: 22 open ⇒ warning "Remote Login (SSH) is reachable"; 5900 ⇒ warning
   "Screen Sharing is reachable"; 445 ⇒ advisory "File Sharing (SMB) is on".
   Link com.apple.Sharing-Settings.extension.
3. Firewall: socketfilterfw --getglobalstate contains "State = 0" ⇒ warning.
   Parse helper `static func firewallDisabled(from output: String) -> Bool?`.
4. FileVault: `fdesetup status` contains "Off" ⇒ warning.
5. Analytics: AutoSubmit == 1 ⇒ info "Mac analytics sharing is on".
6. Guest: GuestEnabled == 1 ⇒ advisory.
7. AirDrop: DiscoverableMode == "Everyone" ⇒ advisory "AirDrop is discoverable by everyone".
8. Credential hygiene (FileManager only, NEVER read contents): for regular files
   in homeURL/.ssh not ending .pub and not config/known_hosts*/authorized_keys:
   posixPermissions & 0o077 != 0 ⇒ warning "SSH private key readable by others".
   homeURL/.aws/credentials and homeURL/.netrc: perms & 0o077 != 0 ⇒ warning.
9. History secrets heuristic: read LAST 256 KB of .zsh_history/.bash_history
   (lossy UTF-8), regex `(?i)(password|passwd|token|secret|api[_-]?key)\s*[=:]\s*\S`
   ⇒ advisory "Your shell history may contain secrets" (count matches; never
   include matched text in the finding).
Pure helpers exposed `internal static` for tests. Every Process call goes
through CommandRunning (real impl: Process + 5 s timeout, absolute launch paths
/usr/libexec/ApplicationFirewall/socketfilterfw, /usr/bin/fdesetup,
/usr/bin/defaults). Port probe real impl: Network.framework NWConnection.

## CleanUI changes

### PrivacyViewModel.swift
- `scanner = PrivacyScanner.production()`.
- Add `private(set) var findings: [PrivacyFinding] = []`.
- scan(): run trace scan and `PrivacyAuditor().audit()` concurrently
  (async let / two detached tasks), populate both. Findings sorted severity desc.
- Add `func openSettings(_ finding: PrivacyFinding)` using NSWorkspace.
- Mock init gains `mockFindings: [PrivacyFinding] = []`.

### PrivacyView.swift
- BrowserIcon NSCache key: `app.key as NSString` (rawValue is gone).
- Results layout: below the description, a "POTENTIAL ISSUES" section (slab
  header per DESIGN.md: 9.5 pt bold white-0.32 tracking 1.3 uppercase) —
  one glass card listing findings: severity chip via TagBadge/StatusPill
  (warning→PillTone.warn, advisory→.blue, info→neutral white-0.10), title
  13.5 semibold white, detail 11 pt Palette.tiny, trailing
  CompactCapsuleButton("Open Settings") when settingsURLString != nil.
  NO checkboxes anywhere in this section. Empty findings ⇒ a single quiet row
  "No privacy issues detected" with a good-tone chip.
- Then the existing trace group cards (now includes electron + system groups).
- Copy updates (keep safety copy semantics): idle sub-line and results
  description now say "…left behind by your browsers, apps and macOS."
- Electron groups with a mapped bundle id show the real app icon via existing
  BrowserIcon path; unmapped fall back to `app.dashed` symbol tile.
- Scanning phase line: "Scanning browsers, apps and system traces…".

### Design constraints (DESIGN.md binding)
Glass cards white 0.07 fill / 0.10 border, no materials; Aurora privacy variant
unchanged; safety copy inviolable; never render fake data.

## Tests (Tests/CleanCoreTests)

- Update PrivacyScannerTests exhaustive-kind switch mechanically; everything
  else must pass UNCHANGED.
- ElectronTraceScannerTests (new): detection via signature; Cache-only native
  dir NOT detected (BambuStudio-style fixture); `User`/config/db siblings never
  offered; Login Data inside electron dir never offered and blocked in clear();
  Partitions tier + context badge; Default tier for full-Chromium fixture WITHOUT
  offering History; known-browser dirs (Google/…) skipped; com.apple.* skipped;
  items validate against allowedRoots; crafted electron item with non-trace
  basename blocked .protectedContent; crafted item outside detected roots
  blocked .outsideAllowedRoots.
- SystemTraceScannerTests (new): each subsystem found + attributed + kind;
  quarantine sidecars travel together; shellHistory defaultOn == false;
  windowState defaultOn == false; savedState only *.savedState subdirs;
  diagnostics Retired is one item; clear-through-gate removes files; exact
  targets validate; sibling file NEXT TO an exact target is refused
  (.outsideAllowedRoots) — e.g. ~/.zshrc must never pass while ~/.zsh_history does;
  sfl4 prefixed ApplicationRecentDocuments dir detected (regression for the fix).
- SafetyPolicyTests (extend): exact target passes; non-listed sibling fails;
  exact target still subject to protectedPaths and minimumDepth; exact-target
  dir passes while its children do NOT via exact-match (children fail unless
  under a root).
- PrivacyAuditorTests (new): firewall parse (enabled/disabled/garbage→nil);
  history regex (hits/misses, no false positive on "keyboard"); ssh permission
  logic via temp files with modes 600 vs 644; findings carry no deletable URL
  (compile-time by design — assert stable ids & severity ordering instead);
  TCC row→finding mapping with a fixture sqlite db built in the test via
  sqlite3 CLI or SQLite3 C API; port/command checks via mock CommandRunning /
  PortProbing; auditor with all-mocks produces expected findings and isolates
  failures (runner returning nil ⇒ check skipped, no crash).
- Test hermeticity rule: never construct PrivacyScanner/SystemTraceScanner with
  real machine paths; RecordingDisposer actually deletes files.

## Verification
`swift build` + `swift test` green from app/. Then snapshot render (snapshot
executable) of privacy screens to eyeball the Aurora layout.
