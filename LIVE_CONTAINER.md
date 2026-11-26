# LiveContainer 兼容实验版（基线 1.0.3）
原 TrollStore 构建不变。独立工作流 Build LiveContainer，或 macOS 执行 bash scripts/build-livecontainer.sh，下载 dist 中 IPA 后在 LiveContainer 中导入并由宿主签名。文件选择器异常时尝试 Fix File Picker。
LC 构建关闭系统 Shell、私有窗口 category、静音保活、Widget 刷新和 Live Activity；使用标准偏好存储，保留授权服务和激活流程。主界面支持应用内歌词、手动暂停/继续/归零；MediaRemote 仍为尽力读取，宿主不授权时用手动搜索或导入。自动检测可能覆盖手动播放，必要时在设置停止检测。
验证：Swift 语法解析及 shell 语法检查；未执行 Xcode 编译、签名或真机运行。原工程私有框架链接设置保留，可能需要进一步精简；未验证 LiveContainer 的偏好隔离、网络激活及导入行为。该 IPA 不提供全局悬浮或锁屏歌词。
