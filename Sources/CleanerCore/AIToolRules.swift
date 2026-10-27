import Foundation

// This catalog grants access only to named, regenerable cache leaves. Product
// roots, website stores, models, worktrees and artifact sessions are never grants.
struct AITool {
    var aliases: Set<String>
    var appNames: Set<String>
    var identifiers: Set<String>
    var cliNames: Set<String>
    static let known: [AITool] = [
        .init(aliases:["Claude"],appNames:["Claude.app"],identifiers:[],cliNames:["claude","Claude"]),
        .init(aliases:["Codex","ChatGPT"],appNames:["Codex.app","ChatGPT.app"],identifiers:["com.openai.codex"],cliNames:["codex"]),
        .init(aliases:["Cursor"],appNames:["Cursor.app"],identifiers:["com.todesktop.230313mzl4w4u92"],cliNames:["cursor"]),
        .init(aliases:["Trae","Trae CN"],appNames:["Trae.app","Trae CN.app"],identifiers:["com.trae.app"],cliNames:["trae"]),
        .init(aliases:["Windsurf"],appNames:["Windsurf.app"],identifiers:[],cliNames:["windsurf"]),
        .init(aliases:["Gemini"],appNames:["Gemini.app"],identifiers:["com.google.GeminiMacOS"],cliNames:["gemini"]),
        .init(aliases:["Cherry Studio","CherryStudio"],appNames:["Cherry Studio.app","CherryStudio.app"],identifiers:[],cliNames:["cherry-studio"]),
        .init(aliases:["Ollama"],appNames:["Ollama.app"],identifiers:["com.electron.ollama"],cliNames:["ollama"]),
        .init(aliases:["LM Studio"],appNames:["LM Studio.app"],identifiers:[],cliNames:["lm-studio"]),
        .init(aliases:["Doubao","豆包"],appNames:["Doubao.app","豆包.app"],identifiers:[],cliNames:["doubao"]),
        .init(aliases:["Qianwen","Qwen","千问","通义"],appNames:["Qianwen.app","Qwen.app","千问.app","通义.app"],identifiers:[],cliNames:["qwen"])
    ]
    static func safeComponent(_ name: String) -> Bool {
        !name.isEmpty && name.utf8.count <= 200 && name != "." && name != ".." && !name.hasPrefix(".") &&
        !name.contains(where: { $0 == "/" || $0 == "\\" || $0 == ":" || $0.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) }) &&
        !["Library","Caches","Application Support"].contains(name) && !name.lowercased().hasPrefix("com.apple.")
    }
    static func safeIdentifier(_ value: String) -> Bool {
        value.utf8.count <= 200 && value.matches("^[A-Za-z][A-Za-z0-9-]*(\\.[A-Za-z0-9][A-Za-z0-9-]*){2,}$") &&
        value.lowercased() != "com.apple" && !value.lowercased().hasPrefix("com.apple.")
    }
    static func discover(_ config: CleanerConfiguration) -> [AITool] {
        var tools=known
        for root in Set([config.applicationsRoot,config.home.appendingPathComponent("Applications")]) {
            guard let apps=try? SafeFS.children(root) else { continue }
            for app in apps where app.pathExtension == "app" {
                guard let m=try? SafeFS.metadata(app),SafeFS.isDirectory(m),
                      let data=try? SafeFS.readPrefix(app.appendingPathComponent("Contents/Info.plist"),limit:1024*1024),
                      let values=(try? PropertyListSerialization.propertyList(from:data,format:nil)) as? [String:Any] else { continue }
                let identifier=values["CFBundleIdentifier"] as? String
                guard let index=tools.firstIndex(where: { $0.appNames.contains(app.lastPathComponent) || (identifier.map($0.identifiers.contains) ?? false) }) else { continue }
                tools[index].appNames.insert(app.lastPathComponent)
                if let identifier, safeIdentifier(identifier) { tools[index].identifiers.insert(identifier) }
                for key in ["CFBundleName","CFBundleDisplayName","CFBundleExecutable"] {
                    if let alias=values[key] as? String,safeComponent(alias) { tools[index].aliases.insert(alias) }
                }
            }
        }
        return tools
    }
    func ownsCache(_ path: URL, home: URL) -> Bool {
        for alias in aliases {
            for location in ["Library/Application Support/","Library/Caches/"] {
                if CacheLayout.relative(path,to:home.appendingPathComponent(location+alias)).map(CacheLayout.allowedAI) == true { return true }
            }
        }
        return identifiers.contains { path == home.appendingPathComponent("Library/Caches/"+$0+"/fsCachedData") }
    }
}

