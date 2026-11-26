import Foundation
import Darwin

/// 进程实际有效权限（1.0.6 第 5 项＋第 1 项的正面证据）。
///
/// 只认实际调用／系统查询的结果，不认 IPA 声明了什么：
/// - 任务级权限：SecTask（内核强制的实际值）——用 dlsym 拿函数指针，
///   不链接 Security、不依赖头文件；符号不存在就返回 nil，不崩。
///   读到 true = 系统真授予了；false = 真没有；nil = 读不到（未知，不当通过）。
/// - 沙盒外写探测：no-sandbox 是否实际生效——在 /var/mobile 下建一个
///   唯一名空文件，成功即删。成功 = 解除沙盒生效（只有 TrollStore 会给）；
///   EPERM／EACCES = 被沙盒拦住；其他错误 = 未知。
/// - MediaRemote／FrontBoard 的实测不在这里：MediaRemote 看
///   MediaRemoteDiagnostics 的回调记录，FrontBoard 看 ObjC 侧托管复核。
/// - LC 客人继承不到宿主没有的权限：宿主是普通开发者签名时，
///   任务权限里 platform-application／no-sandbox 就是 false，
///   沙盒外写也被拒——这张表会如实写出来。
enum EffectiveEntitlements {

    /// SecTask 探测的权限键（与 TrollLyricsDesk.entitlements 声明的一致，
    /// 只查这里列出的键，不多查）。
    static let probedKeys = [
        "platform-application",
        "com.apple.private.security.no-sandbox",
        "com.apple.frontboard.launchapplications",
        "com.apple.mediaremote.now-playing-read-access",
        "com.apple.mediaremote.full-now-playing-read-access",
        "com.apple.backboard.client",
        "get-task-allow",
    ]

    private static let securityHandle: UnsafeMutableRawPointer? = dlopen(
        "/System/Library/Frameworks/Security.framework/Security",
        RTLD_NOW
    )

    private static func secTaskSymbol(_ name: String) -> UnsafeMutableRawPointer? {
        guard let handle = securityHandle else { return nil }
        return dlsym(handle, name)
    }

    /// 任务级权限实测（SecTask，内核强制值）：true／false／nil（读不到）。
    static func taskEntitlement(_ key: String) -> Bool? {
        guard let createSym = secTaskSymbol("SecTaskCreateFromSelf"),
              let copySym = secTaskSymbol("SecTaskCopyValueForEntitlement") else {
            return nil
        }
        typealias CreateFn = @convention(c) (CFAllocator?) -> UnsafeMutableRawPointer?
        // 1.0.6/build 21：SecTaskCopyValueForEntitlement 正确要 3 个参数
        //（task、key、CFErrorRef *error）；2 参数版是隐患——哪个键查不到，
        // 系统往缺失的第三个参数写东西就真崩。第三个参数传 nil（不要错误对象）。
        typealias CopyFn = @convention(c) (UnsafeMutableRawPointer, CFString, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Unmanaged<CFTypeRef>?
        guard let task = unsafeBitCast(createSym, to: CreateFn.self)(nil) else {
            return nil
        }
        // SecTaskCreateFromSelf 是 Create 规则（＋1），用完放掉，不留引用。
        defer { Unmanaged<CFTypeRef>.fromOpaque(task).release() }
        guard let unmanaged = unsafeBitCast(copySym, to: CopyFn.self)(task, key as CFString, nil) else {
            return nil
        }
        // SecTaskCopyValueForEntitlement 是 Copy 规则（＋1），takeRetainedValue 接管。
        let value = unmanaged.takeRetainedValue()
        return (value as? NSNumber)?.boolValue
    }

    /// 沙盒外写探测：outcome 是 success（解除沙盒生效）／denied（被沙盒拦住）／
    /// unknown（其他错误，原因不明）；detail 写清 errno。文件建完即删，
    /// 只留一行日志，不留残留文件。
    static func sandboxWriteProbe() -> (outcome: String, detail: String) {
        let path = "/var/mobile/.tlds-entitlement-probe-\(ProcessInfo.processInfo.processIdentifier)"
        let fd = open(path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        if fd >= 0 {
            close(fd)
            unlink(path)
            return ("success", "沙盒外写成功（文件已删）")
        }
        let err = errno
        if err == EPERM || err == EACCES {
            return ("denied", "沙盒外写被拒（errno=\(err)，权限受限）")
        }
        return ("unknown", "沙盒外写失败（errno=\(err)，原因不明）")
    }

    /// 只探一次（启动时），结果全进程复用，不重复写文件、不重复调 SecTask。
    private static let probedTaskValues: [String: Bool?] = {
        var out: [String: Bool?] = [:]
        for key in probedKeys {
            out[key] = taskEntitlement(key)
        }
        return out
    }()

    private static let probedWrite: (outcome: String, detail: String) = {
        sandboxWriteProbe()
    }()

    static func taskValue(for key: String) -> Bool? {
        probedTaskValues[key] ?? nil
    }

    static var writeProbeOutcome: String { probedWrite.outcome }

    static var writeProbeDetail: String { probedWrite.detail }

    /// TrollStore 正面证据（第 1 项用）：任务权限 platform-application 与
    /// no-sandbox 均为 true，或沙盒外写探测成功。任一成立即算证明；
    /// 都不成立不是「不是 TrollStore」的证明，只是「没有正面证据」。
    static func trollStoreEvidence() -> (proven: Bool, detail: String) {
        let platform = taskValue(for: "platform-application")
        let noSandbox = taskValue(for: "com.apple.private.security.no-sandbox")
        if platform == true && noSandbox == true {
            return (true, "任务权限 platform-application=YES 且 no-sandbox=YES（SecTask 实测）")
        }
        if probedWrite.outcome == "success" {
            return (true, "沙盒外写探测成功（no-sandbox 实际生效）；任务权限 platform-application=\(describe(platform))、no-sandbox=\(describe(noSandbox))")
        }
        return (false, "任务权限 platform-application=\(describe(platform))、no-sandbox=\(describe(noSandbox))；沙盒外写探测：\(probedWrite.detail)")
    }

    /// 已证实被沙盒拦住：写探测被拒，或任务权限两项都明确为 false。
    /// （写探测其他错误、SecTask 读不到时不算已证实，返回 false，走 unknown。）
    static var sandboxedProven: Bool {
        if probedWrite.outcome == "denied" { return true }
        let platform = taskValue(for: "platform-application")
        let noSandbox = taskValue(for: "com.apple.private.security.no-sandbox")
        return platform == false && noSandbox == false
    }

    static func describe(_ value: Bool?) -> String {
        switch value {
        case .some(true): return "YES"
        case .some(false): return "NO"
        case .none: return "读不到"
        }
    }

    /// 实测表打进日志（启动判定一次＋诊断页刷新一次）。
    static func logReport() {
        LyricLogger.log("诊断1.0.6 实际权限：声明≠可用，以下是进程实测（SecTask 任务权限＋沙盒外写探测）")
        for key in probedKeys {
            LyricLogger.log("诊断1.0.6 实际权限：\(key)：任务权限=\(describe(taskValue(for: key)))")
        }
        LyricLogger.log("诊断1.0.6 实际权限：沙盒外写探测：\(probedWrite.detail)")
        let evidence = trollStoreEvidence()
        LyricLogger.log("诊断1.0.6 实际权限：TrollStore 正面证据：\(evidence.proven ? "有" : "无")（\(evidence.detail)）")
    }
}
