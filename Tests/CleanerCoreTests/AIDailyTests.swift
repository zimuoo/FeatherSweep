import XCTest
@testable import CleanerCore

final class AIDailyTests: XCTestCase {
    let fm = FileManager.default
    var root: URL!
    var home: URL!
    var apps: URL!
    var engine: CleaningEngine!
    let day: TimeInterval = 86400
    let uuidA = "11111111-1111-4111-8111-111111111111"
    let uuidB = "22222222-2222-4222-8222-222222222222"
    override func setUpWithError() throws {
        root = URL(fileURLWithPath:"/private/tmp/FeatherSweepAIDaily-\(UUID().uuidString)")
        home = root.appendingPathComponent("home"); apps = root.appendingPathComponent("Applications")
        try fm.createDirectory(at:home,withIntermediateDirectories:true)
        try fm.createDirectory(at:apps,withIntermediateDirectories:true)
        engine = CleaningEngine(configuration:.init(home:home,temporaryRoots:[],userTemporaryRoot:root.appendingPathComponent("T"),checkOpenFiles:false,applicationsRoot:apps))
    }
    override func tearDownWithError() throws { try fm.removeItem(at:root) }
    @discardableResult func write(_ path:String,_ value:String="cache") throws -> URL {
        let p=home.appendingPathComponent(path);try fm.createDirectory(at:p.deletingLastPathComponent(),withIntermediateDirectories:true)
        try Data(value.utf8).write(to:p);return p
    }
    func aged(_ p:URL,_ days:Double) throws { try fm.setAttributes([.modificationDate:Date(timeIntervalSinceNow: -days*day)],ofItemAtPath:p.path) }
    @discardableResult func cache(_ alias:String,_ layout:String="Cache") throws -> URL {
        let p=try write("Library/Application Support/\(alias)/\(layout)/entry")
        return p.deletingLastPathComponent()
    }
    func installed(_ app:String,_ values:[String:String]) throws {
        let p=apps.appendingPathComponent(app+".app/Contents/Info.plist")
        try fm.createDirectory(at:p.deletingLastPathComponent(),withIntermediateDirectories:true)
        try PropertyListSerialization.data(fromPropertyList:values,format:.xml,options:0).write(to:p)
    }
    func forge(_ url:URL,kind:String) throws -> CleanupCandidate {
        let k=try XCTUnwrap(CleanupKind(rawValue:kind)), s=try SafeFS.snapshot(url,collectEntries:true)
        return CleanupCandidate(path:url.path,category:.cursor,kind:k,reason:"forged",identity:s.identity,metadataFingerprint:s.fingerprint)
    }
    func testMainstreamAliasesExposeOnlyRebuildableCacheSubpaths() throws {
        let aliases=["Claude","Codex","ChatGPT","Cursor","Trae","Trae CN","Windsurf","Gemini","Cherry Studio","CherryStudio","Ollama","LM Studio","Doubao","豆包","Qianwen","Qwen","千问","通义"]
        var expected=Set<String>(),protected:[URL]=[]
        for alias in aliases {
            expected.insert(try cache(alias).path)
            for path in ["Cookies","Login Data","IndexedDB/db","Local Storage/db","Session Storage/db","Service Worker/data","CachedExtensionVSIXs/plugin","CachedData/unknown","settings.json","models/weights","downloads/file"] {
                protected.append(try write("Library/Application Support/\(alias)/\(path)","keep"))
            }
        }
        protected += [try write(".codex/auth.json"),try write(".codex/config.toml"),try write(".codex/worktrees/project/source.swift"),try write(".codex/artifact_sessions/data"),try write(".claude/settings.json"),try write(".claude/projects/chat.jsonl"),try write(".ollama/models/model"),try write(".lmstudio/models/model")]
        let report=try engine.scan()
        XCTAssertEqual(Set(report.candidates.map(\.path)),expected,report.warnings.joined(separator:"\n"))
        XCTAssertEqual(CleanupCategory.cursor.title,"AI 缓存与旧快照")
        _=try engine.clean(report)
        for p in protected { XCTAssertTrue(fm.fileExists(atPath:p.path),p.path) }
    }
    func testCacheProfilesAndPartitionsUseExactGrammar() throws {
        let valid=["Code Cache","Default/GPUCache","Profile 2/DawnGraphiteCache","Partitions/webview/Cache","Default/Partitions/persist-chat/ShaderCache"]
        let expected=try Set(valid.map{try cache("Codex",$0).path})
        for layout in ["CacheData","Profile bad/Cache","Nested/Profile 2/Cache","Partitions/a/b/Cache","Service Worker/Cache","Default/IndexedDB"] { _=try cache("Codex",layout) }
        XCTAssertEqual(Set(try engine.scan().candidates.map(\.path)),expected)
    }
    func testInstalledDoubaoAndQianwenDiscoverSafeAliasesAndNativeCache() throws {
        try installed("Doubao",["CFBundleIdentifier":"com.example.doubao","CFBundleName":"豆包桌面","CFBundleExecutable":"DoubaoDesktop"])
        try installed("千问",["CFBundleIdentifier":"cn.example.qianwen","CFBundleDisplayName":"Qianwen Desktop","CFBundleName":"千问桌面"])
        let a=try cache("豆包桌面"),b=try cache("Qianwen Desktop")
        let c=try write("Library/Caches/com.example.doubao/fsCachedData/entry").deletingLastPathComponent()
        let d=try write("Library/Caches/cn.example.qianwen/fsCachedData/entry").deletingLastPathComponent()
        _=try write("Library/Caches/com.example.doubao/Cache.db","keep")
        XCTAssertEqual(Set(try engine.scan().candidates.map(\.path)),Set([a.path,b.path,c.path,d.path]))
    }
    func testUnrecognizedAppAndUnsafeMetadataCannotExpandAllowlist() throws {
        try installed("Unrelated",["CFBundleIdentifier":"com.example.other","CFBundleName":"Claude-ish"])
        try installed("Doubao",["CFBundleIdentifier":"com.apple.Safari","CFBundleName":"../important","CFBundleExecutable":"bad/name","CFBundleDisplayName":".."])
        _=try cache("Claude-ish");_=try write("Library/Caches/com.apple.Safari/fsCachedData/entry")
        XCTAssertTrue(try engine.scan().candidates.isEmpty)
    }
    func testKnownNativeBundleCachesAndCodexJSONOnly() throws {
        let native=try write("Library/Caches/com.openai.codex/fsCachedData/file").deletingLastPathComponent()
        let dirs=["codex_app_directory","codex_apps_server_info","codex_apps_tools","remote_plugin_catalog","bundled_plugin_exclusions"]
        var expected=Set([native.path])
        for (index,name) in dirs.enumerated() {
            let length=[40,40,40,16,64][index]
            expected.insert(try write(".codex/cache/\(name)/"+String(repeating:"a",count:length)+".json","{}").path)
            _=try write(".codex/cache/\(name)/settings.json","keep")
            _=try write(".codex/cache/\(name)/nested/"+String(repeating:"a",count:length)+".json","keep")
        }
        let changelog=try write(".claude/cache/changelog.md");expected.insert(changelog.path)
        _=try write(".codex/cache/other/"+String(repeating:"a",count:40)+".json")
        _=try write("Library/Caches/com.openai.codex/Cache.db","keep")
        XCTAssertEqual(Set(try engine.scan().candidates.map(\.path)),expected)
    }
    func history(_ id:String,rootAge:Double,childAge:Double) throws -> URL {
        let child=try write(".claude/file-history/\(id)/source@v1","old source")
        try aged(child,childAge);let group=child.deletingLastPathComponent();try aged(group,rootAge);return group
    }
    func testClaudeHistoryRequiresOldDescendantsAndRetainsNewestTree() throws {
        let old=try history(uuidA,rootAge:100,childAge:90)
        let newest=try history(uuidB,rootAge:120,childAge:2)
        let report=try engine.scan()
        XCTAssertEqual(Set(report.candidates.map(\.path)),Set([old.path]))
        XCTAssertTrue(report.retainedBackups.contains(newest.path))
        _=try engine.clean(report)
        XCTAssertFalse(fm.fileExists(atPath:old.path));XCTAssertTrue(fm.fileExists(atPath:newest.path))
    }
    func testClaudeHistorySortsByNewestDescendantRatherThanRoot() throws {
        let newest=try history(uuidA,rootAge:100,childAge:35)
        let old=try history(uuidB,rootAge:50,childAge:40)
        let report=try engine.scan()
        XCTAssertEqual(Set(report.candidates.map(\.path)),Set([old.path]));XCTAssertTrue(report.retainedBackups.contains(newest.path))
    }
    func testFreshRootAndUnknownHistoryNamesArePreserved() throws {
        _=try history(uuidA,rootAge:1,childAge:80)
        _=try history(uuidB,rootAge:100,childAge:90)
        _=try history("my-project",rootAge:100,childAge:100)
        let report=try engine.scan();XCTAssertFalse(report.candidates.contains{$0.path.hasSuffix("my-project") || $0.path.hasSuffix(uuidA)})
    }
    func testClaudeShellRetainsOneLatestAndRejectsUnknownScripts() throws {
        let old=try write(".claude/shell-snapshots/snapshot-zsh-1760000000000-ab12.sh");try aged(old,20)
        let latest=try write(".claude/shell-snapshots/snapshot-zsh-1760000000001-cd34.sh");try aged(latest,10)
        _=try write(".claude/shell-snapshots/startup.sh")
        let report=try engine.scan();XCTAssertEqual(Set(report.candidates.map(\.path)),Set([old.path]));XCTAssertTrue(report.retainedBackups.contains(latest.path))
    }
    func testCodexShellRetainsLatestPerSessionAndFreshSnapshots() throws {
        let old=try write(".codex/shell_snapshots/\(uuidA).a.sh");try aged(old,30)
        let latest=try write(".codex/shell_snapshots/\(uuidA).b.sh");try aged(latest,20)
        let other=try write(".codex/shell_snapshots/\(uuidB).ps1");try aged(other,30)
        let fresh=try write(".codex/shell_snapshots/\(uuidA).c.sh");try aged(fresh,1)
        _=try write(".codex/shell_snapshots/unknown.sh")
        let report=try engine.scan();XCTAssertEqual(Set(report.candidates.map(\.path)),Set([old.path,latest.path]));XCTAssertTrue(report.retainedBackups.contains(fresh.path));XCTAssertTrue(report.retainedBackups.contains(other.path))
    }
    func testSnapshotThatBecomesLatestIsProtectedAtCleanup() throws {
        let old=try write(".codex/shell_snapshots/\(uuidA).a.sh");try aged(old,30)
        let latest=try write(".codex/shell_snapshots/\(uuidA).b.sh");try aged(latest,20)
        let report=try engine.scan();XCTAssertEqual(report.candidates.count,1)
        try fm.removeItem(at:latest)
        let result=try engine.clean(report);XCTAssertEqual(result.removedCount,0);XCTAssertTrue(fm.fileExists(atPath:old.path))
    }
    func testHistoryRetainedGroupRemovalPreventsDeletion() throws {
        let old=try history(uuidA,rootAge:100,childAge:90)
        let latest=try history(uuidB,rootAge:80,childAge:70)
        let report=try engine.scan();XCTAssertEqual(report.candidates.count,1)
        try fm.removeItem(at:latest)
        let result=try engine.clean(report);XCTAssertEqual(result.removedCount,0);XCTAssertTrue(fm.fileExists(atPath:old.path))
    }
    func testDailyBrowserCachesKeepCredentialsAndServiceWorkers() throws {
        var expected=Set<String>(),protected:[URL]=[]
        for alias in ["Google/Chrome","Microsoft Edge","BraveSoftware/Brave-Browser"] {
            for profile in ["Default","Profile 3"] {
                expected.insert(try cache(alias,profile+"/GPUCache").path)
                expected.insert(try write("Library/Caches/\(alias)/\(profile)/Cache/Cache_Data/entry").deletingLastPathComponent().path)
                for name in ["Cookies","Login Data","Service Worker/store","IndexedDB/data"] { protected.append(try write("Library/Application Support/\(alias)/\(profile)/\(name)","keep")) }
            }
        }
        let firefox=try write("Library/Caches/Firefox/Profiles/abcd.default-release/cache2/entries/file").deletingLastPathComponent().deletingLastPathComponent();expected.insert(firefox.path)
        let report=try engine.scan();XCTAssertEqual(Set(report.candidates.map(\.path)),expected)
        XCTAssertTrue(report.candidates.allSatisfy{$0.category.rawValue == "daily"})
        _=try engine.clean(report);for p in protected { XCTAssertTrue(fm.fileExists(atPath:p.path)) }
    }
    func testDailySystemCachesAndOnlyOldDirectDiagnosticReports() throws {
        var expected=Set<String>()
        for dir in ["Library/Caches/com.apple.QuickLook.thumbnailcache","Library/Caches/com.apple.helpd/fsCachedData","Library/Caches/com.apple.helpd/Generated"] { expected.insert(try write(dir+"/data").deletingLastPathComponent().path) }
        for ext in ["ips","crash","diag","hang","spin"] { let p=try write("Library/Logs/DiagnosticReports/old."+ext);try aged(p,10);expected.insert(p.path) }
        for p in ["Library/Logs/DiagnosticReports/fresh.ips","Library/Logs/DiagnosticReports/old.log","Library/Logs/DiagnosticReports/nested/old.ips","Library/Caches/com.apple.helpd/Cache.db","Library/Caches/com.apple.helpd/HSTS.plist","Downloads/file",".Trash/file"] { _=try write(p) }
        let report=try engine.scan();XCTAssertEqual(Set(report.candidates.map(\.path)),expected)
    }
    func testFreshDiagnosticsForgedCandidatesAndMutatedCacheAreRejected() throws {
        let cache=try self.cache("Claude");var report=try engine.scan();XCTAssertEqual(report.candidates.count,1)
        _=try write("Library/Application Support/Claude/Cache/new")
        let fresh=try write("Library/Logs/DiagnosticReports/fresh.ips")
        let cookie=try write("Library/Application Support/Claude/Cookies")
        report.candidates += [try forge(fresh,kind:"diagnosticReport"),try forge(cookie,kind:"aiCache")]
        let result=try engine.clean(report);XCTAssertEqual(result.removedCount,0)
        for p in [cache,fresh,cookie] { XCTAssertTrue(fm.fileExists(atPath:p.path)) }
    }
    func testSymlinksAndUnknownLayoutsAreExcluded() throws {
        let outside=try write("important/source.swift","keep")
        let cache=try self.cache("Claude")
        try fm.createSymbolicLink(at:cache.appendingPathComponent("link"),withDestinationURL:outside)
        _=try self.cache("UnknownAI")
        _=try write("Library/Application Support/Google/Chrome/Profile unknown/Cache/entry")
        XCTAssertTrue(try engine.scan().candidates.isEmpty)
    }
    func testKindAndPathAwareOccupancyUsesExactExecutablesAndAppPaths() throws {
        let ai=try XCTUnwrap(CleanupKind(rawValue:"aiCache"))
        let history=try XCTUnwrap(CleanupKind(rawValue:"claudeFileHistory"))
        let codex=try XCTUnwrap(CleanupKind(rawValue:"codexShellSnapshot"))
        let browser=try XCTUnwrap(CleanupKind(rawValue:"browserCache"))
        XCTAssertTrue(OpenFileState(commands:["/usr/local/bin/claude"]).busy(history,home.appendingPathComponent(".claude/file-history/\(uuidA)").path))
        XCTAssertTrue(OpenFileState(commands:["/Applications/ChatGPT.app/Contents/MacOS/ChatGPT"]).busy(codex,home.appendingPathComponent(".codex/shell_snapshots/\(uuidA).sh").path))
        XCTAssertTrue(OpenFileState(commands:["/Applications/Gemini.app/Contents/MacOS/Gemini"]).busy(ai,home.appendingPathComponent("Library/Application Support/Gemini/GPUCache").path))
        XCTAssertTrue(OpenFileState(commands:["/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"]).busy(browser,home.appendingPathComponent("Library/Caches/Google/Chrome/Default/Cache/Cache_Data").path))
        XCTAssertFalse(OpenFileState(commands:["/project/codex-example/server","/project/claude-project/python"]).busy(history,home.appendingPathComponent(".claude/file-history/\(uuidA)").path))
        XCTAssertFalse(OpenFileState(commands:["/project/notcodex"]).busy(codex,home.appendingPathComponent(".codex/shell_snapshots/\(uuidA).sh").path))
    }
    func testActiveDynamicInstalledAppSkipsItsCache() throws {
        try installed("Doubao",["CFBundleIdentifier":"com.example.dynamic","CFBundleName":"DynamicDoubao"])
        let p=try cache("DynamicDoubao")
        var rules=CleanupRules(config:engine.configuration,openFiles:OpenFileState(commands:["/Applications/Doubao.app/Contents/MacOS/Runtime"]))
        let state=try XCTUnwrap(CleanupKind(rawValue:"aiCache"))
        rules.add(p,kind:state,category:.cursor,reason:"test")
        XCTAssertTrue(rules.candidates.isEmpty);XCTAssertFalse(rules.warnings.isEmpty)
    }
    func testSelectionPreservesMetadataAndOnlyRemovesChosenItems() throws {
        let a=try cache("Claude"),b=try cache("Codex")
        var report=try engine.scan()
        report.warnings=["fixture warning"];report.retainedBackups=["fixture retained"];report.availableBytes=1234
        let selected=report.selecting([a.path,"unknown-id"])
        XCTAssertEqual(selected.candidates.map(\.path),[a.path])
        XCTAssertEqual(selected.scannedAt,report.scannedAt);XCTAssertEqual(selected.warnings,report.warnings)
        XCTAssertEqual(selected.retainedBackups,report.retainedBackups);XCTAssertEqual(selected.availableBytes,1234)
        XCTAssertTrue(report.selecting(["unknown-id"]).candidates.isEmpty)
        XCTAssertTrue(report.selecting([]).candidates.isEmpty)
        let result=try engine.clean(selected);XCTAssertEqual(result.removedCount,1)
        XCTAssertFalse(fm.fileExists(atPath:a.path));XCTAssertTrue(fm.fileExists(atPath:b.path))
    }
    func testEveryKindExplainsPracticalImpact() throws {
        let values=["goCache","rustCache","cursorSnapshots","cursorSearchIndex","stagingCopy","duplicatePackage","signingClone","obsoleteUpdate","staticWebEntry","blenderBackup","aiCache","aiMetadataCache","claudeFileHistory","claudeShellSnapshot","codexShellSnapshot","browserCache","quickLookCache","helpCache","diagnosticReport"]
        for value in values {
            let kind=try XCTUnwrap(CleanupKind(rawValue:value))
            let c=CleanupCandidate(path:"/fixture",category:.cursor,kind:kind,reason:"")
            XCTAssertFalse(c.impactTitle.isEmpty);XCTAssertTrue(c.impactDetail.count > 15,value)
        }
        XCTAssertTrue(CleanupCandidate(path:"/fixture",category:.cursor,kind:.claudeFileHistory,reason:"").impactDetail.contains("回退"))
        XCTAssertTrue(CleanupCandidate(path:"/fixture",category:.temporary,kind:.duplicatePackage,reason:"").impactDetail.contains("正式安装包保留"))
    }