enum CacheLayout {
    static let names: Set<String> = ["Cache","Code Cache","GPUCache","DawnCache","DawnGraphiteCache","DawnWebGPUCache","GraphiteDawnCache","GrShaderCache","ShaderCache"]
    static func relative(_ path:URL,to root:URL) -> [String]? {
        guard path != root,SafeFS.within(path.path,root.path) else { return nil }
        return String(path.path.dropFirst(root.path.count+1)).split(separator:"/").map(String.init)
    }
    static func profile(_ name:String) -> Bool { name == "Default" || name.matches("^Profile [0-9]+$") }
    static func partition(_ name:String) -> Bool { name.matches("^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$") }
    static func allowedAI(_ parts:[String]) -> Bool {
        guard let leaf=parts.last,names.contains(leaf) else { return false }
        let base=Array(parts.dropLast())
        return base.isEmpty || (base.count == 1 && profile(base[0])) ||
            (base.count == 2 && base[0] == "Partitions" && partition(base[1])) ||
            (base.count == 3 && profile(base[0]) && base[1] == "Partitions" && partition(base[2]))
    }
    static func directories(_ root:URL) throws -> [URL] {
        guard SafeFS.exists(root) else { return [] }
        var bases=[root]
        for p in try SafeFS.children(root) where profile(p.lastPathComponent) {
            if SafeFS.isDirectory(try SafeFS.metadata(p)) { bases.append(p) }
        }
        for base in bases {
            let partitions=base.appendingPathComponent("Partitions")
            guard SafeFS.exists(partitions) else { continue }
            for p in try SafeFS.children(partitions) where partition(p.lastPathComponent) {
                if SafeFS.isDirectory(try SafeFS.metadata(p)) { bases.append(p) }
            }
        }
        return bases.flatMap { base in names.sorted().map { base.appendingPathComponent($0) } }
    }
}

struct AISnapshotRecord {
    let url: URL
    let newest: FileIdentity
}

