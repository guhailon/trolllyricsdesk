import Foundation
import Darwin

final class MediaRemoteBridge {

    private let handle: UnsafeMutableRawPointer?

    init() {
        handle = dlopen(
            MediaRemoteSymbols.frameworkPath,
            RTLD_NOW
        )
    }

    deinit {
        if let handle {
            dlclose(handle)
        }
    }

    func symbol(_ name: String) -> UnsafeMutableRawPointer? {
        guard let handle else { return nil }
        return dlsym(handle, name)
    }
}
