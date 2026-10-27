import Foundation
import CryptoKit
import Darwin

public enum CleanerError: LocalizedError {
    case unsafe(String), changed(String), busy(String), uncertainOccupancy(String), system(String), staleScan
    public var errorDescription: String? {
        switch self {
        case .unsafe(let p): return "不在清理规则内或包含不安全路径：\(p)"
        case .changed(let p): return "扫描后内容发生变化，已跳过：\(p)"
        case .busy(let p): return "正在使用，已跳过：\(p)"
        case .uncertainOccupancy(let p): return "存在未识别的 Node / Bun 进程，无法确认 AI 快照或目录缓存闲置，已安全跳过：\(p)"
        case .system(let p): return p
        case .staleScan: return "扫描结果已过期，请重新查看垃圾。"
        }
    }
}

struct TreeEntry { let relative: String; let identity: FileIdentity }
struct TreeSnapshot {
    let identity: FileIdentity
    let fingerprint: String
    let bytes: Int64
    let fileCount: Int
    let entries: [TreeEntry]
}

enum SafeFS {
    static func identity(_ s: stat) -> FileIdentity {
        FileIdentity(device: UInt64(s.st_dev), inode: UInt64(s.st_ino), size: s.st_size,
                     modifiedSeconds: Int64(s.st_mtimespec.tv_sec), modifiedNanoseconds: Int64(s.st_mtimespec.tv_nsec),
                     mode: UInt32(s.st_mode), owner: s.st_uid)
    }
    static func isDirectory(_ m: FileIdentity) -> Bool { m.mode & UInt32(S_IFMT) == UInt32(S_IFDIR) }
    static func isLink(_ m: FileIdentity) -> Bool { m.mode & UInt32(S_IFMT) == UInt32(S_IFLNK) }
    static func isRegular(_ m: FileIdentity) -> Bool { m.mode & UInt32(S_IFMT) == UInt32(S_IFREG) }
    static func exists(_ url: URL) -> Bool { var s = stat(); return lstat(url.path, &s) == 0 }
    static func within(_ path: String, _ root: String) -> Bool { path == root || path.hasPrefix(root + "/") }
    static func fail(_ path: String) -> CleanerError { .system("\(path)：\(String(cString: strerror(errno)))") }

    static func lexicalPath(_ path: String) -> Bool {
        path.hasPrefix("/") && path != "/" && !path.dropFirst().split(separator: "/", omittingEmptySubsequences: false).contains { $0.isEmpty || $0 == "." || $0 == ".." }
    }