extension CleanupRules {
    func aiCacheOwner(_ path:URL) -> AITool? { aiProducts.first { $0.ownsCache(path,home:config.home) } }
    func aiMetadataAllowed(_ path:URL) -> Bool {
        if path == config.home.appendingPathComponent(".claude/cache/changelog.md") { return true }
        let parent=path.deletingLastPathComponent()
        return parent.deletingLastPathComponent() == config.home.appendingPathComponent(".codex/cache") &&
            ["codex_app_directory","codex_apps_server_info","codex_apps_tools","remote_plugin_catalog","bundled_plugin_exclusions"].contains(parent.lastPathComponent) &&
            path.lastPathComponent.matches("^([0-9a-f]{16}|[0-9a-f]{40}|[0-9a-f]{64})\\.json$")
    }
    func snapshotRoot(_ kind:CleanupKind) -> URL? {
        switch kind {
        case .claudeFileHistory: return config.home.appendingPathComponent(".claude/file-history")
        case .claudeShellSnapshot: return config.home.appendingPathComponent(".claude/shell-snapshots")
        case .codexShellSnapshot: return config.home.appendingPathComponent(".codex/shell_snapshots")
        default: return nil
        }
    }
    func snapshotName(_ name:String,kind:CleanupKind) -> Bool {
        switch kind {
        case .claudeFileHistory: return UUID(uuidString:name) != nil
        case .claudeShellSnapshot: return name.matches("^snapshot-(bash|zsh|sh)-[0-9]{10,16}-[A-Za-z0-9_-]+\\.sh$")
        case .codexShellSnapshot:
            guard name.matches("^[0-9A-Fa-f-]{36}(\\.[A-Za-z0-9_-]{1,64})?\\.(sh|ps1)$") else { return false }
            return UUID(uuidString:String(name.prefix(36))) != nil
        default: return false
        }
    }
    func aiSnapshotAllowed(_ path:URL,kind:CleanupKind) -> Bool {
        guard let root=snapshotRoot(kind),path.deletingLastPathComponent() == root else { return false }
        return snapshotName(path.lastPathComponent,kind:kind)
    }
    func snapshotGroups(_ kind:CleanupKind) throws -> [String:[AISnapshotRecord]] {
        guard let root=snapshotRoot(kind) else { return [:] }
        var groups:[String:[AISnapshotRecord]]=[:]
        for path in try children(root) where snapshotName(path.lastPathComponent,kind:kind) {
            let tree=try snapshot(path,kind:kind,entries:true)
            guard kind == .claudeFileHistory ? SafeFS.isDirectory(tree.identity) : SafeFS.isRegular(tree.identity) else { throw CleanerError.unsafe(path.path) }
            var newest=tree.identity
            for entry in tree.entries {
                let m=entry.identity
                if m.modifiedSeconds > newest.modifiedSeconds || (m.modifiedSeconds == newest.modifiedSeconds && m.modifiedNanoseconds > newest.modifiedNanoseconds) { newest=m }
            }
            let key=kind == .codexShellSnapshot ? String(path.lastPathComponent.prefix(36)).lowercased() : "all"
            groups[key,default:[]].append(AISnapshotRecord(url:path,newest:newest))
        }
        for key in Array(groups.keys) {
            groups[key]?.sort { a,b in
                if a.newest.modifiedSeconds != b.newest.modifiedSeconds { return a.newest.modifiedSeconds > b.newest.modifiedSeconds }
                if a.newest.modifiedNanoseconds != b.newest.modifiedNanoseconds { return a.newest.modifiedNanoseconds > b.newest.modifiedNanoseconds }
                return a.url.path > b.url.path
            }
        }
        return groups
    }
    func oldEnough(_ m:FileIdentity,days:Double) -> Bool {
        Date().timeIntervalSince1970 - (Double(m.modifiedSeconds)+Double(m.modifiedNanoseconds)/1_000_000_000) > days*86400
    }
    func aiSnapshotEligible(_ url:URL,kind:CleanupKind) throws -> Bool {
        guard aiSnapshotAllowed(url,kind:kind) else { return false }
        for files in try snapshotGroups(kind).values {
            guard files.count > 1 else { continue }
            if let record=files.dropFirst().first(where:{$0.url == url}) { return oldEnough(record.newest,days:kind == .claudeFileHistory ? 30 : 7) }
        }
        return false
    }
    mutating func scanAITools() {
        for product in aiProducts {
            for alias in product.aliases.sorted() {
                for location in ["Library/Application Support/","Library/Caches/"] {
                    do {
                        for cache in try CacheLayout.directories(config.home.appendingPathComponent(location+alias)) {
                            add(cache,kind:.aiCache,category:.cursor,reason:"AI 工具可重新生成的 HTTP、代码与 GPU 着色器缓存；保留聊天与登录数据")
                        }
                    } catch { warnings.append(error.localizedDescription) }
                }
            }
            for identifier in product.identifiers.sorted() {
                add(config.home.appendingPathComponent("Library/Caches/"+identifier+"/fsCachedData"),kind:.aiCache,category:.cursor,reason:"AI 工具原生网络缓存；保留 Cookie、数据库与设置")
            }
        }
        for directory in ["codex_app_directory","codex_apps_server_info","codex_apps_tools","remote_plugin_catalog","bundled_plugin_exclusions"] {
            do {
                for path in try children(config.home.appendingPathComponent(".codex/cache/"+directory)) where aiMetadataAllowed(path) {
                    add(path,kind:.aiMetadataCache,category:.cursor,reason:"可重新获取的 Codex 工具与插件目录元数据")
                }
            } catch { warnings.append(error.localizedDescription) }
        }
        add(config.home.appendingPathComponent(".claude/cache/changelog.md"),kind:.aiMetadataCache,category:.cursor,reason:"可重新获取的 Claude 更新说明")
        for kind in [CleanupKind.claudeFileHistory,.claudeShellSnapshot,.codexShellSnapshot] {
            do {
                for files in try snapshotGroups(kind).values {
                    guard let latest=files.first else { continue };retained.append(latest.url.path)
                    for record in files.dropFirst() where oldEnough(record.newest,days:kind == .claudeFileHistory ? 30 : 7) {
                        add(record.url,kind:kind,category:.cursor,reason:kind == .claudeFileHistory ? "超过 30 天的 Claude 文件历史；保留最近更新的历史组" : "超过 7 天的终端环境快照；保留最新快照",kept:latest.url)
                    }
                }
            } catch { warnings.append(error.localizedDescription) }
        }
    }
    func aiArtifactOwner(_ kind:CleanupKind,_ path:URL) -> AITool? {
        let command: String
        switch kind {
        case .aiCache: return aiCacheOwner(path)
        case .claudeFileHistory,.claudeShellSnapshot: command = "claude"
        case .codexShellSnapshot: command = "codex"
        case .cursorSnapshots,.cursorSearchIndex: command = "cursor"
        case .aiMetadataCache:
            if SafeFS.within(path.path,config.home.appendingPathComponent(".claude/cache").path) { command = "claude" }
            else if SafeFS.within(path.path,config.home.appendingPathComponent(".codex/cache").path) { command = "codex" }
            else { return nil }
        default: return nil
        }
        return aiProducts.first { $0.cliNames.contains(command) }
    }
    func busy(_ kind:CleanupKind,_ path:String,state:OpenFileState? = nil) -> Bool {
        let occupancy=state ?? openFiles
        if occupancy.busy(kind,path) { return true }
        guard let owner=aiArtifactOwner(kind,URL(fileURLWithPath:path)) else { return false }
        return occupancy.running(appNames:owner.appNames,cliNames:owner.cliNames) ||
            (owner.cliNames.contains("claude") && occupancy.runningNativeClaude(home:config.home))
    }

}

