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

                NavigationLink {
                    LogView()
                } label: {
                    Label("日志", systemImage: "doc.text")
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
                    if let url = URL(string: "https://t.me/seadragonjb") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    HStack {
                        Label("Telegram 频道", systemImage: "paperplane")
                        Spacer()
                        Text("@seadragonjb")
                            .foregroundColor(.secondary)
                    }
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
