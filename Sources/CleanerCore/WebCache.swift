import Foundation

// Chromium SimpleFileHeader and CacheStorageIndex are parsed only far enough to
// identify approved static resources. Cookies and website storage are never opened.
enum WebCache {
    static let extensions: Set<String> = ["js","mjs","css","png","jpg","jpeg","webp","svg","ico","gif","avif","woff","woff2","ttf","otf","wasm","map"]
    static let feishuHosts: Set<String> = ["lf-package-cn.feishucdn.com","lf-package-sg.feishucdn.com","sf1-scmcdn-cn.feishucdn.com"]
    static func fields(_ data: Data) throws -> [Int:[Data]] {
        let bytes=[UInt8](data);var position=0;var result:[Int:[Data]]=[:]
        func number() throws -> UInt64 {
            var value:UInt64=0,shift=0
            for _ in 0..<10 {
                guard position<bytes.count else { throw CleanerError.system("缓存索引格式不完整") }
                let b=bytes[position];position+=1
                guard shift<64, !(shift==63 && b>1) else { throw CleanerError.system("缓存索引格式不支持") }
                value |= UInt64(b&127)<<shift
                if b&128==0 { return value };shift+=7
            }
            throw CleanerError.system("缓存索引格式不支持")
        }
        while position<bytes.count {
            let tag=try number();let field=Int(tag>>3),wire=Int(tag&7)
            guard field>0 else { throw CleanerError.system("缓存索引格式不支持") }
            switch wire {
            case 0: _=try number()
            case 1: guard position+8<=bytes.count else { throw CleanerError.system("缓存索引格式不完整") };position+=8
            case 2:
                let n=try number();guard n<=UInt64(bytes.count-position) else { throw CleanerError.system("缓存索引格式不完整") }
                result[field,default:[]].append(Data(bytes[position..<(position+Int(n))]));position+=Int(n)
            case 5: guard position+4<=bytes.count else { throw CleanerError.system("缓存索引格式不完整") };position+=4
            default: throw CleanerError.system("缓存索引格式不支持")
            }
        }
        return result
    }
    static func index(_ originDirectory: URL) throws -> (String,Set<String>)? {
        let p=originDirectory.appendingPathComponent("index.txt")
        guard SafeFS.exists(p) else { return nil }
        let m=try SafeFS.metadata(p);guard m.size<=1024*1024 else { return nil }
        let f=try fields(SafeFS.readPrefix(p,limit:1024*1024))
        let raw = (f[2]?.first ?? f[3]?.first).flatMap { String(data:$0,encoding:.utf8) } ?? ""
        let origin=String(raw.split(separator:"^").first ?? "")
        guard let host=URL(string:origin)?.host?.lowercased(), approvedOrigin(host) else { return nil }
        var dirs=Set<String>()
        for message in f[1] ?? [] {
            let inner=try fields(message)
            if let name=inner[2]?.first.flatMap({String(data:$0,encoding:.utf8)}), UUID(uuidString:name) != nil { dirs.insert(name) }
        }
        return (host,dirs)
    }
    static func approvedOrigin(_ host:String)->Bool {
        host=="dash.cloudflare.com" || ["feishu.cn","feishu.net","larksuite.com","larkoffice.com"].contains { host==$0 || host.hasSuffix("."+$0) }
    }
    static func key(_ p:URL) throws -> String? {
        let d=[UInt8](try SafeFS.readPrefix(p,limit:128*1024+24))
        guard d.count>=24 else { return nil }
        func little(_ offset:Int,_ count:Int)->UInt64 { (0..<count).reduce(0) { $0 | (UInt64(d[offset+$1]) << ($1*8)) } }
        guard little(0,8)==0xfcfb6d1ba7725c30 else { return nil }
        let length=Int(little(12,4));guard length>0,length<=128*1024,24+length<=d.count else { return nil }
        guard let key=String(bytes:d[24..<(24+length)],encoding:.utf8), let range=key.range(of:"https://[^\\s\\u0000]+",options:.regularExpression) else { return nil }
        let text=String(key[range]);guard let url=URL(string:text), let host=url.host?.lowercased(), extensions.contains(url.pathExtension.lowercased()), feishuHosts.contains(host) || host=="dash.cloudflare.com" else { return nil }
        return key
    }
    static func validGroup(_ paths:[URL]) throws -> Bool {
        guard let first=paths.first else { return false }
        let cache=first.deletingLastPathComponent(),origin=cache.deletingLastPathComponent()
        guard let (_,dirs)=try index(origin),dirs.contains(cache.lastPathComponent) else { return false }
        var keys=Set<String>()
        for p in paths {
            guard SafeFS.isRegular(try SafeFS.metadata(p)), let k=try key(p) else { return false };keys.insert(k)
        }
        return keys.count==1
    }
}

extension CleanupRules {
    mutating func scanWebCache() {
        do {
            for origin in try children(webRoot) where origin.lastPathComponent.matches("^[0-9a-f]{40}$") {
                guard let (_,dirs)=try WebCache.index(origin) else { continue }
                for name in dirs {
                    let cache=origin.appendingPathComponent(name)
                    var groups:[String:[URL]]=[:]
                    for p in try children(cache) where p.lastPathComponent.matches("^[0-9a-f]{16}_[01]$") { groups[String(p.lastPathComponent.prefix(16)),default:[]].append(p) }
                    for paths in groups.values {
                        let sorted=paths.sorted{$0.path<$1.path}
                        if try WebCache.validGroup(sorted),let first=sorted.first { add(first,kind:.staticWebEntry,category:.webCache,reason:"飞书 / Cloudflare 可重新下载的静态资源；保留 Cookie 与网站数据",companions:Array(sorted.dropFirst())) }
                    }
                }
            }
        } catch { warnings.append(error.localizedDescription) }
    }
}
