import XCTest
@testable import CleanerCore

final class WebCacheTests: XCTestCase {
    let fm = FileManager.default
    var root: URL!
    var home: URL!
    var cache: URL!
    var engine: CleaningEngine!
    override func setUpWithError() throws {
        root = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("FeatherSweepWebTests-\(UUID().uuidString)").resolvingSymlinksInPath()
        home = root.appendingPathComponent("home")
        cache = home.appendingPathComponent("Library/Application Support/Google/Chrome/Default/Service Worker/CacheStorage/" + String(repeating:"a",count:40) + "/11111111-1111-1111-1111-111111111111")
        try fm.createDirectory(at:cache,withIntermediateDirectories:true)
        engine = CleaningEngine(configuration:.init(home:home,temporaryRoots:[],userTemporaryRoot:root.appendingPathComponent("T"),checkOpenFiles:false))
    }
    override func tearDownWithError() throws { try fm.removeItem(at:root) }
    func varint(_ value: Int) -> Data {
        var n=value,bytes:[UInt8]=[]
        while n>=128 { bytes.append(UInt8(n&127)|128);n >>= 7 };bytes.append(UInt8(n));return Data(bytes)
    }
    func field(_ number: Int, _ data: Data) -> Data { varint((number<<3)|2)+varint(data.count)+data }
    func index(_ origin: String = "https://workspace.feishu.cn") throws {
        let message=field(1,Data("static".utf8))+field(2,Data(cache.lastPathComponent.utf8))
        let data=field(1,message)+field(2,Data(origin.utf8))
        try data.write(to:cache.deletingLastPathComponent().appendingPathComponent("index.txt"))
    }
    func asset(_ name: String, _ key: String) throws -> URL {
        var data=Data()
        func little(_ n:UInt64,_ count:Int) { for i in 0..<count { data.append(UInt8((n >> (i*8))&255)) } }
        little(0xfcfb6d1ba7725c30,8);little(9,4);little(UInt64(key.utf8.count),4);little(0,4);little(0,4)
        data.append(Data(key.utf8));data.append(Data(repeating:1,count:100))
        let p=cache.appendingPathComponent(name);try data.write(to:p);return p
    }
    func testOnlyApprovedStaticAssetsAreRemoved() throws {
        try index()
        let a=try asset("aaaaaaaaaaaaaaaa_0","https://lf-package-cn.feishucdn.com/app.js")
        let b=try asset("aaaaaaaaaaaaaaaa_1","https://lf-package-cn.feishucdn.com/app.js")
        let api=try asset("bbbbbbbbbbbbbbbb_0","https://workspace.feishu.cn/api/messages.json")
        let other=try asset("cccccccccccccccc_0","https://unrelated.example/app.js")
        let cookies=home.appendingPathComponent("Library/Application Support/Google/Chrome/Default/Cookies")
        try Data("session".utf8).write(to:cookies)
        let indexPath=cache.deletingLastPathComponent().appendingPathComponent("index.txt")
        let before=try Data(contentsOf:indexPath)
        let report=try engine.scan()
        XCTAssertEqual(report.candidates.filter{$0.kind == .staticWebEntry}.count,1)
        _=try engine.clean(report)
        for p in [a,b] { XCTAssertFalse(fm.fileExists(atPath:p.path)) }
        for p in [api,other,cookies,indexPath] { XCTAssertTrue(fm.fileExists(atPath:p.path)) }
        XCTAssertEqual(try Data(contentsOf:indexPath),before)
        XCTAssertEqual(try String(contentsOf:cookies),"session")
    }
    func testMixedKeyPairIsPreserved() throws {
        try index()
        _=try asset("aaaaaaaaaaaaaaaa_0","https://lf-package-cn.feishucdn.com/app.js")
        _=try asset("aaaaaaaaaaaaaaaa_1","https://workspace.feishu.cn/api/messages.json")
        XCTAssertTrue(try engine.scan().candidates.isEmpty)
    }
    func testUnapprovedOriginIsPreservedEvenWithStaticCDNKey() throws {
        try index("https://unrelated.example")
        _=try asset("aaaaaaaaaaaaaaaa_0","https://lf-package-cn.feishucdn.com/app.js")
        XCTAssertTrue(try engine.scan().candidates.isEmpty)
    }
    func testChangedStaticResourceIsSkipped() throws {
        try index();let p=try asset("aaaaaaaaaaaaaaaa_0","https://lf-package-cn.feishucdn.com/app.js")
        let report=try engine.scan()
        _=try asset("aaaaaaaaaaaaaaaa_0","https://lf-package-cn.feishucdn.com/new.js")
        let result=try engine.clean(report)
        XCTAssertTrue(fm.fileExists(atPath:p.path));XCTAssertFalse(result.skipped.isEmpty)
    }
}
