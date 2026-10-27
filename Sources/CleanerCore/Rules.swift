import Foundation
import Darwin

struct CleanupRules {
    let config: CleanerConfiguration
    let openFiles: OpenFileState
    let aiProducts: [AITool]
    init(config: CleanerConfiguration, openFiles: OpenFileState) {
        self.config = config; self.openFiles = openFiles; self.aiProducts = AITool.discover(config)
    }
    var candidates: [CleanupCandidate] = []
    var warnings: [String] = []
    var retained: [String] = []
    let fm = FileManager.default
    var yisora: URL { config.home.appendingPathComponent("Desktop/docker/yijun_project/clawise_agent/yisora") }
    var artifacts: URL { yisora.appendingPathComponent("artifacts") }
    var releases: URL { yisora.appendingPathComponent("release") }
    var cursor: URL { config.home.appendingPathComponent("Library/Application Support/Cursor") }
    var backupRoot: URL { config.home.appendingPathComponent("Library/Application Support/Blender/5.0/extensions/.user/user_default/claude_blender/checkpoints") }
    var webRoot: URL { config.home.appendingPathComponent("Library/Application Support/Google/Chrome/Default/Service Worker/CacheStorage") }
    var rustRoot: URL { config.home.appendingPathComponent("Desktop/docker/yijun_project/wifi_RuView/v2/target") }
    var telegramRoot: URL { config.home.appendingPathComponent("Library/Caches/ru.keepcoder.Telegram/org.sparkle-project.Sparkle/PersistentDownloads") }
    var shipItRoot: URL { config.home.appendingPathComponent("Library/Caches/com.todesktop.230313mzl4w4u92.ShipIt") }
    var signingRoots: [URL] { ["com.google.Chrome", "com.citrolabs.ego.lite"].map { config.userTemporaryRoot.deletingLastPathComponent().appendingPathComponent("X/\($0).code_sign_clone") } }

