import Foundation

public enum CleanupCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case compilation, cursor, temporary, updates, webCache, blender
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .compilation: return "Go / Rust 编译缓存"
        case .cursor: return "Cursor 旧快照"
        case .temporary: return "打包与签名副本"
        case .updates: return "过期更新下载"
        case .webCache: return "应用静态缓存"
        case .blender: return "Blender 旧备份"
        }
    }
}

public enum CleanupKind: String, Codable, Sendable {
    case goCache, rustCache, cursorSnapshots, cursorSearchIndex
    case stagingCopy, duplicatePackage, signingClone, obsoleteUpdate
    case staticWebEntry, blenderBackup
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
