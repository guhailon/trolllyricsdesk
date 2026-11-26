# 1.0.5 双进程实验版
独立版保留原 MediaRemote、FrontBoard、Live Activity、激活机制。LC 版关闭自身检测和系统窗口，使用只读 TCP 127.0.0.1:38473 配对桥；每秒读取歌词快照。两端需分别激活。独立版复制配对码，LC 版粘贴；请勿公开配对码。未连接时可使用本地歌词。桥接仅同步歌词快照，不同步设置、激活状态或控制音乐。

构建：GitHub Actions 原 build 工作流生成 TrollStore IPA；Build LiveContainer 工作流生成 LC IPA。先安装并启动独立版，再导入 LC 版。锁屏功能沿用原 Live Activities（16.1+）。

验证范围：Linux Swift parser 和 bash 语法检查，不是 Xcode 类型检查或真机测试。需要验证 loopback 可达性、后台挂起、宿主网络限制、FrontBoard 和 Live Activities、切歌暂停拖进度、配对失败和重连。连接状态表示收到快照，不保证音乐仍在播放。未连接时旧快照可能仍显示。没有实现系统守护进程，独立版被挂起或杀死时桥不可用。配对码为本机共享秘密，不提供加密或对抗恶意本机进程的保证。