    // Open every ancestor relative to a pinned directory descriptor. No symlink is followed.
    static func parent(_ url: URL) throws -> (Int32, String) {
        let path = url.path
        guard lexicalPath(path) else { throw CleanerError.unsafe(path) }
        let parts = path.split(separator: "/").map(String.init)
        guard !parts.contains(".."), !parts.contains("."), let leaf = parts.last else { throw CleanerError.unsafe(path) }
        var fd = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard fd >= 0 else { throw fail(path) }
        for part in parts.dropLast() {
            let next = openat(fd, part, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            close(fd)
            guard next >= 0 else { throw fail(path) }
            fd = next
        }
        return (fd, leaf)
    }
    static func metadata(_ url: URL) throws -> FileIdentity {
        let (fd, name) = try parent(url); defer { close(fd) }
        var s = stat()
        guard fstatat(fd, name, &s, AT_SYMLINK_NOFOLLOW) == 0 else { throw fail(url.path) }
        return identity(s)
    }
    static func names(_ fd: Int32) throws -> [String] {
        guard let dir = fdopendir(dup(fd)) else { throw fail("读取目录") }
        defer { closedir(dir) }
        var result: [String] = []
        errno = 0
        while let entry = readdir(dir) {
            let name = withUnsafePointer(to: entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: entry.pointee.d_name)) { String(cString: $0) }
            }
            if name != "." && name != ".." { result.append(name) }
            errno = 0
        }
        guard errno == 0 else { throw fail("读取目录") }
        return result.sorted()
    }
    static func children(_ url: URL) throws -> [URL] {
        let (pfd, name) = try parent(url); defer { close(pfd) }
        let fd = openat(pfd, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw fail(url.path) }; defer { close(fd) }
        return try names(fd).map { url.appendingPathComponent($0) }
    }
    static func snapshot(_ url: URL, collectEntries: Bool = false, skippingRootNames: Set<String> = []) throws -> TreeSnapshot {
        let (pfd, leaf) = try parent(url); defer { close(pfd) }
        var rootStat = stat()
        guard fstatat(pfd, leaf, &rootStat, AT_SYMLINK_NOFOLLOW) == 0 else { throw fail(url.path) }
        let rootIdentity = identity(rootStat)
        guard !isLink(rootIdentity), rootIdentity.owner == geteuid() else { throw CleanerError.unsafe(url.path) }
        var entries: [TreeEntry] = [], bytes: Int64 = 0, count = 0, hasher = SHA256(), seen = Set<String>()
        func visit(_ parentFD: Int32, _ name: String, _ relative: String) throws {
            var s = stat()
            guard fstatat(parentFD, name, &s, AT_SYMLINK_NOFOLLOW) == 0 else { throw fail(url.path) }
            let m = identity(s)
            guard isDirectory(m) || isRegular(m) || isLink(m) else { throw CleanerError.unsafe(url.path) }
            let record = "\(relative)\u{0}\(m.device):\(m.inode):\(m.size):\(m.modifiedSeconds):\(m.modifiedNanoseconds):\(m.mode)\n"
            hasher.update(data: Data(record.utf8))
            if collectEntries { entries.append(TreeEntry(relative: relative, identity: m)) }
            if isDirectory(m) {
                let fd = openat(parentFD, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                guard fd >= 0 else { throw fail(url.path) }; defer { close(fd) }
                var pinned = stat(); guard fstat(fd, &pinned) == 0, identity(pinned).inode == m.inode, identity(pinned).device == m.device else { throw CleanerError.changed(url.path) }
                for child in try names(fd) {
                    if relative.isEmpty && skippingRootNames.contains(child) { continue }
                    try visit(fd, child, relative.isEmpty ? child : relative + "/" + child)
                }
            } else {
                count += 1
                if seen.insert("\(m.device):\(m.inode)").inserted { bytes += Int64(s.st_blocks) * 512 }
            }
        }
        try visit(pfd, leaf, "")
        return TreeSnapshot(identity: rootIdentity, fingerprint: hasher.finalize().map { String(format: "%02x", $0) }.joined(), bytes: bytes, fileCount: count, entries: entries)
    }
    static func digest(_ url: URL) throws -> String {
        let (pfd, name) = try parent(url); defer { close(pfd) }
        let fd = openat(pfd, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw fail(url.path) }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        var s = stat(); guard fstat(fd, &s) == 0, isRegular(identity(s)) else { throw CleanerError.unsafe(url.path) }
        var h = SHA256()
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty { h.update(data: data) }
        return h.finalize().map { String(format: "%02x", $0) }.joined()
    }
    static func readPrefix(_ url: URL, limit: Int) throws -> Data {
        let (pfd, name) = try parent(url); defer { close(pfd) }
        let fd = openat(pfd, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw fail(url.path) }
        let h = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        var s = stat(); guard fstat(fd, &s) == 0, isRegular(identity(s)) else { throw CleanerError.unsafe(url.path) }
        return try h.read(upToCount: limit) ?? Data()
    }
    static func remove(_ url: URL, snapshot: TreeSnapshot, expectedFingerprint: String, keepingGoCacheRoot: Bool = false, onRemoval: (Int64) -> Void = { _ in }) throws {
        guard snapshot.fingerprint == expectedFingerprint else { throw CleanerError.changed(url.path) }
        let expected = Dictionary(uniqueKeysWithValues: snapshot.entries.map { ($0.relative, $0.identity) })
        let (pfd, leaf) = try parent(url); defer { close(pfd) }
        var accounted=Set<String>()
        func erase(_ parentFD: Int32, _ name: String, _ relative: String) throws {
            guard let old = expected[relative] else { throw CleanerError.changed(url.path) }
            var s = stat()
            guard fstatat(parentFD, name, &s, AT_SYMLINK_NOFOLLOW) == 0 else { throw CleanerError.changed(url.path) }
            let m = identity(s)
            guard m.device == old.device, m.inode == old.inode, m.mode == old.mode else { throw CleanerError.changed(url.path) }
            if isDirectory(m) {
                let fd = openat(parentFD, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                guard fd >= 0 else { throw CleanerError.changed(url.path) }; defer { close(fd) }
                var pinned = stat(); guard fstat(fd, &pinned) == 0, identity(pinned).inode == old.inode, identity(pinned).device == old.device else { throw CleanerError.changed(url.path) }
                for child in try names(fd) {
                    if relative.isEmpty && keepingGoCacheRoot && !child.matches("^[0-9a-f]{2}$") { continue }
                    try erase(fd, child, relative.isEmpty ? child : relative + "/" + child)
                }
                if relative.isEmpty && keepingGoCacheRoot { return }
                // New entries cannot be silently removed; rmdir fails if the directory is no longer empty.
                var finalEntry=stat()
                guard fstatat(parentFD,name,&finalEntry,AT_SYMLINK_NOFOLLOW)==0,identity(finalEntry).device==old.device,identity(finalEntry).inode==old.inode else { throw CleanerError.changed(url.path) }
                guard unlinkat(parentFD, name, AT_REMOVEDIR) == 0 else { throw fail(url.path) }
                onRemoval(0)
            } else {
                guard m == old else { throw CleanerError.changed(url.path) }
                guard unlinkat(parentFD, name, 0) == 0 else { throw fail(url.path) }
                let key="\(m.device):\(m.inode)"
                onRemoval(accounted.insert(key).inserted ? Int64(s.st_blocks)*512 : 0)
            }
        }
        try erase(pfd, leaf, "")
    }
    static func available(_ url: URL) -> Int64 {
        var s = statfs()
        guard statfs(url.path, &s) == 0 else { return 0 }
        return Int64(s.f_bavail) * Int64(s.f_bsize)
    }
}

struct OpenFileState {
    var paths: [String] = []
    var commands: [String] = []
    func contains(_ path: String) -> Bool { paths.contains { SafeFS.within($0, path) } }
    func busy(_ kind: CleanupKind, _ path: String) -> Bool {
        if contains(path) { return true }
        if [.goCache,.stagingCopy].contains(kind), commands.contains(where: { ["go","compile","link","makensis","electron-builder"].contains(URL(fileURLWithPath:$0).lastPathComponent) }) { return true }
        if kind == .rustCache, commands.contains(where: { ["cargo","rustc"].contains(URL(fileURLWithPath:$0).lastPathComponent) }) { return true }
        if [.cursorSnapshots,.cursorSearchIndex].contains(kind), commands.contains(where: { $0.contains("/Cursor.app/") }) { return true }
        if kind == .blenderBackup, commands.contains(where: { URL(fileURLWithPath:$0).lastPathComponent == "Blender" }) { return true }
        return busyAIOrDaily(kind,path)
    }
    static func validatedOutput(executable:String,status:Int32,output:Data,diagnostics:Data) throws -> String {
        guard status == 0,diagnostics.isEmpty,!output.isEmpty else { throw CleanerError.system("无法完整检查文件占用，清理已停止。\(String(decoding:diagnostics.prefix(512),as:UTF8.self))") }
        return String(decoding:output,as:UTF8.self)
    }
    static func capture(enabled: Bool) throws -> OpenFileState {
        guard enabled else { return OpenFileState() }
        func output(_ exe: String, _ args: [String]) throws -> String {
            let p = Process(); p.executableURL = URL(fileURLWithPath:exe); p.arguments = args
            let out = Pipe(), err = Pipe(); p.standardOutput = out; p.standardError = err
            try p.run()
            let work = DispatchWorkItem { if p.isRunning { p.terminate() } }
            DispatchQueue.global().asyncAfter(deadline:.now()+8, execute:work)
            let data = out.fileHandleForReading.readDataToEndOfFile()
            let errors = err.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit(); work.cancel()
            return try validatedOutput(executable:exe,status:p.terminationStatus,output:data,diagnostics:errors)
        }
        let files = try output("/usr/sbin/lsof",["-nP","-Fpn"])
        let processes = try output("/bin/ps",["-axo","comm="])
        return OpenFileState(paths: files.split(separator:"\n").filter { $0.hasPrefix("n/") }.map { String($0.dropFirst()) }, commands: processes.split(separator:"\n").map { $0.trimmingCharacters(in:.whitespaces) })
    }
}

extension String {
    func matches(_ pattern: String) -> Bool { range(of: pattern, options: .regularExpression) != nil }
}

final class RustBuildLock {
    private let descriptor: Int32
    init(profile: URL) throws {
        let lock=profile.appendingPathComponent(".cargo-lock")
        let (parent,name)=try SafeFS.parent(lock);defer { close(parent) }
        let fd=openat(parent,name,O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC,mode_t(0o600))
        guard fd>=0 else { throw SafeFS.fail(lock.path) }
        var m=stat()
        guard fstat(fd,&m)==0,SafeFS.isRegular(SafeFS.identity(m)),m.st_uid==geteuid(),m.st_nlink==1 else { close(fd);throw CleanerError.unsafe(lock.path) }
        guard flock(fd,LOCK_EX | LOCK_NB)==0 else { close(fd);throw CleanerError.busy(lock.path) }
        descriptor=fd
    }
    deinit { flock(descriptor,LOCK_UN);close(descriptor) }
}

struct VerifiedReference {
    let url:URL
    let identity:FileIdentity
    init(url:URL,digest:String) throws {
        self.url=url;identity=try SafeFS.metadata(url)
        guard SafeFS.isRegular(identity),try SafeFS.digest(url)==digest,try SafeFS.metadata(url)==identity else { throw CleanerError.changed(url.path) }
    }
    func validateUnchanged() throws {
        guard try SafeFS.metadata(url)==identity else { throw CleanerError.changed("正式保留文件："+url.path) }
    }
}