    func testMixedCaseAppleIdentifierCannotGrantNativeCacheAccess() throws {
        try installed("Doubao",["CFBundleIdentifier":"Com.Apple.Safari"])
        _=try write("Library/Caches/Com.Apple.Safari/fsCachedData/file")
        XCTAssertTrue(try engine.scan().candidates.isEmpty)
    }
    func testNativeVersionedClaudeCLIAndUnidentifiedJSRuntimeProtectSnapshots() throws {
        let history=try self.history(uuidA,rootAge:100,childAge:90)
        _=try self.history(uuidB,rootAge:80,childAge:70)
        let native=home.appendingPathComponent(".local/share/claude/versions/2.1.9").path
        var rules=CleanupRules(config:engine.configuration,openFiles:OpenFileState(commands:[native]))
        rules.add(history,kind:.claudeFileHistory,category:.cursor,reason:"test")
        XCTAssertTrue(rules.candidates.isEmpty)
        let codex=try write(".codex/shell_snapshots/\(uuidA).a.sh");try aged(codex,20)
        for command in ["/opt/homebrew/bin/node","/opt/homebrew/bin/bun"] {
            XCTAssertTrue(OpenFileState(commands:[command]).busy(.codexShellSnapshot,codex.path))
            XCTAssertTrue(OpenFileState(commands:[command]).busy(.claudeFileHistory,history.path))
            var runtimeRules=CleanupRules(config:engine.configuration,openFiles:OpenFileState(commands:[command]))
            runtimeRules.add(codex,kind:.codexShellSnapshot,category:.cursor,reason:"test")
            XCTAssertTrue(runtimeRules.warnings.first?.contains("Node / Bun") == true)
        }
        let unrelated=root.appendingPathComponent("project/.local/share/claude/versions/2.1.9").path
        let idle=CleanupRules(config:engine.configuration,openFiles:OpenFileState(commands:[unrelated]))
        XCTAssertFalse(idle.busy(.claudeFileHistory,history.path))
    }
    func testAllProductAppOwnersProtectTheirCachesWithoutOpenHandles() throws {
        for product in AITool.known {
            let alias=try XCTUnwrap(product.aliases.sorted().first)
            let app=try XCTUnwrap(product.appNames.sorted().first)
            let p=try cache(alias,"GPUCache")
            let state=OpenFileState(commands:["/Applications/\(app)/Contents/MacOS/Runtime"])
            let rules=CleanupRules(config:engine.configuration,openFiles:state)
            XCTAssertTrue(rules.busy(.aiCache,p.path),alias)
        }
        let p=try write(".codex/cache/remote_plugin_catalog/"+String(repeating:"a",count:16)+".json")
        XCTAssertTrue(OpenFileState(commands:["/Applications/ChatGPT.app/Contents/MacOS/ChatGPT"]).busy(.aiMetadataCache,p.path))
        for (kind,command,path) in [(CleanupKind.quickLookCache,"/System/Library/Frameworks/QuickLook.framework/qlmanage","Library/Caches/com.apple.QuickLook.thumbnailcache"),(.helpCache,"/System/Library/PrivateFrameworks/HelpData.framework/helpd","Library/Caches/com.apple.helpd/Generated")] {
            XCTAssertTrue(OpenFileState(commands:[command]).busy(kind,home.appendingPathComponent(path).path))
        }
    }
    func testForgedLatestAndFreshSnapshotsAndBroadRootsAreRejected() throws {
        let latestHistory=try history(uuidA,rootAge:100,childAge:90)
        let claude=try write(".claude/shell-snapshots/snapshot-zsh-1760000000000-ab12.sh");try aged(claude,20)
        let codex=try write(".codex/shell_snapshots/\(uuidA).a.sh");try aged(codex,20)
        let old=try write(".codex/shell_snapshots/\(uuidB).a.sh");try aged(old,30)
        let fresh=try write(".codex/shell_snapshots/\(uuidB).b.sh");try aged(fresh,1)
        let broad=try write(".codex/cache/unknown/file").deletingLastPathComponent().deletingLastPathComponent()
        let outside=root.appendingPathComponent("outside/Cache");try fm.createDirectory(at:outside,withIntermediateDirectories:true)
        try Data("keep".utf8).write(to:outside.appendingPathComponent("source"))
        let fixtures:[(URL,String)]=[(latestHistory,"claudeFileHistory"),(claude,"claudeShellSnapshot"),(codex,"codexShellSnapshot"),(fresh,"codexShellSnapshot"),(broad,"aiCache"),(outside,"aiCache")]
        let candidates=try fixtures.map{try forge($0.0,kind:$0.1)}
        let result=try engine.clean(ScanReport(candidates:candidates))
        XCTAssertEqual(result.removedCount,0);XCTAssertEqual(result.skipped.count,fixtures.count)
        for (p,_) in fixtures { XCTAssertTrue(fm.fileExists(atPath:p.path)) }
    }
    func testFreshDescendantAndRootSymlinkSwapAreProtectedAfterScan() throws {
        let old=try history(uuidA,rootAge:100,childAge:90)
        _=try history(uuidB,rootAge:80,childAge:70)
        let report=try engine.scan();XCTAssertEqual(report.candidates.count,1)
        _=try write(".claude/file-history/\(uuidA)/fresh@v2")
        XCTAssertEqual(try engine.clean(report).removedCount,0);XCTAssertTrue(fm.fileExists(atPath:old.path))
        let cache=try self.cache("Claude")
        let scanned=try engine.scan().selecting([cache.path])
        let moved=root.appendingPathComponent("moved-cache");try fm.moveItem(at:cache,to:moved)
        try fm.createSymbolicLink(at:cache,withDestinationURL:moved)
        XCTAssertEqual(try engine.clean(scanned).removedCount,0);XCTAssertTrue(fm.fileExists(atPath:moved.appendingPathComponent("entry").path))
    }