    func children(_ url: URL) throws -> [URL] { SafeFS.exists(url) ? try SafeFS.children(url) : [] }
    func version(_ url: URL) throws -> [Int] {
        let data = try SafeFS.readPrefix(url.appendingPathComponent("Contents/Info.plist"), limit: 1024*1024)
        guard let d = try PropertyListSerialization.propertyList(from:data,format:nil) as? [String:Any], let v = d["CFBundleShortVersionString"] as? String else { throw CleanerError.unsafe(url.path) }
        let parts = v.split(separator:".").compactMap { Int($0) }
        guard !parts.isEmpty else { throw CleanerError.unsafe(url.path) }; return parts
    }
    func goIsValid(_ url: URL) throws -> Bool {
        guard let m = try? SafeFS.metadata(url), SafeFS.isDirectory(m), !SafeFS.isLink(m), m.owner == getuid() else { return false }
        guard SafeFS.exists(url.appendingPathComponent("README")) else { return false }
        guard String(decoding: try SafeFS.readPrefix(url.appendingPathComponent("README"), limit:512), as: UTF8.self).hasPrefix("This directory holds cached build artifacts from the Go build system.") else { return false }
        for p in try children(url) {
            if ["README","trim.txt","fuzz"].contains(p.lastPathComponent) { continue }
            guard p.lastPathComponent.matches("^[0-9a-f]{2}$"), SafeFS.isDirectory(try SafeFS.metadata(p)) else { return false }
            for file in try children(p) {
                guard file.lastPathComponent.matches("^[0-9a-f]{64}-[ad]$"), SafeFS.isRegular(try SafeFS.metadata(file)) else { return false }
            }
        }
        return true
    }
    func allowed(_ c: CleanupCandidate) -> Bool {
        let p = URL(fileURLWithPath:c.path)
        guard p.path == c.path, SafeFS.lexicalPath(c.path), c.path != config.home.path else { return false }
        let parent = p.deletingLastPathComponent()
        guard c.kind == .staticWebEntry || c.companionPaths.isEmpty else { return false }
        switch c.kind {
        case .aiCache: return aiCacheOwner(p) != nil && (try? SafeFS.metadata(p)).map(SafeFS.isDirectory) == true
        case .aiMetadataCache: return aiMetadataAllowed(p) && (try? SafeFS.metadata(p)).map(SafeFS.isRegular) == true
        case .claudeFileHistory, .claudeShellSnapshot, .codexShellSnapshot: return aiSnapshotAllowed(p,kind:c.kind)
        case .browserCache: return browserCacheAllowed(p) && (try? SafeFS.metadata(p)).map(SafeFS.isDirectory) == true
        case .quickLookCache: return p == quickLookRoot && (try? SafeFS.metadata(p)).map(SafeFS.isDirectory) == true
        case .helpCache: return helpRoots.contains(p) && (try? SafeFS.metadata(p)).map(SafeFS.isDirectory) == true
        case .diagnosticReport: return diagnosticAllowed(p) && (try? SafeFS.metadata(p)).map(SafeFS.isRegular) == true
        case .goCache:
            return p == config.home.appendingPathComponent("Library/Caches/go-build") || (config.temporaryRoots.contains(parent) && (p.lastPathComponent.lowercased().contains("cache") || p.lastPathComponent.lowercased().contains("go")))
        case .rustCache:
            return ["debug","release"].contains(parent.lastPathComponent) && parent.deletingLastPathComponent() == rustRoot && [".fingerprint","build","deps","examples","incremental"].contains(p.lastPathComponent)
        case .cursorSnapshots: return p == cursor.appendingPathComponent("snapshots")
        case .cursorSearchIndex: return parent == cursor.appendingPathComponent("User/globalStorage") && ["conversation-search.db","conversation-search.db-wal","conversation-search.db-shm"].contains(p.lastPathComponent)
        case .blenderBackup: return parent == backupRoot && backupScene(p) != nil
        case .stagingCopy:
            guard SafeFS.within(p.path,artifacts.path) else { return false }
            let relative = String(p.path.dropFirst(artifacts.path.count+1))
            return relative.matches("^[^/]+/(build/(darwin-arm64/mac-arm64|darwin-x64/mac|win32-x64/win-unpacked)|unpacked|windows-payload|windows-installer|packages/(mac|mac-arm64|win-unpacked))$")
        case .duplicatePackage:
            guard let ref = c.referencePath else { return false }
            let q = URL(fileURLWithPath:ref)
            return SafeFS.within(p.path,artifacts.path) && SafeFS.within(q.path,releases.path) && p.lastPathComponent == q.lastPathComponent && p.lastPathComponent.matches("^Lumi-[0-9].*\\.(exe|dmg|zip|apk)$")
        case .signingClone: return signingRoots.contains(parent) && p.lastPathComponent.matches("^code_sign_clone\\.[A-Za-z0-9]+$")
        case .obsoleteUpdate:
            return (parent == shipItRoot && p.lastPathComponent.matches("^update\\.[A-Za-z0-9]+$")) || (parent == telegramRoot && p.lastPathComponent.matches("^[A-Za-z0-9]+$"))
        case .staticWebEntry:
            guard SafeFS.within(p.path,webRoot.path) else { return false }
            let parts = String(p.path.dropFirst(webRoot.path.count+1)).split(separator:"/").map(String.init)
            guard parts.count == 3, parts[0].matches("^[0-9a-f]{40}$"), UUID(uuidString:parts[1]) != nil, parts[2].matches("^[0-9a-f]{16}_[01]$") else { return false }
            return c.companionPaths.allSatisfy { q in
                let u = URL(fileURLWithPath:q)
                return u.deletingLastPathComponent() == parent && u.lastPathComponent.matches("^[0-9a-f]{16}_[01]$") && u.lastPathComponent.prefix(16) == p.lastPathComponent.prefix(16)
            }
        }
    }
    func snapshot(_ p: URL, kind: CleanupKind, entries: Bool = false) throws -> TreeSnapshot {
        let tree = try SafeFS.snapshot(p, collectEntries:entries || kind.requiresStrictTree, skippingRootNames: kind == .goCache ? ["README","trim.txt","fuzz"] : [])
        if kind.requiresStrictTree {
            guard tree.entries.allSatisfy({ !SafeFS.isLink($0.identity) && $0.identity.owner == geteuid() }) else { throw CleanerError.unsafe(p.path) }
        }
        return tree
    }
    mutating func add(_ url: URL, kind: CleanupKind, category: CleanupCategory, reason: String, reference: URL? = nil, digest: String? = nil, kept: URL? = nil, companions: [URL] = []) {
        guard SafeFS.exists(url) else { return }
        do {
            var c = CleanupCandidate(path:url.path, category:category, kind:kind, reason:reason, referencePath:reference?.path, referenceDigest:digest, retainedPath:kept?.path)
            c.companionPaths = companions.map(\.path)
            guard allowed(c) else { throw CleanerError.unsafe(url.path) }
            if openFiles.uncertainAIRuntime(kind) { warnings.append(CleanerError.uncertainOccupancy(url.path).localizedDescription); return }
            if busy(kind,url.path) || companions.contains(where: { openFiles.contains($0.path) }) { warnings.append("正在使用，已跳过：\(url.path)"); return }
            if kind == .signingClone {
                let s = try SafeFS.snapshot(url)
                c.identity = s.identity; c.metadataFingerprint = s.fingerprint
                c.estimatedBytes = 0; c.fileCount = 1
            } else {
                let s = try snapshot(url,kind:kind)
                c.identity = s.identity; c.metadataFingerprint = s.fingerprint
                c.estimatedBytes = s.bytes; c.fileCount = s.fileCount
                for companion in companions { let s = try SafeFS.snapshot(companion); c.estimatedBytes += s.bytes; c.fileCount += s.fileCount; c.metadataFingerprint += ":" + s.fingerprint }
                guard c.fileCount > 0 else { return }
            }
            candidates.append(c)
        } catch { warnings.append(error.localizedDescription) }
    }
    mutating func scanGo() {
        var roots = [config.home.appendingPathComponent("Library/Caches/go-build")]
        for root in config.temporaryRoots {
            do { roots += try children(root).filter { $0.lastPathComponent.lowercased().contains("go") || $0.lastPathComponent.lowercased().contains("cache") } }
            catch { warnings.append(error.localizedDescription) }
        }
        for p in Set(roots).sorted(by: { $0.path < $1.path }) where SafeFS.exists(p) {
            do { if try goIsValid(p) { add(p,kind:.goCache,category:.compilation,reason:"可重新生成的 Go 编译缓存，保留 README 与模糊测试语料") } }
            catch { warnings.append(error.localizedDescription) }
        }
    }
    mutating func scanRustAndCursor() {
        for profile in ["debug","release"] { for name in [".fingerprint","build","deps","examples","incremental"] {
            add(rustRoot.appendingPathComponent(profile+"/"+name),kind:.rustCache,category:.compilation,reason:"Rust 编译中间文件，保留服务程序与源码")
        } }
        add(cursor.appendingPathComponent("snapshots"),kind:.cursorSnapshots,category:.cursor,reason:"Cursor 历史代码快照；保留设置、插件与登录数据")
        for name in ["conversation-search.db","conversation-search.db-wal","conversation-search.db-shm"] {
            add(cursor.appendingPathComponent("User/globalStorage/"+name),kind:.cursorSearchIndex,category:.cursor,reason:"可重建的聊天搜索索引")
        }
    }
    func backupScene(_ url: URL) -> String? {
        guard url.pathExtension == "blend" else { return nil }
        let stem=url.deletingPathExtension().lastPathComponent
        guard let range=stem.range(of:"-agent-[0-9]{8}-[0-9]{6}-[0-9]+$",options:.regularExpression),range.lowerBound != stem.startIndex else { return nil }
        return String(stem[..<range.lowerBound])
    }
    func newer(_ a: URL, _ b: URL) -> Bool {
        let lhs=try? SafeFS.metadata(a),rhs=try? SafeFS.metadata(b)
        if lhs?.modifiedSeconds != rhs?.modifiedSeconds { return (lhs?.modifiedSeconds ?? 0) > (rhs?.modifiedSeconds ?? 0) }
        if lhs?.modifiedNanoseconds != rhs?.modifiedNanoseconds { return (lhs?.modifiedNanoseconds ?? 0) > (rhs?.modifiedNanoseconds ?? 0) }
        return a.lastPathComponent > b.lastPathComponent
    }
    func backupGroups() throws -> [String:[URL]] {
        var groups: [String:[URL]] = [:]
        for p in try children(backupRoot) {
            let c = CleanupCandidate(path:p.path,category:.blender,kind:.blenderBackup,reason:"")
            guard allowed(c), SafeFS.isRegular(try SafeFS.metadata(p)) else { continue }
            guard let scene = backupScene(p) else { continue }
            groups[scene,default:[]].append(p)
        }
        for key in Array(groups.keys) {
            groups[key] = groups[key]!.sorted {
                let a = try? SafeFS.metadata($0), b = try? SafeFS.metadata($1)
                if a?.modifiedSeconds != b?.modifiedSeconds { return (a?.modifiedSeconds ?? 0) > (b?.modifiedSeconds ?? 0) }
                if a?.modifiedNanoseconds != b?.modifiedNanoseconds { return (a?.modifiedNanoseconds ?? 0) > (b?.modifiedNanoseconds ?? 0) }
                return $0.lastPathComponent > $1.lastPathComponent
            }
        }
        return groups
    }
    mutating func scanBlender() {
        do { for files in try backupGroups().values {
            guard let latest = files.first else { continue }; retained.append(latest.path)
            for p in files.dropFirst() { add(p,kind:.blenderBackup,category:.blender,reason:"旧场景备份；同场景最新 1 份始终保留",kept:latest) }
        } } catch { warnings.append(error.localizedDescription) }
    }
    func packageFiles(_ root: URL, skipping: [URL] = []) throws -> [URL] {
        var result: [URL] = []
        func walk(_ p: URL) throws {
            for child in try children(p) where !skipping.contains(child) {
                let m = try SafeFS.metadata(child)
                if SafeFS.isDirectory(m) { try walk(child) }
                else if SafeFS.isRegular(m), child.lastPathComponent.matches("^Lumi-[0-9].*\\.(exe|dmg|zip|apk)$") { result.append(child) }
            }
        }
        try walk(root); return result
    }
    mutating func scanPackaging() {
        var stages: [URL] = []
        do {
            for p in try children(artifacts) where SafeFS.isDirectory(try SafeFS.metadata(p)) {
                if p.lastPathComponent.hasPrefix("packaging-") {
                    for name in ["darwin-arm64/mac-arm64","darwin-x64/mac","win32-x64/win-unpacked"] {
                        let q=p.appendingPathComponent("build/"+name); if SafeFS.exists(q) { stages.append(q) }
                    }
                }
                for name in ["unpacked","windows-payload","windows-installer","packages/mac","packages/mac-arm64","packages/win-unpacked"] {
                    let q=p.appendingPathComponent(name); if SafeFS.exists(q) { stages.append(q) }
                }
            }
            stages = stages.filter { p in !stages.contains { $0 != p && SafeFS.within(p.path,$0.path) } }
            for p in stages { add(p,kind:.stagingCopy,category:.temporary,reason:"打包解压与验证副本；保留正式安装包和验证记录") }
            let refs = try packageFiles(releases)
            var digests: [URL:String] = [:]
            for p in try packageFiles(artifacts,skipping:stages) {
                let m = try SafeFS.metadata(p)
                let options = refs.filter { $0.lastPathComponent == p.lastPathComponent && (try? SafeFS.metadata($0).size) == m.size }
                guard !options.isEmpty else { continue }
                let hash = try SafeFS.digest(p)
                for q in options {
                    if digests[q] == nil { digests[q] = try SafeFS.digest(q) }
                    if digests[q] == hash { add(p,kind:.duplicatePackage,category:.temporary,reason:"与正式发布文件内容完全相同的副本",reference:q,digest:hash); break }
                }
            }
        } catch { warnings.append(error.localizedDescription) }
    }
    func validClone(_ p: URL) throws -> Bool {
        let contents = try children(p)
        guard contents.count == 1, contents[0].lastPathComponent.hasSuffix(".app.bundle") else { return false }
        let data = try SafeFS.readPrefix(contents[0].appendingPathComponent("Contents/Info.plist"),limit:1024*1024)
        guard let d = try PropertyListSerialization.propertyList(from:data,format:nil) as? [String:Any], let id = d["CFBundleIdentifier"] as? String else { return false }
        return p.deletingLastPathComponent().lastPathComponent == id + ".code_sign_clone"
    }
    mutating func scanSigning() {
        for root in signingRoots {
            do {
                let files = try children(root).filter { $0.lastPathComponent.matches("^code_sign_clone\\.[A-Za-z0-9]+$") }.sorted(by:newer)
                for p in files.dropFirst(2) {
                    let m = try SafeFS.metadata(p)
                    if SafeFS.isDirectory(m), Date().timeIntervalSince1970 - Double(m.modifiedSeconds) > 300, try validClone(p) {
                        add(p,kind:.signingClone,category:.temporary,reason:"闲置应用签名副本；共享占用不计入空间估算，保留最新 2 份")
                    }
                }
            } catch { warnings.append(error.localizedDescription) }
        }
    }
    func telegramDownloads() throws -> [(URL,Int,Int64)] {
        var rows: [(URL,Int,Int64)] = []
        for root in try children(telegramRoot) where SafeFS.isDirectory(try SafeFS.metadata(root)) {
            for p in try children(root) {
                let plist = p.appendingPathComponent("Telegram.app/Contents/Info.plist"), zip=p.appendingPathComponent("Telegram.app.zip")
                if SafeFS.exists(plist), SafeFS.exists(zip) {
                    let data = try SafeFS.readPrefix(plist,limit:1024*1024)
                    if let d = try PropertyListSerialization.propertyList(from:data,format:nil) as? [String:Any], let build = d["CFBundleVersion"] as? String, let number = Int(build) {
                        rows.append((root,number,try SafeFS.metadata(zip).modifiedSeconds))
                    }
                }
            }
        }
        return rows.sorted { a,b in a.1 != b.1 ? a.1>b.1 : a.2>b.2 }
    }
    func obsoleteUpdate(_ p: URL) throws -> Bool {
        if p.deletingLastPathComponent() == shipItRoot {
            let cached = p.appendingPathComponent("Cursor.app")
            let installed = config.applicationsRoot.appendingPathComponent("Cursor.app")
            return try version(cached).lexicographicallyPrecedes(version(installed))
        }
        let rows = try telegramDownloads()
        guard let latest = rows.first, latest.0 != p, let row=rows.first(where:{$0.0==p}) else { return false }
        if row.1 < latest.1 { return true }
        let zip1 = try children(p).map { $0.appendingPathComponent("Telegram.app.zip") }.first { SafeFS.exists($0) }
        let zip2 = try children(latest.0).map { $0.appendingPathComponent("Telegram.app.zip") }.first { SafeFS.exists($0) }
        guard let a=zip1,let b=zip2 else { return false }
        return try SafeFS.digest(a) == SafeFS.digest(b)
    }
    mutating func scanUpdates() {
        do {
            for p in try children(shipItRoot) where p.lastPathComponent.hasPrefix("update.") {
                if try obsoleteUpdate(p) { add(p,kind:.obsoleteUpdate,category:.updates,reason:"已安装更高版本，旧版 Cursor 更新下载可清理") }
            }
            for row in try telegramDownloads().dropFirst() {
                if try obsoleteUpdate(row.0) { add(row.0,kind:.obsoleteUpdate,category:.updates,reason:"重复或已过时的 Telegram 更新下载；保留最新下载") }
            }
        } catch { warnings.append(error.localizedDescription) }
    }
}
