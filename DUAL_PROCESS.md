# 1.0.6 单包双进程版
一个 IPA，两种环境：独立版（TrollStore）与 LiveContainer 客人版运行时自己判断，不再分两个包。判断见 Lyrics/LyricStore.swift 的 isLiveContainer：LC_HOME_PATH 环境变量（宿主起客人前设）或包体在宿主 Documents/Applications/ 下；都命不中默认独立版。判断结果写进日志（日志页可见当前是独立版还是 LC 客人）。不要用「有没有 TweakLoader.dylib」做信号——客人可关掉注入，hideLiveContainer 也会把它藏起来。
独立版保留原 MediaRemote、FrontBoard、Live Activity、激活机制，在 127.0.0.1:38473 起只读 TCP 服务；LC 客人每秒读歌词快照。两端需分别激活。独立版复制配对码，LC 客人粘贴；请勿公开配对码。未连接时可使用本地歌词。桥接仅同步歌词快照，不同步设置、激活状态或控制音乐。

构建：GitHub Actions 原 build 工作流生成一个 TrollStore IPA（zsign 签名），TrollStore 与 LiveContainer 都导入这一个包。先安装并启动独立版，再在同一台手机的 LiveContainer 里导入同一个包（桥是本机回环，跨手机连不上）。锁屏功能沿用原 Live Activities（16.1+）。旧的双包做法（livecontainer.yml＋build-livecontainer.sh）1.0.6 起作废，已删。

验证范围：Linux Swift parser 语法检查，不是 Xcode 类型检查或真机测试。需要验证：LiveContainer 认不认单包（plist 三键＋Widget＋zsign 签名）、运行时判断在真机上准不准（日志页看模式）、loopback 可达性、后台挂起、宿主网络限制、切歌暂停拖进度、配对失败和重连。连接状态表示收到快照，不保证音乐仍在播放。未连接时旧快照可能仍显示。没有实现系统守护进程，独立版被挂起或杀死时桥不可用。配对码为本机共享秘密，不提供加密或对抗恶意本机进程的保证。
