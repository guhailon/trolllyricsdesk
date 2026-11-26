import Foundation
import Darwin

/// 1.0.5 诊断（第 1 项）：dlopen／dlsym 只记一次结论，不在每次轮询里刷屏。
/// 失败时把 dlerror() 的原因也记下来——真机日志要能看出是框架打不开、
/// 还是某个符号找不到。只记日志，不改任何行为。
final class MediaRemoteBridge {

    private let handle: UnsafeMutableRawPointer?
    private var loggedSymbols = Set<String>()
    private(set) var dlopenOK = false

    init() {
        handle = dlopen(
            MediaRemoteSymbols.frameworkPath,
            RTLD_NOW
        )
        dlopenOK = handle != nil
        if let handle {
            _ = handle
            LyricLogger.log(
                "诊断1.0.5 MediaRemote：dlopen 成功（\(MediaRemoteSymbols.frameworkPath)）"
            )
        } else {
            let reason = MediaRemoteBridge.lastDLError()
            LyricLogger.log(
                "诊断1.0.5 MediaRemote：dlopen 失败：\(reason)"
            )
        }
    }

    deinit {
        if let handle {
            dlclose(handle)
        }
    }

    func symbol(_ name: String) -> UnsafeMutableRawPointer? {
        guard let handle else {
            if !loggedSymbols.contains(name) {
                loggedSymbols.insert(name)
                LyricLogger.log(
                    "诊断1.0.5 MediaRemote：dlsym \(name) 失败：框架未打开（dlopen 已失败）"
                )
            }
            return nil
        }
        let sym = dlsym(handle, name)
        if !loggedSymbols.contains(name) {
            loggedSymbols.insert(name)
            if sym != nil {
                LyricLogger.log("诊断1.0.5 MediaRemote：dlsym \(name) 成功")
            } else {
                LyricLogger.log(
                    "诊断1.0.5 MediaRemote：dlsym \(name) 失败：\(MediaRemoteBridge.lastDLError())"
                )
            }
        }
        return sym
    }

    private static func lastDLError() -> String {
        guard let err = dlerror() else { return "无错误信息" }
        return String(cString: err)
    }
}
