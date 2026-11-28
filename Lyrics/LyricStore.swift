import Foundation

struct LyricSnapshot: Codable {

    var title: String
    var artist: String

    var lyrics: [LyricLine]

    var startedAt: Date
    var isPlaying: Bool

    var elapsedWhenPaused: TimeInterval

    var opacity: Double
    var fontSize: Double
}

enum LyricStore {

    static let groupID =
        "group.com.hailong.TrollLyricsDesk"

    static let dataKey = "lyric.snapshot"

    /// build 30：日志里的 build 号只从这里取（统一常量）——升版时改这一处＋
    /// 两处 Info.plist 的 CFBundleVersion＋pbxproj 的 CURRENT_PROJECT_VERSION。
    /// 自检 §19／§21 核对它与三处版本号一致（2.0.0 起另加 daemon 常量 TLDHUDVersion.h）；MediaRemoteAdapter 的探针日志用它插值，
    /// 不再写死 "build 22"（build 23 的日志写 build 22 就是写死字串的教训）。
    /// 故意写成长串（19 字节 UTF-8）：≤15 字节的字串在 Release 下会被编译器
    /// 压成 small-string immediate 进代码段，字节扫描不到；长字串进 __cstring，
    /// 验包能直接搜到 "build 26"。
    static let versionTag = "build 32（2.0.2）"

    /// 是否跑在 LiveContainer 宿主里（只作运行时检测，不可靠权限证明）。
    /// 信号（按优先级）：
    /// 1. 环境变量 LC_HOME_PATH（宿主起客人 App 前 setenv；旧统一版 1.0.6
    ///    build 18 的信号一，commit 893f066；hideLiveContainer 不动环境变量，
    ///    最可靠）——build 23 在 LC 3.8.12 里漏判成「普通签名（沙盒内）」，
    ///    就是因为 newbase 重写时丢了这一路。
    /// 2. Info.plist 键 TLDSLiveContainer 为 true。
    /// 3. 包路径含 /Documents/Applications/（旧线信号二：客人包体在宿主
    ///    Documents/Applications/ 下；巨魔包在 /var/containers/Bundle/Application/
    ///    下，不会误中）。
    /// 4. 包路径／可执行路径／argv[0]／进程名／Home 目录含 livecontainer 或
    ///    /lcapps/，或类 LCAppDelegate 存在。
    /// 宿主模式下 defaults 走 .standard（不用 App Group），悬浮窗／锁屏／
    /// 保活／小组件刷新一律不走，只做应用内歌词。
    static var isLiveContainer: Bool {
        if ProcessInfo.processInfo.environment["LC_HOME_PATH"] != nil { return true }
        if Bundle.main.object(forInfoDictionaryKey: "TLDSLiveContainer") as? Bool == true { return true }
        if Bundle.main.bundlePath.lowercased().contains("/documents/applications/") { return true }
        let paths = [Bundle.main.bundlePath, Bundle.main.executablePath ?? "", ProcessInfo.processInfo.arguments.first ?? "", ProcessInfo.processInfo.processName, NSHomeDirectory()]
        return paths.contains { path in
            let lower = path.lowercased()
            return lower.contains("livecontainer") || lower.contains("/lcapps/")
        } || NSClassFromString("LCAppDelegate") != nil
    }

    /// 当前是否检测不到任何播放器。由 poll() 写入，悬浮窗读取后决定
    /// 是显示歌词还是提示——避免无音乐时悬浮窗停留在上一次的歌词快照。
    static let noMusicKey = "lyric.noMusic"

    /// 悬浮窗开关变化通知：双击隐藏 / 主界面拨开关时互相同步。
    /// 两侧用的是不同的 UserDefaults 实例，写值不会自动刷新对方，需显式通知。
    static let floatingEnabledChanged = Notification.Name("TLDSFloatingEnabledChanged")

    /// 歌词时间偏移（秒，存 App Group，主 App / 悬浮窗 / Widget 共用）。
    /// 正值 = 歌词提前显示，负值 = 延后显示。
    ///
    /// 第二次修复：改为「逐歌」记忆。LRCLIB 的歌词由不同用户上传，
    /// 每首歌的时间轴偏差各不相同（有的偏早、有的偏晚），全局一个值
    /// 无法同时满足——调好 A 歌就会弄坏 B 歌，正是「有的歌不同步」。
    /// 这里按稳定歌曲标识分别存，每首歌调一次，之后自动套用。
    private static let offsetKeyPrefix = "lyric.timeOffset|"

