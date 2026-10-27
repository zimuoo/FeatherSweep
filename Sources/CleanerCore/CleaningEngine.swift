import Foundation
import Darwin

public struct CleanerConfiguration: Sendable {
    public var home: URL
    public var temporaryRoots: [URL]
    public var userTemporaryRoot: URL
    public var applicationsRoot: URL
    public var checkOpenFiles: Bool
    public var persistHistory: Bool
    public init(home: URL, temporaryRoots: [URL], userTemporaryRoot: URL, checkOpenFiles: Bool = true,
                applicationsRoot: URL = URL(fileURLWithPath:"/Applications"), persistHistory: Bool = false) {
        self.home = Self.canonical(home); self.temporaryRoots = temporaryRoots.map(Self.canonical); self.userTemporaryRoot = Self.canonical(userTemporaryRoot)
        self.checkOpenFiles = checkOpenFiles; self.applicationsRoot = applicationsRoot; self.persistHistory = persistHistory
    }
    private static func canonical(_ url: URL) -> URL {
        guard let path = realpath(url.path, nil) else { return url.standardizedFileURL }
        defer { Darwin.free(path) }
        return URL(fileURLWithPath: String(cString: path))
    }
    public static func live() -> CleanerConfiguration {
        .init(home: FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath(),
              temporaryRoots: [URL(fileURLWithPath:"/private/tmp"), URL(fileURLWithPath:NSTemporaryDirectory()).resolvingSymlinksInPath()],
              userTemporaryRoot: URL(fileURLWithPath:NSTemporaryDirectory()).resolvingSymlinksInPath(), persistHistory:true)
    }
}

public final class CleaningEngine: @unchecked Sendable {
    public let configuration: CleanerConfiguration
    private let operation = NSLock()
    public init(configuration: CleanerConfiguration = .live()) { self.configuration = configuration }

    public func scan(progress: @escaping (Double, String) -> Void = { _, _ in }) throws -> ScanReport {
        guard operation.try() else { throw CleanerError.system("已有扫描或清理正在运行。") }; defer { operation.unlock() }
        progress(0,"检查使用中的文件")
        var state=OpenFileState(),initialWarnings:[String]=[]
        do { state=try OpenFileState.capture(enabled:configuration.checkOpenFiles) }
        catch { initialWarnings.append(error.localizedDescription + "；清理前将再次检查。") }
        var rules=CleanupRules(config:configuration,openFiles:state)
        progress(0.05,"查看 Go 编译缓存");rules.scanGo()
        progress(0.23,"查看 Rust 与 Cursor 快照");rules.scanRustAndCursor()
        progress(0.40,"保留每个 Blender 场景的最新备份");rules.scanBlender()
        progress(0.49,"核对打包副本与正式安装包");rules.scanPackaging()
        progress(0.66,"检查闲置应用签名副本");rules.scanSigning()
        progress(0.75,"比较更新下载版本");rules.scanUpdates()
        progress(0.86,"识别飞书与 Cloudflare 静态资源");rules.scanWebCache()
        var seen=Set<String>()
        let items=rules.candidates.filter { seen.insert($0.path).inserted }
        progress(1,"扫描完成")
        return ScanReport(candidates:items,warnings:initialWarnings+rules.warnings,availableBytes:SafeFS.available(configuration.home),retainedBackups:rules.retained.sorted())
    }

