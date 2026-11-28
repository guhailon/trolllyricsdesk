import Foundation
import Security

/// 激活标记的 Keychain 持久化（2.0.1，唯一新增功能）。
///
/// 目的：重装 App 后不用再激活。UserDefaults（App Group suite／宿主
/// .standard）随 App 删除一起清掉，Keychain 不会——所以激活成功时把
/// 激活类型也写一份进 Keychain，启动时先从 Keychain 恢复回 UserDefaults。
///
/// 依据（方案成立的前提）：iOS 的 Keychain item 在删除 App 后仍保留，
/// 同一签名身份（同一 access group／同一 Team＋bundle 种子）下重装后
/// 仍可读到。只用默认访问组，不新增任何 entitlements。
///
/// 局限：若重装时签名身份变了（例如换了签名方式／换了 Team），旧
/// Keychain item 可能读不到，届时仍需重新激活一次——这是 iOS 的
/// Keychain 归属规则，不是本 App 能绕过的。
///
/// 全部接口都是静默的：任何 Keychain 调用失败都返回 nil／直接忽略，
/// 绝不抛错、绝不崩溃、不记任何日志。存的只是激活类型（"master"／
/// "code"），不是码值——码值只在服务端校验，永不落盘。
enum ActivationKeychain {

    /// service 用 App 自身标识（与 bundle id 一致）。
    private static let service = "com.ycwl.Lyrics"

    /// account 固定为激活标记键（与 UserDefaults 的键同名，便于对照）。
    private static let account = "tld.activated"

    /// 读标记：有返回激活类型（"master"／"code"），无返回 nil，
    /// 任何失败（无 item／读错／解不出）都返回 nil。
    static func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let type = String(data: data, encoding: .utf8),
              !type.isEmpty
        else {
            return nil
        }
        return type
    }

    /// 写标记：不存在则 SecItemAdd，已存在则 SecItemUpdate。
    /// 失败静默忽略（例如设备锁定期间 Keychain 不可用）。
    static func write(_ type: String) {
        guard let data = type.data(using: .utf8), !data.isEmpty else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        var attributes: [String: Any] = [
            kSecValueData as String: data,
            // 设备首次解锁后即可用：App 在后台被系统拉起时也能读写，
            // 不必等用户解锁；仍不新增 entitlements。
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        if status == errSecDuplicateItem {
            attributes.removeValue(forKey: kSecAttrAccessible as String)
            _ = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        }
    }

    /// 启动时调用一次，双向对齐 UserDefaults 与 Keychain：
    /// - UserDefaults 已激活、Keychain 为空 → 补写 Keychain（覆盖升级／
    ///   旧版已激活用户首次进 2.0.1 时，把标记补进 Keychain）。
    /// - UserDefaults 未激活、Keychain 有标记 → 把标记写回 UserDefaults
    ///   （重装后恢复，激活页不再弹）。
    /// - 两边一致时什么都不做。LC 宿主模式同样只 try 不报错：
    ///   defaults 走 .standard，Keychain 读写失败也只是静默跳过。
    static func syncWithDefaults() {
        let defaults = LyricStore.defaults ?? .standard
        let activated = defaults.bool(forKey: ActivationStore.activatedKey)
        let keychainType = read()
        if activated {
            if keychainType == nil {
                write(defaults.string(forKey: ActivationStore.activationTypeKey) ?? "code")
            }
        } else if let type = keychainType {
            defaults.set(true, forKey: ActivationStore.activatedKey)
            defaults.set(type, forKey: ActivationStore.activationTypeKey)
        }
    }
}
