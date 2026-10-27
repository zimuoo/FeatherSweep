import Foundation

public enum CleanupCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case compilation, cursor, temporary, updates, webCache, blender, daily
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .compilation: return "Go / Rust 编译缓存"
        case .cursor: return "AI 缓存与旧快照"
        case .temporary: return "打包与签名副本"
        case .updates: return "过期更新下载"
        case .webCache: return "应用静态缓存"
        case .blender: return "Blender 旧备份"
        case .daily: return "日常缓存与诊断"
        }
    }
}

public enum CleanupKind: String, Codable, Sendable {
    case goCache, rustCache, cursorSnapshots, cursorSearchIndex
    case stagingCopy, duplicatePackage, signingClone, obsoleteUpdate
    case staticWebEntry, blenderBackup
    case aiCache, aiMetadataCache, claudeFileHistory, claudeShellSnapshot, codexShellSnapshot
    case browserCache, quickLookCache, helpCache, diagnosticReport

    var requiresStrictTree: Bool {
        switch self {
        case .aiCache, .aiMetadataCache, .claudeFileHistory, .claudeShellSnapshot, .codexShellSnapshot, .browserCache, .quickLookCache, .helpCache, .diagnosticReport: return true
        default: return false
        }
    }
}

public struct FileIdentity: Codable, Equatable, Sendable {
    public var device: UInt64
    public var inode: UInt64
    public var size: Int64
    public var modifiedSeconds: Int64
    public var modifiedNanoseconds: Int64
    public var mode: UInt32
    public var owner: UInt32
}

public struct CleanupCandidate: Codable, Identifiable, Sendable {
    public var id: String { path }
    public var path: String
    public var category: CleanupCategory
    public var kind: CleanupKind
    public var reason: String
    public var estimatedBytes: Int64
    public var fileCount: Int
    public var identity: FileIdentity?
    public var metadataFingerprint: String
    public var companionPaths: [String]
    public var referencePath: String?
    public var referenceDigest: String?
    public var retainedPath: String?

    public var impactTitle: String {
        switch kind {
        case .goCache, .rustCache: return "下次编译会重新生成缓存"
        case .cursorSnapshots, .claudeFileHistory: return "减少历史代码恢复能力"
        case .claudeShellSnapshot, .codexShellSnapshot: return "旧终端环境快照将无法恢复"
        case .cursorSearchIndex: return "聊天搜索索引需要重建"
        case .stagingCopy, .duplicatePackage: return "保留正式安装包"
        case .signingClone: return "再次签名时重新创建副本"
        case .obsoleteUpdate: return "以后更新可能需要重新下载"
        case .staticWebEntry, .aiCache, .browserCache: return "首次打开可能稍慢"
        case .aiMetadataCache: return "工具元数据会重新获取"
        case .blenderBackup: return "旧场景备份将无法恢复"
        case .quickLookCache: return "文件缩略图会重新生成"
        case .helpCache: return "帮助内容与索引会重新缓存"
        case .diagnosticReport: return "失去这份旧故障诊断信息"
        }
    }
    public var impactDetail: String {
        switch kind {
        case .goCache: return "保留源码与模糊测试语料；下一次 Go 编译会花时间重新生成构建结果。"
        case .rustCache: return "保留源码与服务程序；下一次 Rust 构建需要重新编译依赖和中间文件。"
        case .cursorSnapshots: return "删除 Cursor 历史代码快照后，相关旧版本不能再从快照恢复；当前源码、聊天、设置与插件保留。"
        case .cursorSearchIndex: return "已有聊天内容保留，Cursor 可能需要重新建立聊天搜索索引。"
        case .stagingCopy: return "删除打包解压和验证用副本，正式安装包与验证记录保留；再次打包时重新生成。"
        case .duplicatePackage: return "只删除与正式发布文件内容完全相同的副本；已核对的正式安装包保留。"
        case .signingClone: return "删除闲置签名副本，正式应用保留；下次签名时会重新创建，空间估算不计共享文件。"
        case .obsoleteUpdate: return "已安装应用保留；旧更新下载被删除后，再次需要该版本时须重新下载。"
        case .staticWebEntry: return "飞书或 Cloudflare 静态资源需要重新下载；Cookie、登录会话与网站存储保留。"
        case .aiCache: return "HTTP、代码或 GPU 着色器缓存会重新下载或编译；首次启动可能较慢，聊天、登录、设置、技能、插件与模型保留。"
        case .aiMetadataCache: return "Codex 工具目录、插件目录元数据或 Claude 更新说明会重新获取；身份凭据、配置、技能与插件文件保留。"
        case .claudeFileHistory: return "删除超过 30 天的 Claude 文件历史组会减少对应代码的回退版本；保留最新历史组、当前项目源码与聊天。"
        case .claudeShellSnapshot: return "删除超过 7 天的 Claude 终端快照后无法恢复该旧环境；最新一份、终端配置与项目文件保留。"
        case .codexShellSnapshot: return "删除超过 7 天的 Codex 终端快照后无法恢复该旧环境；每个会话最新一份、聊天、配置与工作树保留。"
        case .browserCache: return "网页资源会重新下载，代码和 GPU 着色器缓存会重建；首次加载可能较慢，密码、Cookie、登录会话及网站存储保留。"
        case .quickLookCache: return "Finder 和快速查看中的文件缩略图会按需重新生成，首次预览可能稍慢；原始文件保留。"
        case .helpCache: return "系统帮助内容与生成的帮助索引会按需重建，首次打开帮助可能稍慢；帮助设置保留。"
        case .diagnosticReport: return "删除超过 7 天的崩溃、卡顿或诊断报告，之后无法用这份报告排查旧故障；应用数据与近期报告保留。"
        case .blenderBackup: return "这份旧场景备份将无法恢复；同场景最新一份备份与原始工程保留。"
        }
    }