    public func clean(_ report: ScanReport, progress: @escaping (Double, String) -> Void = { _, _ in }) throws -> CleanupResult {
        guard operation.try() else { throw CleanerError.system("已有扫描或清理正在运行。") }; defer { operation.unlock() }
        guard Date().timeIntervalSince(report.scannedAt)<=1800, report.scannedAt.timeIntervalSinceNow<=5 else { throw CleanerError.staleScan }
        var state=try OpenFileState.capture(enabled:configuration.checkOpenFiles)
        var lastOccupancyCheck=Date()
        func requireIdle(_ c:CleanupCandidate, force:Bool=false) throws {
            if configuration.checkOpenFiles && (force || Date().timeIntervalSince(lastOccupancyCheck)>=1) {
                state=try OpenFileState.capture(enabled:true);lastOccupancyCheck=Date()
            }
            guard !state.busy(c.kind,c.path),!c.companionPaths.contains(where:{state.contains($0)}), !(c.referencePath.map{state.contains($0)} ?? false) else { throw CleanerError.busy(c.path) }
        }
        let rules=CleanupRules(config:configuration,openFiles:state)
        let before=SafeFS.available(configuration.home)
        var removedBytes:Int64=0,removedCount=0,partialCount=0,skipped:[String]=[],failed:[String]=[]
        var rustLocks:[String:RustBuildLock]=[:]
        defer { withExtendedLifetime(rustLocks) {} }
        for (index,c) in report.candidates.enumerated() {
            progress(Double(index)/Double(max(1,report.candidates.count)),c.category.title)
            var touched=false
            do {
                var referenceGuard:VerifiedReference?
                guard rules.allowed(c),let expected=c.identity else { throw CleanerError.unsafe(c.path) }
                let url=URL(fileURLWithPath:c.path)
                try requireIdle(c,force: ![CleanupKind.staticWebEntry,.signingClone].contains(c.kind))
                if c.kind == .rustCache {
                    let profile=url.deletingLastPathComponent()
                    if rustLocks[profile.path] == nil { rustLocks[profile.path]=try RustBuildLock(profile:profile) }
                }
                guard try SafeFS.metadata(url)==expected else { throw CleanerError.changed(c.path) }
                if c.kind == .goCache { guard try rules.goIsValid(url) else { throw CleanerError.unsafe(c.path) } }
                if c.kind == .blenderBackup {
                    guard let scene=rules.backupScene(url),let group=try rules.backupGroups()[scene],group.count>1,group.first != url else { throw CleanerError.changed("最新或唯一场景备份："+c.path) }
                }
                if c.kind == .duplicatePackage {
                    guard let reference=c.referencePath,let digest=c.referenceDigest else { throw CleanerError.unsafe(c.path) }
                    referenceGuard=try VerifiedReference(url:URL(fileURLWithPath:reference),digest:digest)
                    guard try SafeFS.digest(url)==digest else { throw CleanerError.changed("重复包："+c.path) }
                }
                if c.kind == .obsoleteUpdate { guard try rules.obsoleteUpdate(url) else { throw CleanerError.changed("更新下载不再过时："+c.path) } }
                if c.kind == .staticWebEntry { guard try WebCache.validGroup([url]+c.companionPaths.map{URL(fileURLWithPath:$0)}) else { throw CleanerError.changed(c.path) } }
                if c.kind == .signingClone {
                    guard try rules.validClone(url),Date().timeIntervalSince1970-Double(expected.modifiedSeconds)>300 else { throw CleanerError.changed(c.path) }
                    let latest=try rules.children(url.deletingLastPathComponent()).filter{$0.lastPathComponent.hasPrefix("code_sign_clone.")}.sorted(by:rules.newer)
                    guard !latest.prefix(2).contains(url) else { throw CleanerError.changed("最新签名副本："+c.path) }
                }
                let paths=[url]+c.companionPaths.map{URL(fileURLWithPath:$0)}
                var trees:[TreeSnapshot]=[]
                for path in paths { trees.append(try rules.snapshot(path,kind:c.kind,entries:true)) }
                guard trees.map(\.fingerprint).joined(separator:":")==c.metadataFingerprint else { throw CleanerError.changed(c.path) }
                try requireIdle(c,force:c.kind == .duplicatePackage)
                try referenceGuard?.validateUnchanged()
                // Each removal is descriptor-relative, never follows a symlink, and
                // rejects any leaf inserted or replaced since this preflight snapshot.
                for (path,tree) in zip(paths,trees) {
                    try referenceGuard?.validateUnchanged()
                    try SafeFS.remove(path,snapshot:tree,expectedFingerprint:tree.fingerprint,keepingGoCacheRoot:c.kind == .goCache) { bytes in
                        touched=true
                        if c.kind != .signingClone { removedBytes += bytes }
                    }
                }
                removedCount += 1
            } catch let e as CleanerError {
                if touched { partialCount += 1;failed.append("已清理部分内容，剩余项目未完成："+c.path+"；"+e.localizedDescription);continue }
                switch e {
                case .unsafe,.changed,.busy: skipped.append(e.localizedDescription)
                case .system: failed.append(e.localizedDescription)
                case .staleScan: skipped.append(e.localizedDescription)
                }
            } catch {
                if touched { partialCount += 1 }
                failed.append((touched ? "已清理部分内容：" : "")+c.path+"："+error.localizedDescription)
            }
        }
        let result=CleanupResult(removedBytes:removedBytes,availableBytesBefore:before,availableBytesAfter:SafeFS.available(configuration.home),removedCount:removedCount,skipped:skipped,failed:failed,partialCount:partialCount)
        if configuration.persistHistory { record(result) }
        progress(1,failed.isEmpty ? "清理完成" : "清理结束，部分项目已跳过")
        return result
    }
    private func record(_ result:CleanupResult) {
        guard let defaults=UserDefaults(suiteName:"io.github.zimuoo.FeatherSweep") else { return }
        var rows=defaults.array(forKey:"cleanupHistory") as? [[String:Any]] ?? []
        rows.append(["date":ISO8601DateFormatter().string(from:Date()),"removedBytes":result.removedBytes,"freedBytes":result.freedBytes,"removedCount":result.removedCount,"partialCount":result.partialCount,"skippedCount":result.skipped.count,"failedCount":result.failed.count])
        defaults.set(Array(rows.suffix(20)),forKey:"cleanupHistory")
    }
}