    static var defaults: UserDefaults? {
        isLiveContainer ? .standard : UserDefaults(suiteName: groupID)
    }

    /// 某首歌的时间偏移 key（用稳定歌曲标识，字段型播放器换字段也不变）。
    private static func offsetKey(title: String, artist: String) -> String {
        offsetKeyPrefix + stableSongIdentity(title: title, artist: artist)
            .lowercased()
    }

    /// 读取指定歌曲的时间偏移。没调过返回 0（保持旧行为）。
    static func timeOffset(title: String, artist: String) -> TimeInterval {
        let key = offsetKey(title: title, artist: artist)
        guard let raw = defaults?.object(forKey: key) else { return 0 }
        return (raw as? Double) ?? (raw as? NSNumber)?.doubleValue ?? 0
    }

    /// 从快照读取当前歌曲的偏移。悬浮窗 / Widget / 主界面统一走这里。
    static func timeOffset(_ snapshot: LyricSnapshot) -> TimeInterval {
        timeOffset(title: snapshot.title, artist: snapshot.artist)
    }

    /// 保存某首歌的时间偏移。
    static func setTimeOffset(
        _ value: TimeInterval,
        title: String,
        artist: String
    ) {
        defaults?.set(value, forKey: offsetKey(title: title, artist: artist))
    }

    static func save(_ snapshot: LyricSnapshot) {

        guard let data = try? JSONEncoder().encode(
            snapshot
        ) else {
            return
        }

        defaults?.set(data, forKey: dataKey)
    }

    static func load() -> LyricSnapshot? {

        guard
            let data = defaults?.data(forKey: dataKey),
            let snapshot = try? JSONDecoder().decode(
                LyricSnapshot.self,
                from: data
            )
        else {
            return nil
        }

        return snapshot
    }

    static func currentElapsed(
        _ snapshot: LyricSnapshot,
        at date: Date
    ) -> TimeInterval {

        if snapshot.isPlaying {
            return max(
                0,
                snapshot.elapsedWhenPaused
                    + date.timeIntervalSince(
                        snapshot.startedAt
                    )
            )
        }

        return snapshot.elapsedWhenPaused
    }

    static func currentLyric(
        _ snapshot: LyricSnapshot,
        at date: Date
    ) -> LyricLine? {

        // 叠加这首歌自己的校正偏移：正值让歌词提前出现，抵消 LRC 时间轴偏晚。
        // 逐歌存储，调一首不影响其他歌。
        let elapsed = currentElapsed(
            snapshot,
            at: date
        ) + timeOffset(snapshot)

        return snapshot.lyrics.last {
            $0.time <= elapsed
        }
    }

