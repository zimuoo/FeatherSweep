import Foundation

extension CleanupRules {
    static let browserAliases = ["Google/Chrome","Microsoft Edge","BraveSoftware/Brave-Browser"]
    var quickLookRoot: URL { config.home.appendingPathComponent("Library/Caches/com.apple.QuickLook.thumbnailcache") }
    var helpRoots: [URL] { ["fsCachedData","Generated"].map { config.home.appendingPathComponent("Library/Caches/com.apple.helpd/"+$0) } }
    var diagnosticRoot: URL { config.home.appendingPathComponent("Library/Logs/DiagnosticReports") }
    func browserCacheAllowed(_ path:URL) -> Bool {
        for alias in Self.browserAliases {
            if let parts=CacheLayout.relative(path,to:config.home.appendingPathComponent("Library/Application Support/"+alias)),
               parts.count == 2,CacheLayout.profile(parts[0]),CacheLayout.names.contains(parts[1]) { return true }
            if let parts=CacheLayout.relative(path,to:config.home.appendingPathComponent("Library/Caches/"+alias)),parts.count >= 2,CacheLayout.profile(parts[0]) {
                let tail=Array(parts.dropFirst())
                if tail == ["Cache","Cache_Data"] || tail == ["Cache_Data"] || (tail.count == 1 && CacheLayout.names.subtracting(["Cache"]).contains(tail[0])) { return true }
            }
        }
        guard let parts=CacheLayout.relative(path,to:config.home.appendingPathComponent("Library/Caches/Firefox/Profiles")) else { return false }
        return parts.count == 2 && CacheLayout.partition(parts[0]) && parts[1] == "cache2"
    }
    func diagnosticAllowed(_ path:URL) -> Bool {
        path.deletingLastPathComponent() == diagnosticRoot && ["ips","crash","diag","hang","spin"].contains(path.pathExtension) && AITool.safeComponent(path.lastPathComponent)
    }
    func dailyEligible(_ path:URL,kind:CleanupKind) throws -> Bool {
        if kind == .diagnosticReport { let m=try SafeFS.metadata(path);return SafeFS.isRegular(m) && oldEnough(m,days:7) }
        return true
    }
    mutating func scanDaily() {
        for alias in Self.browserAliases {
            for location in ["Library/Application Support/","Library/Caches/"] {
                let root=config.home.appendingPathComponent(location+alias)
                do {
                    for profile in try children(root) where CacheLayout.profile(profile.lastPathComponent) {
                        guard SafeFS.isDirectory(try SafeFS.metadata(profile)) else { continue }
                        let names=location == "Library/Caches/" ? CacheLayout.names.subtracting(["Cache"]).union(["Cache/Cache_Data","Cache_Data"]) : CacheLayout.names
                        for name in names.sorted() { add(profile.appendingPathComponent(name),kind:.browserCache,category:.daily,reason:"浏览器可重新下载或编译的缓存；保留密码、Cookie、会话与网站存储") }
                    }
                } catch { warnings.append(error.localizedDescription) }
            }
        }
        do {
            let root=config.home.appendingPathComponent("Library/Caches/Firefox/Profiles")
            for profile in try children(root) where CacheLayout.partition(profile.lastPathComponent) {
                guard SafeFS.isDirectory(try SafeFS.metadata(profile)) else { continue }
                add(profile.appendingPathComponent("cache2"),kind:.browserCache,category:.daily,reason:"Firefox 可重新下载的网页缓存；保留登录与网站数据")
            }
        } catch { warnings.append(error.localizedDescription) }
        add(quickLookRoot,kind:.quickLookCache,category:.daily,reason:"按需重新生成的用户文件缩略图缓存")
        for path in helpRoots { add(path,kind:.helpCache,category:.daily,reason:"系统帮助下载缓存与生成的帮助索引") }
        do {
            for path in try children(diagnosticRoot) where diagnosticAllowed(path) {
                if try dailyEligible(path,kind:.diagnosticReport) { add(path,kind:.diagnosticReport,category:.daily,reason:"超过 7 天的故障诊断报告；保留近期诊断与其他日志") }
            }
        } catch { warnings.append(error.localizedDescription) }
    }
}