    func testDiscoveredRenamedCodexOwnsSnapshotsAndMetadataWithoutOpenHandles() throws {
        try installed("RenamedCodex",["CFBundleIdentifier":"com.openai.codex","CFBundleName":"RenamedCodexCache","CFBundleExecutable":"RenamedRuntime"])
        let gpu=try cache("RenamedCodexCache","GPUCache")
        let metadata=try write(".codex/cache/remote_plugin_catalog/"+String(repeating:"a",count:16)+".json")
        let old=try write(".codex/shell_snapshots/\(uuidA).a.sh");try aged(old,30)
        let latest=try write(".codex/shell_snapshots/\(uuidA).b.sh");try aged(latest,20)
        var idle=CleanupRules(config:engine.configuration,openFiles:OpenFileState())
        idle.scanAITools()
        XCTAssertEqual(Set(idle.candidates.map(\.path)),Set([gpu.path,metadata.path,old.path]))
        let running=OpenFileState(commands:[apps.appendingPathComponent("RenamedCodex.app/Contents/MacOS/RenamedRuntime").path])
        XCTAssertTrue(running.paths.isEmpty)
        for candidate in idle.candidates { XCTAssertTrue(idle.busy(candidate.kind,candidate.path,state:running),candidate.path) }
        var active=CleanupRules(config:engine.configuration,openFiles:running)
        active.scanAITools()
        XCTAssertTrue(active.candidates.isEmpty,active.candidates.map(\.path).joined(separator:"\n"))
        XCTAssertEqual(active.warnings.count,3)
    }
    func testDiscoveredRenamedCursorOwnsLegacySnapshotsAndSearchIndex() throws {
        try installed("RenamedCursor",["CFBundleIdentifier":"com.todesktop.230313mzl4w4u92","CFBundleName":"RenamedCursor"])
        let snapshots=try write("Library/Application Support/Cursor/snapshots/stores/old").deletingLastPathComponent().deletingLastPathComponent()
        let search=try write("Library/Application Support/Cursor/User/globalStorage/conversation-search.db")
        var idle=CleanupRules(config:engine.configuration,openFiles:OpenFileState())
        idle.scanRustAndCursor();XCTAssertEqual(Set(idle.candidates.map(\.path)),Set([snapshots.path,search.path]))
        let running=OpenFileState(commands:[apps.appendingPathComponent("RenamedCursor.app/Contents/MacOS/Runtime").path])
        for candidate in idle.candidates { XCTAssertTrue(idle.busy(candidate.kind,candidate.path,state:running),candidate.path) }
        var active=CleanupRules(config:engine.configuration,openFiles:running)
        active.scanRustAndCursor();XCTAssertTrue(active.candidates.isEmpty);XCTAssertEqual(active.warnings.count,2)
    }
    func testExactUppercaseClaudeExecutableProtectsRenamedAppArtifacts() throws {
        let old=try history(uuidA,rootAge:100,childAge:90)
        _=try history(uuidB,rootAge:80,childAge:70)
        let shell=try write(".claude/shell-snapshots/snapshot-zsh-1760000000000-ab12.sh");try aged(shell,20)
        let latest=try write(".claude/shell-snapshots/snapshot-zsh-1760000000001-cd34.sh");try aged(latest,10)
        let metadata=try write(".claude/cache/changelog.md")
        let gpu=try cache("Claude","GPUCache")
        var idle=CleanupRules(config:engine.configuration,openFiles:OpenFileState())
        idle.scanAITools();XCTAssertEqual(Set(idle.candidates.map(\.path)),Set([old.path,shell.path,metadata.path,gpu.path]))
        let running=OpenFileState(commands:["/Applications/RenamedClaude.app/Contents/MacOS/Claude"])
        for candidate in idle.candidates { XCTAssertTrue(idle.busy(candidate.kind,candidate.path,state:running),candidate.path) }
        var active=CleanupRules(config:engine.configuration,openFiles:running)
        active.scanAITools();XCTAssertTrue(active.candidates.isEmpty)
        let unrelated=OpenFileState(commands:["/Applications/Unrelated.app/Contents/MacOS/Claude-helper","/project/claude-project/python"])
        XCTAssertFalse(idle.busy(.claudeFileHistory,old.path,state:unrelated))
    }

}
