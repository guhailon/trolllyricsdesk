import Foundation
import Darwin

/// 1.0.5 诊断（第 1 项）：dlopen／dlsym 只记一次结论，不在每次轮询里刷屏。
/// 失败时把 dlerror() 的原因也记下来——真机日志要能看出是框架打不开、
/// 还是某个符号找不到。记录集中在 MediaRemoteDiagnostics（诊断页也能读到），
/// 这里只负责调 dlopen／dlsym 并上报结果，不改任何行为。
final class MediaRemoteBridge {

    private let handle: UnsafeMutableRawPointer?

    init() {
        handle = dlopen(
            MediaRemoteSymbols.frameworkPath,
            RTLD_NOW
        )
        MediaRemoteDiagnostics.recordDlopen(
            success: handle != nil,
            path: MediaRemoteSymbols.frameworkPath,
            reason: handle == nil ? Self.lastDLError() : nil
        )
    }

    deinit {
        if let handle {
            dlclose(handle)
        }
    }

    func symbol(_ name: String) -> UnsafeMutableRawPointer? {
        guard let handle else {
            MediaRemoteDiagnostics.recordDlsym(
                name: name, success: false, noHandle: true, reason: nil
            )
            return nil
        }
        let sym = dlsym(handle, name)
        MediaRemoteDiagnostics.recordDlsym(
            name: name, success: sym != nil, noHandle: false,
            reason: sym == nil ? Self.lastDLError() : nil
        )
        return sym
    }

    private static func lastDLError() -> String {
        guard let err = dlerror() else { return "无错误信息" }
        return String(cString: err)
    }
}