    public init(path: String, category: CleanupCategory, kind: CleanupKind, reason: String,
                estimatedBytes: Int64 = 0, fileCount: Int = 1, identity: FileIdentity? = nil,
                metadataFingerprint: String = "", companionPaths: [String] = [],
                referencePath: String? = nil, referenceDigest: String? = nil, retainedPath: String? = nil) {
        self.path = path; self.category = category; self.kind = kind; self.reason = reason
        self.estimatedBytes = estimatedBytes; self.fileCount = fileCount; self.identity = identity
        self.metadataFingerprint = metadataFingerprint; self.companionPaths = companionPaths
        self.referencePath = referencePath; self.referenceDigest = referenceDigest; self.retainedPath = retainedPath
    }
}

public struct ScanReport: Codable, Sendable {
    public var candidates: [CleanupCandidate]
    public var warnings: [String]
    public var scannedAt: Date
    public var availableBytes: Int64
    public var retainedBackups: [String]
    public var totalBytes: Int64 { candidates.reduce(0) { $0 + $1.estimatedBytes } }
    public func selecting(_ ids: Set<String>) -> ScanReport {
        var selected = self
        selected.candidates = candidates.filter { ids.contains($0.id) }
        return selected
    }
    public init(candidates: [CleanupCandidate] = [], warnings: [String] = [], scannedAt: Date = Date(),
                availableBytes: Int64 = 0, retainedBackups: [String] = []) {
        self.candidates = candidates; self.warnings = warnings; self.scannedAt = scannedAt
        self.availableBytes = availableBytes; self.retainedBackups = retainedBackups
    }
}

public struct CleanupResult: Codable, Sendable {
    public var removedBytes: Int64
    public var availableBytesBefore: Int64
    public var availableBytesAfter: Int64
    public var removedCount: Int
    public var partialCount: Int
    public var skipped: [String]
    public var failed: [String]
    public var freedBytes: Int64 { max(0, availableBytesAfter - availableBytesBefore) }
    public init(removedBytes: Int64, availableBytesBefore: Int64, availableBytesAfter: Int64,
                removedCount: Int, skipped: [String] = [], failed: [String] = [], partialCount: Int = 0) {
        self.removedBytes = removedBytes; self.availableBytesBefore = availableBytesBefore
        self.availableBytesAfter = availableBytesAfter; self.removedCount = removedCount
        self.skipped = skipped; self.failed = failed; self.partialCount = partialCount
    }
}