extension OpenFileState {
    func running(appNames:Set<String>,cliNames:Set<String> = []) -> Bool {
        commands.contains { command in
            let url=URL(fileURLWithPath:command)
            return cliNames.contains(url.lastPathComponent) || url.pathComponents.contains(where:appNames.contains)
        }
    }
    func uncertainAIRuntime(_ kind:CleanupKind) -> Bool {
        guard [.claudeFileHistory,.claudeShellSnapshot,.codexShellSnapshot,.aiMetadataCache].contains(kind) else { return false }
        // comm does not reveal which script an interpreter is running. Avoid
        // guessing ownership from arbitrary project names or reading arguments.
        return running(appNames:[],cliNames:["node","nodejs","bun"])
    }
    func runningNativeClaude(home:URL) -> Bool {
        let root=home.appendingPathComponent(".local/share/claude/versions")
        return commands.contains { command in
            guard SafeFS.lexicalPath(command),let parts=CacheLayout.relative(URL(fileURLWithPath:command),to:root),parts.count == 1 else { return false }
            return parts[0].matches("^[0-9]+\\.[0-9]+\\.[0-9]+(-[A-Za-z0-9.-]+)?$")
        }
    }
    func busyAIOrDaily(_ kind:CleanupKind,_ path:String) -> Bool {
        if uncertainAIRuntime(kind) { return true }
        let parts=URL(fileURLWithPath:path).pathComponents
        switch kind {
        case .claudeFileHistory,.claudeShellSnapshot:
            return running(appNames:["Claude.app"],cliNames:["claude","Claude"])
        case .codexShellSnapshot:
            return running(appNames:["Codex.app","ChatGPT.app"],cliNames:["codex"])
        case .aiMetadataCache:
            return parts.contains(".claude") ? running(appNames:["Claude.app"],cliNames:["claude","Claude"]) : running(appNames:["Codex.app","ChatGPT.app"],cliNames:["codex"])
        case .aiCache:
            return AITool.known.contains { tool in
                (!tool.aliases.isDisjoint(with:parts) || !tool.identifiers.isDisjoint(with:parts)) && running(appNames:tool.appNames,cliNames:tool.cliNames)
            }
        case .browserCache:
            if parts.contains("Firefox") { return running(appNames:["Firefox.app"],cliNames:["firefox"]) }
            if parts.contains("Microsoft Edge") { return running(appNames:["Microsoft Edge.app"],cliNames:["Microsoft Edge"]) }
            if parts.contains("Brave-Browser") { return running(appNames:["Brave Browser.app"],cliNames:["Brave Browser"]) }
            return running(appNames:["Google Chrome.app"],cliNames:["Google Chrome"])
        case .quickLookCache:
            return running(appNames:[],cliNames:["qlmanage","quicklookd","QuickLookUIService","QuickLookSatellite","ThumbnailsAgent","quicklook.ui.helper","com.apple.quicklook.ThumbnailsAgent","com.apple.quicklook.QuickLookUIService","com.apple.quicklook.ui.helper"])
        case .helpCache: return running(appNames:["HelpViewer.app"],cliNames:["helpd","HelpViewer"])
        default: return false
        }
    }
}
