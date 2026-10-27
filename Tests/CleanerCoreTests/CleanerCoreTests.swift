import XCTest
import Darwin
@testable import CleanerCore

final class CleanerCoreTests: XCTestCase {
    var root: URL!
    var home: URL!
    var temp: URL!
    var engine: CleaningEngine!
    let fm = FileManager.default

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("FeatherSweepTests-\(UUID().uuidString)").resolvingSymlinksInPath()
        home = root.appendingPathComponent("home")
        temp = root.appendingPathComponent("tmp")
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
        try fm.createDirectory(at: temp, withIntermediateDirectories: true)
        engine = CleaningEngine(configuration: .init(home: home, temporaryRoots: [temp], userTemporaryRoot: root.appendingPathComponent("T"), checkOpenFiles: false))
    }
    override func tearDownWithError() throws { if let root { try fm.removeItem(at: root) } }
    func write(_ relative: String, _ contents: String = "payload") throws -> URL {
        let p = home.appendingPathComponent(relative)
        try fm.createDirectory(at: p.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: p)
        return p
    }
    func goCache() throws -> URL {
        let p = try write("Library/Caches/go-build/README", "This directory holds cached build artifacts from the Go build system.\n")
        _ = try write("Library/Caches/go-build/aa/" + String(repeating: "a", count: 64) + "-d")
        return p.deletingLastPathComponent()
    }
    func testRecognizedGoCacheIsDiscoveredWithoutWriting() throws {
        let cache = try goCache()
        let before = try fm.subpathsOfDirectory(atPath: cache.path)
        let report = try engine.scan()
        XCTAssertEqual(report.candidates.filter { $0.kind == .goCache }.count, 1, report.warnings.joined(separator: "\n"))
        XCTAssertEqual(try fm.subpathsOfDirectory(atPath: cache.path), before)
        XCTAssertTrue(report.totalBytes > 0)
    }

    func testCleanupRemovesCacheAndPreservesSourceAndCredentials() throws {
        let cache = try goCache()
        let source = try write("Desktop/project/main.swift", "important source")
        let cookies = try write("Library/Application Support/Google/Chrome/Default/Cookies", "login")
        let passwords = try write("Library/Application Support/Google/Chrome/Default/Login Data", "passwords")
        let result = try engine.clean(engine.scan())
        XCTAssertEqual(result.removedCount, 1)
        XCTAssertFalse(fm.fileExists(atPath: cache.appendingPathComponent("aa").path))
        XCTAssertTrue(fm.fileExists(atPath: cache.appendingPathComponent("README").path))
        XCTAssertEqual(try String(contentsOf: source), "important source")
        XCTAssertEqual(try String(contentsOf: cookies), "login")
        XCTAssertEqual(try String(contentsOf: passwords), "passwords")
    }

    func testUnknownFileMakesGoCacheIneligible() throws {
        _ = try goCache()
        _ = try write("Library/Caches/go-build/source.swift")
        XCTAssertTrue(try engine.scan().candidates.isEmpty)
    }

    func testChangedCacheAfterScanIsSkipped() throws {
        _ = try goCache()
        let report = try engine.scan()
        let newFile = try write("Library/Caches/go-build/aa/" + String(repeating: "b", count: 64) + "-d", "new build")
        let result = try engine.clean(report)
        XCTAssertTrue(fm.fileExists(atPath: newFile.path))
        XCTAssertEqual(result.removedCount, 0)
        XCTAssertFalse(result.skipped.isEmpty)
    }

    func testRootSymlinkIsNeverScanned() throws {
        let cache = try goCache()
        let outside = root.appendingPathComponent("important")
        try fm.moveItem(at: cache, to: outside)
        try fm.createSymbolicLink(at: cache, withDestinationURL: outside)
        XCTAssertTrue(try engine.scan().candidates.isEmpty)
        XCTAssertTrue(fm.fileExists(atPath: outside.appendingPathComponent("README").path))
    }

    func testSymlinkReplacementAfterScanDoesNotEscape() throws {
        let cache = try goCache()
        let report = try engine.scan()
        let outside = root.appendingPathComponent("outside")
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        let precious = outside.appendingPathComponent("precious.txt")
        try Data("keep me".utf8).write(to: precious)
        try fm.removeItem(at: cache.appendingPathComponent("aa"))
        try fm.createSymbolicLink(at: cache.appendingPathComponent("aa"), withDestinationURL: outside)
        let result = try engine.clean(report)
        XCTAssertEqual(try String(contentsOf: precious), "keep me")
        XCTAssertFalse(result.skipped.isEmpty)
    }

    func testForgedCredentialCandidateIsRejected() throws {
        let p = try write("Library/Application Support/Google/Chrome/Default/Cookies", "keep")
        let forged = CleanupCandidate(path: p.path, category: .compilation, kind: .goCache, reason: "fake")
        let result = try engine.clean(ScanReport(candidates: [forged]))
        XCTAssertEqual(try String(contentsOf: p), "keep")
        XCTAssertEqual(result.removedCount, 0)
        XCTAssertFalse(result.skipped.isEmpty)
    }

    func testStaleScanIsNotCleaned() throws {
        _ = try goCache()
        var report = try engine.scan()
        report.scannedAt = Date(timeIntervalSinceNow: -3601)
        XCTAssertThrowsError(try engine.clean(report))
    }

    let backupRoot = "Library/Application Support/Blender/5.0/extensions/.user/user_default/claude_blender/checkpoints"
    func backup(_ name: String, age: Double) throws -> URL {
        let p = try write(backupRoot + "/" + name, "scene")
        try fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -age)], ofItemAtPath: p.path)
        return p
    }
    func testOneLatestBackupPerSceneIsRetained() throws {
        let aOld = try backup("A-agent-20260101-010000-1.blend", age: 200)
        let aNew = try backup("A-agent-20260101-010100-2.blend", age: 100)
        let b = try backup("B-agent-20260101-010200-3.blend", age: 50)
        let unrelated = try write(backupRoot + "/original.blend")
        let report = try engine.scan()
        XCTAssertEqual(Set(report.retainedBackups), Set([aNew.path, b.path]))
        XCTAssertEqual(report.candidates.filter { $0.kind == .blenderBackup }.count, 1)
        _ = try engine.clean(report)
        XCTAssertFalse(fm.fileExists(atPath: aOld.path))
        for p in [aNew,b,unrelated] { XCTAssertTrue(fm.fileExists(atPath: p.path)) }
    }
    func testBackupThatBecameLatestIsProtected() throws {
        let old = try backup("A-agent-20260101-010000-1.blend", age: 200)
        let latest = try backup("A-agent-20260101-010100-2.blend", age: 100)
        let report = try engine.scan()
        try fm.removeItem(at: latest)
        let result = try engine.clean(report)
        XCTAssertTrue(fm.fileExists(atPath: old.path))
        XCTAssertEqual(result.removedCount, 0)
    }

    let yisora = "Desktop/docker/yijun_project/clawise_agent/yisora"
    func duplicate() throws -> (URL,URL) {
        let original = try write(yisora + "/release/current/Lumi-0.2.09-win-x64.exe", "same installer")
        let copy = try write(yisora + "/artifacts/packaging-current/build/win32-x64/Lumi-0.2.09-win-x64.exe", "same installer")
        return (original,copy)
    }
    func testDuplicatePackageKeepsFormalRelease() throws {
        let (original,copy) = try duplicate()
        let report = try engine.scan()
        XCTAssertEqual(report.candidates.filter { $0.kind == .duplicatePackage }.count, 1)
        _ = try engine.clean(report)
        XCTAssertFalse(fm.fileExists(atPath: copy.path))
        XCTAssertEqual(try String(contentsOf: original), "same installer")
    }
    func testChangedFormalReleaseProtectsDuplicate() throws {
        let (original,copy) = try duplicate()
        let report = try engine.scan()
        try Data("new release".utf8).write(to: original)
        let result = try engine.clean(report)
        XCTAssertTrue(fm.fileExists(atPath: copy.path))
        XCTAssertFalse(result.skipped.isEmpty)
    }
    func testRustIntermediateCleanupPreservesExecutable() throws {
        let base = "Desktop/docker/yijun_project/wifi_RuView/v2/target/debug/"
        let intermediate = try write(base + "incremental/unit/dep-graph.bin")
        let executable = try write(base + "sensing-server", "executable")
        _ = try engine.clean(engine.scan())
        XCTAssertFalse(fm.fileExists(atPath: intermediate.path))
        XCTAssertEqual(try String(contentsOf: executable), "executable")
    }

    func testStagingCopyRemovalPreservesSourceAndInstaller() throws {
        let base = yisora + "/artifacts/packaging-current/build/win32-x64/"
        let staged = try write(base + "win-unpacked/Lumi.exe")
        let final = try write(base + "Lumi-0.2.09-win-x64.exe", "installer")
        let source = try write(yisora + "/src/main.ts", "source")
        _ = try engine.clean(engine.scan())
        XCTAssertFalse(fm.fileExists(atPath: staged.path))
        XCTAssertEqual(try String(contentsOf: final), "installer")
        XCTAssertEqual(try String(contentsOf: source), "source")
    }

    func testCursorSnapshotCleanupPreservesSettingsAndDatabase() throws {
        let base = "Library/Application Support/Cursor/"
        let snapshot = try write(base + "snapshots/stores/old")
        let settings = try write(base + "User/settings.json", "settings")
        let db = try write(base + "User/globalStorage/state.vscdb", "state")
        _ = try engine.clean(engine.scan())
        XCTAssertFalse(fm.fileExists(atPath: snapshot.path))
        XCTAssertEqual(try String(contentsOf: settings), "settings")
        XCTAssertEqual(try String(contentsOf: db), "state")
    }
    func testRustBuildLockPreventsCleanup() throws {
        let base = "Desktop/docker/yijun_project/wifi_RuView/v2/target/debug/"
        let intermediate = try write(base + "incremental/unit/dep-graph.bin")
        let lock = try write(base + ".cargo-lock", "")
        let handle = try FileHandle(forUpdating: lock)
        defer { try? handle.close() }
        XCTAssertEqual(flock(handle.fileDescriptor, LOCK_EX | LOCK_NB), 0)
        let result = try engine.clean(engine.scan())
        XCTAssertTrue(fm.fileExists(atPath: intermediate.path))
        XCTAssertEqual(result.removedCount, 0)
    }
    func testForgedCompanionCannotDeleteCredentials() throws {
        _ = try goCache()
        let cookie = try write("Library/Application Support/Google/Chrome/Default/Cookies", "keep")
        var report = try engine.scan()
        XCTAssertEqual(report.candidates.count, 1)
        report.candidates[0].companionPaths = [cookie.path]
        let result = try engine.clean(report)
        XCTAssertEqual(try String(contentsOf: cookie), "keep")
        XCTAssertEqual(result.removedCount, 0)
        XCTAssertFalse(result.skipped.isEmpty)
    }
    func testOpenFileIsNotOfferedForCleanup() throws {
        let cache = try goCache()
        let file = cache.appendingPathComponent("aa/" + String(repeating: "a", count: 64) + "-d")
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        let checked = CleaningEngine(configuration: .init(home: home, temporaryRoots: [temp], userTemporaryRoot: root.appendingPathComponent("T"), checkOpenFiles: true))
        let report = try checked.scan()
        XCTAssertFalse(report.candidates.contains { $0.path == cache.path })
        XCTAssertTrue(report.warnings.contains { $0.contains(cache.path) })
        XCTAssertTrue(fm.fileExists(atPath: file.path))
    }
    func testSigningClonesKeepLatestTwoAndUseNoSharedByteEstimate() throws {
        let parent = root.appendingPathComponent("X/com.google.Chrome.code_sign_clone")
        for (name, age) in [("old",600.0),("newer",100.0),("newest",50.0)] {
            let p = parent.appendingPathComponent("code_sign_clone."+name)
            let info = p.appendingPathComponent("Google Chrome.app.bundle/Contents/Info.plist")
            try fm.createDirectory(at: info.deletingLastPathComponent(), withIntermediateDirectories: true)
            try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier":"com.google.Chrome"], format: .xml, options: 0).write(to: info)
            try fm.setAttributes([.modificationDate:Date(timeIntervalSinceNow:-age)], ofItemAtPath:p.path)
        }
        let report = try engine.scan()
        let clones = report.candidates.filter { $0.kind == .signingClone }
        XCTAssertEqual(clones.count,1)
        XCTAssertEqual(clones.first?.estimatedBytes,0)
        _ = try engine.clean(report)
        XCTAssertFalse(fm.fileExists(atPath:parent.appendingPathComponent("code_sign_clone.old").path))
        XCTAssertEqual(try fm.contentsOfDirectory(atPath:parent.path).count,2)
    }
    func testOnlyObsoleteCursorUpdateIsRemoved() throws {
        let apps=root.appendingPathComponent("Applications")
        func bundle(_ url:URL,_ version:String) throws {
            let p=url.appendingPathComponent("Contents/Info.plist")
            try fm.createDirectory(at:p.deletingLastPathComponent(),withIntermediateDirectories:true)
            try PropertyListSerialization.data(fromPropertyList:["CFBundleShortVersionString":version],format:.xml,options:0).write(to:p)
        }
        try bundle(apps.appendingPathComponent("Cursor.app"),"3.2")
        let base=home.appendingPathComponent("Library/Caches/com.todesktop.230313mzl4w4u92.ShipIt")
        try bundle(base.appendingPathComponent("update.Old/Cursor.app"),"3.1")
        try bundle(base.appendingPathComponent("update.New/Cursor.app"),"3.3")
        let e=CleaningEngine(configuration:.init(home:home,temporaryRoots:[temp],userTemporaryRoot:root.appendingPathComponent("T"),checkOpenFiles:false,applicationsRoot:apps))
        let report=try e.scan()
        XCTAssertEqual(report.candidates.filter{$0.kind == .obsoleteUpdate}.count,1)
        _=try e.clean(report)
        XCTAssertFalse(fm.fileExists(atPath:base.appendingPathComponent("update.Old").path))
        XCTAssertTrue(fm.fileExists(atPath:base.appendingPathComponent("update.New").path))
        XCTAssertTrue(fm.fileExists(atPath:apps.appendingPathComponent("Cursor.app").path))
    }
    func testGoFuzzCorpusIsPreservedAndNotCounted() throws {
        let cache=try goCache()
        let corpus=try write("Library/Caches/go-build/fuzz/corpus",String(repeating:"x",count:16384))
        let report=try engine.scan()
        XCTAssertTrue(report.totalBytes<16384)
        _=try engine.clean(report)
        XCTAssertTrue(fm.fileExists(atPath:corpus.path))
        XCTAssertTrue(fm.fileExists(atPath:cache.appendingPathComponent("README").path))
    }

    func clone(_ name:String,modified:Date) throws -> URL {
        let p=root.appendingPathComponent("X/com.google.Chrome.code_sign_clone/code_sign_clone."+name)
        let info=p.appendingPathComponent("Google Chrome.app.bundle/Contents/Info.plist")
        try fm.createDirectory(at:info.deletingLastPathComponent(),withIntermediateDirectories:true)
        try PropertyListSerialization.data(fromPropertyList:["CFBundleIdentifier":"com.google.Chrome"],format:.xml,options:0).write(to:info)
        try fm.setAttributes([.modificationDate:modified],ofItemAtPath:p.path)
        return p
    }
    func testReviewSigningCloneDescendantChangeIsSkipped() throws {
        let old=try clone("old",modified:Date(timeIntervalSinceNow:-600))
        _=try clone("newer",modified:Date(timeIntervalSinceNow:-100))
        _=try clone("newest",modified:Date(timeIntervalSinceNow:-50))
        let report=try engine.scan()
        XCTAssertEqual(report.candidates.filter{$0.kind == .signingClone}.count,1)
        let before=try SafeFS.metadata(old)
        let info=old.appendingPathComponent("Google Chrome.app.bundle/Contents/Info.plist")
        try PropertyListSerialization.data(fromPropertyList:["CFBundleIdentifier":"com.google.Chrome","CFBundleVersion":"changed"],format:.xml,options:0).write(to:info)
        XCTAssertEqual(try SafeFS.metadata(old),before)
        let result=try engine.clean(report)
        XCTAssertTrue(fm.fileExists(atPath:old.path))
        XCTAssertEqual(result.removedCount,0)
        XCTAssertFalse(result.skipped.isEmpty)
    }
    func testReviewSigningRetentionIncludesNanoseconds() throws {
        let base=floor(Date().timeIntervalSince1970)-600
        let oldest=try clone("a",modified:Date(timeIntervalSince1970:base+0.1))
        _=try clone("b",modified:Date(timeIntervalSince1970:base+0.5))
        let newest=try clone("c",modified:Date(timeIntervalSince1970:base+0.9))
        let report=try engine.scan()
        XCTAssertEqual(report.candidates.filter{$0.kind == .signingClone}.map(\.path),[oldest.path])
        _=try engine.clean(report)
        XCTAssertTrue(fm.fileExists(atPath:newest.path))
    }
    func testReviewSceneNamesContainingAgentAreNotMerged() throws {
        let a=try backup("A-agent-test-agent-20260101-010000-1.blend",age:200)
        let b=try backup("A-agent-20260101-010100-2.blend",age:100)
        let report=try engine.scan()
        XCTAssertEqual(Set(report.retainedBackups),Set([a.path,b.path]))
        XCTAssertTrue(report.candidates.filter{$0.kind == .blenderBackup}.isEmpty)
        _=try engine.clean(report)
        XCTAssertTrue(fm.fileExists(atPath:a.path))
        XCTAssertTrue(fm.fileExists(atPath:b.path))
    }

    func testFileOpenedBetweenCleanupItemsIsSkipped() throws {
        _=try goCache()
        let second=temp.appendingPathComponent("late-gocache")
        try fm.createDirectory(at:second.appendingPathComponent("aa"),withIntermediateDirectories:true)
        try Data("This directory holds cached build artifacts from the Go build system.\n".utf8).write(to:second.appendingPathComponent("README"))
        let target=second.appendingPathComponent("aa/"+String(repeating:"a",count:64)+"-d")
        try Data("payload".utf8).write(to:target)
        let checked=CleaningEngine(configuration:.init(home:home,temporaryRoots:[temp],userTemporaryRoot:root.appendingPathComponent("T"),checkOpenFiles:true))
        let report=try checked.scan()
        XCTAssertEqual(report.candidates.filter{$0.kind == .goCache}.count,2)
        var handle:FileHandle?
        defer { try? handle?.close() }
        let result=try checked.clean(report) { fraction,_ in
            if fraction>0 && fraction<1 && handle==nil { handle=try? FileHandle(forReadingFrom:target) }
        }
        XCTAssertNotNil(handle)
        XCTAssertTrue(fm.fileExists(atPath:target.path))
        XCTAssertEqual(result.removedCount,1)
        XCTAssertTrue(result.skipped.contains{$0.contains(second.path)})
    }

    func testReviewPartialLsofOutputFailsClosed() throws {
        XCTAssertThrowsError(try OpenFileState.validatedOutput(executable:"/usr/sbin/lsof",status:1,output:Data("p42\nn/path".utf8),diagnostics:Data("incomplete".utf8)))
        XCTAssertThrowsError(try OpenFileState.validatedOutput(executable:"/usr/sbin/lsof",status:0,output:Data("p42".utf8),diagnostics:Data("warning: output incomplete".utf8)))
    }
    func testReviewReferenceChangedAfterVerificationIsRejected() throws {
        let p=try write(yisora+"/release/current/Lumi-1.0-win-x64.exe","old release")
        let reference=try VerifiedReference(url:p,digest:SafeFS.digest(p))
        try Data("new release".utf8).write(to:p)
        XCTAssertThrowsError(try reference.validateUnchanged())
    }
    func testReviewPartialDeletionIsAccounted() throws {
        let cache=try goCache()
        let blocked=try write("Library/Caches/go-build/bb/"+String(repeating:"b",count:64)+"-d","blocked")
        let directory=blocked.deletingLastPathComponent()
        try fm.setAttributes([.posixPermissions:0o555],ofItemAtPath:directory.path)
        defer { try? fm.setAttributes([.posixPermissions:0o755],ofItemAtPath:directory.path) }
        let report=try engine.scan()
        XCTAssertEqual(report.candidates.count,1)
        let result=try engine.clean(report)
        XCTAssertFalse(fm.fileExists(atPath:cache.appendingPathComponent("aa").path))
        XCTAssertTrue(fm.fileExists(atPath:blocked.path))
        XCTAssertGreaterThan(result.removedBytes,0)
        XCTAssertEqual(result.partialCount,1)
        XCTAssertFalse(result.failed.isEmpty)
    }

}
