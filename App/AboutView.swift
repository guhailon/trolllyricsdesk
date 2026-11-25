import SwiftUI
import UIKit

// 关于页：日志、当前版本、加入官方群组。
struct AboutView: View {

    @State private var showCopied = false

    private let qqGroupNumber = "166623677"

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        Form {
            Section(header: Text("关于")) {

                HStack {
                    Text("作者")
                    Spacer()
                    Text("China fly")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("当前版本")
                    Spacer()
                    Text(appVersion)
                        .foregroundColor(.secondary)
                }

                Button {
                    joinQQGroup()
                } label: {
                    HStack {
                        Label("加入官方群组", systemImage: "person.2")
                        Spacer()
                        Text("QQ 群 \(qqGroupNumber)")
                            .foregroundColor(.secondary)
                    }
                }

                Button {
                    openTelegram()
                } label: {
                    HStack {
                        Label("Telegram 频道", systemImage: "paperplane")
                        Spacer()
                        Text("@seadragonjb")
                            .foregroundColor(.secondary)
                    }
                }
            }

            Section {
                NavigationLink {
                    LogView()
                } label: {
                    Label("日志", systemImage: "doc.text")
                }
            }
        }
        .navigationTitle("关于")
        .alert("已复制群号", isPresented: $showCopied) {
            Button("好", role: .cancel) { }
        } message: {
            Text("QQ 群号 \(qqGroupNumber) 已复制，打开 QQ 搜索群号加入。")
        }
    }

    // 频道是私密频道，没有公开用户名，@seadragonjb 打不开频道；
    // 改走频道邀请链接：先跳 Telegram App（tg://join），没装就退回网页版。
    private func openTelegram() {
        let appURL = URL(string: "tg://join?invite=I-I8aw7HUAw1NGY9")!
        let webURL = URL(string: "https://t.me/+I-I8aw7HUAw1NGY9")!
        UIApplication.shared.open(appURL, options: [:]) { success in
            if !success {
                UIApplication.shared.open(webURL)
            }
        }
    }

    // 点一下先跳 QQ 的群名片；手机没装 QQ 就复制群号，提示去 QQ 里搜。
    private func joinQQGroup() {
        guard let url = URL(string: "mqqapi://card/show_pslcard?src_type=internal&version=1&uin=\(qqGroupNumber)&card_type=group&source=qrcode") else {
            UIPasteboard.general.string = qqGroupNumber
            showCopied = true
            return
        }
        UIApplication.shared.open(url, options: [:]) { success in
            if !success {
                UIPasteboard.general.string = self.qqGroupNumber
                self.showCopied = true
            }
        }
    }
}