    /// 识别「歌词被塞进 artist 字段」的播放器。
    /// 实测上报格式是 "歌名 — 歌手"（如 "为什么 — 庄妮" / "谁的生活不是鸡零狗碎 — 李认针"），
    /// 歌手名在尾段；artist 放的是逐句变化的歌词。判定必须只看尾段歌手名：
    /// 只要 artist 不等于尾段歌手，就认定它是歌词，歌词始终显示在上面。
    /// 旧逻辑只比对前段且要求 "前段 != artist"，当某句歌词恰好等于歌名
    /// （如歌词 "为什么"、title "为什么 — 庄妮"）时会突然判成正常播放器，
    /// 把歌词翻到下面——这正是「本来正常，突然乱识别」的原因。
    /// 正常播放器（artist 就是尾段歌手本人）返回 false。
    static func artistCarriesLyric(title: String, artist: String) -> Bool {
        // build 28：「·」型镜像（title = "真歌名 · 真歌手"，artist = 歌词行）
        // 同样认 " · "——与 songIdentityParts 的分隔符保持一致。
        let separators = [" — ", " – ", " - ", " · ", "—", "–"]
        let trimmedArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedArtist.isEmpty else { return false }

        for sep in separators {
            guard let range = title.range(of: sep) else { continue }
            let head = String(title[..<range.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let tail = String(title[range.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !head.isEmpty, !tail.isEmpty else { continue }

            // 「歌名 — 歌手」：尾段是歌手名，artist 与它不同就是歌词。
            // 条件只看尾段，和歌词库是否命中、歌词长短都无关，因此稳定。
            if tail.count <= 8, trimmedArtist != tail {
                return true
            }
            // 兼容「歌手 — 歌名」：首段是歌手且 artist 就是歌手本人 → 正常播放器。
            if head.count <= 8, tail.count > 8, trimmedArtist == head {
                return false
            }
        }
        return false
    }

    // MARK: - 歌词位置识别（title / artist 字段会互换）

    /// 歌词所在字段。
    enum LyricLocation {
        case artist  /// 歌词在 artist 字段
        case title   /// 歌词在 title 字段
        case unknown /// 判定不了，调用方维持「title 在上」的原布局
    }

    /// 拆出 "A — B" 型「歌曲标识串」的两段；不是这种格式返回 nil。
    /// build 28：加 " · "——「·」型播放器（汽水音乐实测）把
    /// "真歌名 · 真歌手" 放进 artist 字段、当前歌词行放进 title 字段；
    /// 不认 " · "，stableSongIdentity 会退回歌词行当标识，每句都当成换歌。
    private static func songIdentityParts(
        _ text: String
    ) -> (head: String, tail: String)? {
        let separators = [" — ", " – ", " - ", " · ", "—", "–"]
        for sep in separators {
            guard let range = text.range(of: sep) else { continue }
            let head = String(text[..<range.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let tail = String(text[range.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !head.isEmpty, !tail.isEmpty {
                return (head, tail)
            }
        }
        return nil
    }

    /// 标识串里是否有一段等于 part——用于排除「artist 其实就是歌手名」的正常播放器。
    private static func identity(_ text: String, hasPart part: String) -> Bool {
        guard let parts = songIdentityParts(text) else { return false }
        func norm(_ s: String) -> String {
            s.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: " ", with: "")
        }
        let p = norm(part)
        return norm(parts.head) == p || norm(parts.tail) == p
    }

    /// 稳定判断歌词在 title 还是 artist 字段。
    ///
    /// 实测某些播放器会在两个字段间来回交换：
    ///   某帧 title = "歌手 — 歌名"、artist = 当前歌词；
    ///   下一帧 title = 当前歌词、artist = "歌手 — 歌名"。
    /// 只判断「artist 是不是歌词」会在交换后翻转，导致歌词一会在上一会在下。
    /// 稳定的信号是「谁是歌曲标识串」：标识串整首歌不变且带 " — " 分隔符，
    /// 歌词逐句变化且通常不带分隔符，所以先认出标识串，另一字段就是歌词。
    static func lyricLocation(
        title: String,
        artist: String,
        lyricTexts: Set<String> = []
    ) -> LyricLocation {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let a = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !a.isEmpty else { return .unknown }

        func norm(_ s: String) -> String {
            s.replacingOccurrences(of: " ", with: "")
        }

        let titleIsIdentity = songIdentityParts(t) != nil
        let artistIsIdentity = songIdentityParts(a) != nil

        if titleIsIdentity && !artistIsIdentity {
            // title 是标识串 → artist 是歌词；artist 正好是标识串里的歌手名则不算。
            return identity(t, hasPart: a) ? .unknown : .artist
        }
        if artistIsIdentity && !titleIsIdentity {
            return identity(a, hasPart: t) ? .unknown : .title
        }

        // 两边都不像标识串：用歌词库命中判断。
        let inTitle = lyricTexts.contains(norm(t))
        let inArtist = lyricTexts.contains(norm(a))
        if inArtist && !inTitle { return .artist }
        if inTitle && !inArtist { return .title }

        // 兜底：artist 是 8 字以上纯中文短句，按歌词处理。
        let looksLikeLyric = norm(a).count >= 8 &&
            norm(a).unicodeScalars.allSatisfy {
                $0.value >= 0x4E00 && $0.value <= 0x9FFF
            }
        return looksLikeLyric ? .artist : .unknown
    }

    /// 取用于「换歌判定 / 歌词缓存」的稳定歌曲标识。
    /// title / artist 里带 " — " 分隔符的那一段是整首歌固定的「歌手 — 歌名」，
    /// 另一段是逐句变化的歌词；交换两字段后取到的仍是同一个串，因此稳定。
    /// 两边都没有分隔符（正常播放器）时退回 title，保持原行为。
    static func stableSongIdentity(title: String, artist: String) -> String {
        if songIdentityParts(title) != nil { return title }
        if songIdentityParts(artist) != nil { return artist }
        return title
    }

    /// 取真正用于搜词的「歌名 / 歌手」。
    /// 「·」型播放器（汽水音乐实测）：title 是当前歌词行、artist 是
    /// "真歌名 · 真歌手"（如 "为你等天晴 · 桃枝渡晚"、
    /// "血染江山的画怎敌你眉间 一点朱砂 · 清越"）。拿原字段去搜词，
    /// track_name 是歌词行、artist_name 是整串，永远搜不到；
    /// 要先解析出真歌名/真歌手再搜、再匹配、再缓存。
    /// 镜像（title = "真歌名 · 真歌手"，artist = 歌词行）同样处理。
    /// 只认 " · "：实测格式固定是「歌名 · 歌手」；
    /// 「 — 」型歌名/歌手顺序不明（两种都出现过），不猜，原样返回。
    static func searchTerms(title: String, artist: String) -> (track: String, artist: String) {
        for field in [artist, title] {
            guard let range = field.range(of: " · ") else { continue }
            let head = String(field[..<range.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let tail = String(field[range.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !head.isEmpty, !tail.isEmpty {
                return (head, tail)
            }
        }
        return (title, artist)
    }

    // MARK: - 歌词本地缓存
    // 搜到过的歌词按「歌名|歌手」存进 App Group，下次再播同一首歌
    // 直接从缓存读，做到「播放即显示」，不必等网络搜索。

    private static func cacheKey(title: String, artist: String) -> String {
        "lyric.cache|\(title.lowercased())|\(artist.lowercased())"
    }

    struct CachedLyric: Codable {
        let lines: [LyricLine]
        let savedAt: Date
    }

    static func cachedLyrics(
        title: String,
        artist: String
    ) -> [LyricLine]? {
        guard
            let data = defaults?.data(
                forKey: cacheKey(title: title, artist: artist)
            ),
            let cached = try? JSONDecoder().decode(
                CachedLyric.self,
                from: data
            ),
            !cached.lines.isEmpty
        else {
            return nil
        }
        return cached.lines
    }

    static func cacheLyrics(
        _ lines: [LyricLine],
        title: String,
        artist: String
    ) {
        let cached = CachedLyric(lines: lines, savedAt: Date())
        guard let data = try? JSONEncoder().encode(cached) else {
            return
        }
        defaults?.set(
            data,
            forKey: cacheKey(title: title, artist: artist)
        )
    }
}

// MARK: - 授权激活（1.0.3）
// 整个 App 第一次打开就要码：激活标记存在 App Group 里，App 与 Widget 共用。
// 码表只在服务端（Cloudflare Pages Functions），App 里没有任何码值，
// 这里只有接口地址和标记键。验证走 POST /api/verify，服务端比对不分大小写，
// App 端同样先 trim 再大写。
// 本文件同时在 App 与 Widget 两个 target 里（两边都要读激活标记），
// 所以只放 Foundation 层面的键与读写，不放任何 SwiftUI／网络代码。
enum ActivationStore {

    static let verifyURLString =
        "https://guhailong-repo.pages.dev/api/verify"

    static let activatedKey = "tld.activated"
    static let activationTypeKey = "tld.activationType"

    static var isActivated: Bool {
        LyricStore.defaults?.bool(forKey: activatedKey) ?? false
    }

    static var activationType: String? {
        LyricStore.defaults?.string(forKey: activationTypeKey)
    }

    static func markActivated(type: String) {
        LyricStore.defaults?.set(true, forKey: activatedKey)
        LyricStore.defaults?.set(type, forKey: activationTypeKey)
    }
}

// MARK: - 1.0.5 诊断：强制悬浮测试文字（第 2 项）
// 开关存在 LyricStore.defaults 里（巨魔走 App Group，宿主走 .standard，
// 与快照同一份存储，悬浮窗与应用内歌词区读的是同一把开关）。
// 开后悬浮窗／应用内歌词区显示固定测试文字，不依赖音乐、不读歌词；
// 关后立刻回到正常歌词，不残留测试文字。
extension LyricStore {

    static let testTextKey = "floatingLyric.testTextEnabled"

    static var isTestTextEnabled: Bool {
        get { defaults?.bool(forKey: testTextKey) ?? false }
        set { defaults?.set(newValue, forKey: testTextKey) }
    }

    /// 固定测试文字＋当前时间（时间戳每刷一次就更新，证明悬浮窗在活着刷新）。
    static func testText() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss"
        return "悬浮测试 · 桌面歌词 2.0.1 · \(fmt.string(from: Date()))"
    }
}

// MARK: - 1.0.6 诊断：三项判定分离（安装环境／实际权限／显示能力）
// 安装环境由启动时一次判定写进这里，托管复核禁止改它（第 1／2 项）；
// 显示能力由复核或安装环境写进这里；实际权限的实测表见
// EffectiveEntitlements（启动判定＋诊断页刷新各记一次）。
// 模式值：trollstore（巨魔原生）／enhanced-host（增强宿主）／compat（普通签名兼容）／
// probing（待探测，复核还没结论）。
extension LyricStore {

    static let runModeKey = "tlds.runMode"
    static let runModeReasonKey = "tlds.runModeReason"

    /// 安装环境（第 1 项）：trollstore／livecontainer／signature／unknown。
    /// 启动时凭正面证据定一次，之后永不改写；复核只定显示能力。
    static let installEnvironmentKey = "tlds.installEnvironment"
    static let installEnvironmentReasonKey = "tlds.installEnvironmentReason"

    static var installEnvironment: String {
        get { defaults?.string(forKey: installEnvironmentKey) ?? "unknown" }
        set { defaults?.set(newValue, forKey: installEnvironmentKey) }
    }

    static var installEnvironmentReason: String {
        get { defaults?.string(forKey: installEnvironmentReasonKey) ?? "" }
        set { defaults?.set(newValue, forKey: installEnvironmentReasonKey) }
    }

    /// 安装环境中文描述（第 2 项）。注意：LyricStore 同时编进 App 与 Widget
    /// 两个 target，RuntimeEnvironment.swift 只在 App target 里——这里不能
    /// 引用 InstallEnvironment 类型，显示名用字符串 switch 写死（与
    /// RuntimeEnvironment.swift 里 InstallEnvironment.displayName 保持一致；
    /// 自检 §15 有一项专查两边一致）。
    static var installEnvironmentDescription: String {
        switch installEnvironment {
        case "trollstore": return "TrollStore（巨魔）"
        case "livecontainer": return "LiveContainer 宿主"
        case "signature": return "普通签名（沙盒内）"
        case "unknown": return "未确认（权限探测不可用）"
        default: return "未确认"
        }
    }

    /// 显示能力（第 2 项）：nativeHUD／pip／inApp。
    /// 巨魔原生直接定 nativeHUD；宿主／未确认由托管复核定；普通签名直接定 inApp。
    static let displayCapabilityKey = "tlds.displayCapability"
    static let displayCapabilityReasonKey = "tlds.displayCapabilityReason"

    static var displayCapability: String {
        get { defaults?.string(forKey: displayCapabilityKey) ?? "" }
        set { defaults?.set(newValue, forKey: displayCapabilityKey) }
    }

    static var displayCapabilityReason: String {
        get { defaults?.string(forKey: displayCapabilityReasonKey) ?? "" }
        set { defaults?.set(newValue, forKey: displayCapabilityReasonKey) }
    }

    /// 显示能力中文描述（第 2 项）。与上同理：不能引用 DisplayCapability 类型，
    /// 显示名用字符串 switch 写死（与 RuntimeEnvironment.swift 里
    /// DisplayCapability.displayName 保持一致；自检 §15 专查两边一致）。
    static var displayCapabilityDescription: String {
        switch displayCapability {
        case "nativeHUD": return "HUD 守护进程悬浮歌词"
        case "pip": return "PiP 画中画歌词（实验）"
        case "inApp": return "应用内歌词"
        default: return "未定"
        }
    }

    /// 激活前后悬浮窗状态快照的通知名（第 7 项）：Swift 侧发，ObjC 侧
    /// TLDSAppDelegate 接住后记窗口状态（窗口在不在、isHidden、windowScene、frame）。
    /// userInfo 带 tag：激活前／激活成功后。
    static let logFloatingWindowStateNotification = Notification.Name("TLDSLogFloatingWindowState")

    /// 发「记一次悬浮窗状态快照」通知（第 7 项）：tag 为「激活前」或「激活成功后」；
    /// ObjC 侧记窗口状态，「激活前」每进程只记一次（由接住方去重）。
    static func logFloatingWindowState(tag: String) {
        NotificationCenter.default.post(
            name: logFloatingWindowStateNotification,
            object: nil,
            userInfo: ["tag": tag]
        )
    }

    /// 哪一个 LiveContainer 信号命中了（第 1 项的证据行；没命中返回「均无」）。
    /// 注意：Info.plist 键 TLDSLiveContainer 在本工程里从来没设过值，
    /// 所以 plist 这一路信号在单 IPA 里永远不命中（不是 bug，是设计：
    /// 单 IPA 不能把这个键写死 true，否则巨魔机也会被判成宿主）。
    /// build 24：环境变量 LC_HOME_PATH 排第一（旧线信号一，最可靠），
    /// 包路径 /Documents/Applications/ 是旧线信号二。
    static var liveContainerSignalDetail: String {
        var hit: [String] = []
        if ProcessInfo.processInfo.environment["LC_HOME_PATH"] != nil {
            hit.append("环境变量 LC_HOME_PATH 已设")
        }
        if Bundle.main.object(forInfoDictionaryKey: "TLDSLiveContainer") as? Bool == true {
            hit.append("plist 键 TLDSLiveContainer=true")
        }
        if Bundle.main.bundlePath.lowercased().contains("/documents/applications/") {
            hit.append("包路径含 /Documents/Applications/")
        }
        let paths = [Bundle.main.bundlePath, Bundle.main.executablePath ?? "", ProcessInfo.processInfo.arguments.first ?? "", ProcessInfo.processInfo.processName, NSHomeDirectory()]
        if paths.contains(where: { $0.lowercased().contains("livecontainer") }) {
            hit.append("路径／进程名／Home 目录含 livecontainer")
        }
        if paths.contains(where: { $0.lowercased().contains("/lcapps/") }) {
            hit.append("路径含 /lcapps/")
        }
        if NSClassFromString("LCAppDelegate") != nil {
            hit.append("类 LCAppDelegate 存在")
        }
        return hit.isEmpty ? "均无（环境变量未设、plist 键未设、路径无信号、类不存在）" : hit.joined(separator: "、")
    }

    static var runMode: String {
        get { defaults?.string(forKey: runModeKey) ?? "probing" }
        set { defaults?.set(newValue, forKey: runModeKey) }
    }

    static var runModeReason: String {
        get { defaults?.string(forKey: runModeReasonKey) ?? "" }
        set { defaults?.set(newValue, forKey: runModeReasonKey) }
    }

    /// 设置页显示用：模式中文名＋判定依据（没判定出时显示「待探测」）。
    /// trollstore（正面证据已出）与 native-candidate（安装来源未知）是两档，
    /// 不要并成一行（并入 ChatGPT 1.0.6 时它们并成了一行，这里拆开）。
    static var runModeDescription: String {
        switch runMode {
        case "trollstore":
            return "巨魔原生模式"
        case "native-candidate":
            return "原生候选（安装来源未知，实际屏幕可见性未确认）"
        case "enhanced-host":
            return "增强宿主模式（托管检查通过，首选 PiP 实验）"
        case "compat":
            return "普通签名兼容模式（托管检查未通过，应用内歌词）"
        default:
            return "待探测（启动后复核中）"
        }
    }
}
