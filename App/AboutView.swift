import SwiftUI
import UIKit

// 关于页：当前版本、加入官方群组。
// 2.0.2：日志入口行已删（Lee 定）——只删这一行，LyricLogger 写日志文件
// 的逻辑不动，主页面「查看守护进程日志」也不动。
struct AboutView: View {

    @State private var showCopied = false

    private let qqGroupNumber = "166623677"

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    var body: some View {
        ZStack {
            AppBackgroundView()

            ScrollView {
                VStack(spacing: 20) {

                    Text("关于")
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.55))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 4)

                    VStack(spacing: 0) {
                        HStack {
                            Text("作者")
                                .foregroundColor(.white)
                            Spacer()
                            Text("China fly")
                                .foregroundColor(.white.opacity(0.65))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)

                        Divider()
                            .background(Color.white.opacity(0.12))

                        HStack {
                            Text("当前版本")
                                .foregroundColor(.white)
                            Spacer()
                            Text(appVersion)
                                .foregroundColor(.white.opacity(0.65))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)

                        Divider()
                            .background(Color.white.opacity(0.12))

                        Button {
                            joinQQGroup()
                        } label: {
                            HStack {
                                Label("加入官方群组", systemImage: "person.2")
                                Spacer()
                                Text("QQ 群 \(qqGroupNumber)")
                                    .foregroundColor(.white.opacity(0.65))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }

                        Divider()
                            .background(Color.white.opacity(0.12))

                        Button {
                            openTelegram()
                        } label: {
                            HStack {
                                Label("Telegram 频道", systemImage: "paperplane")
                                Spacer()
                                Text("@Guhailon")
                                    .foregroundColor(.white.opacity(0.65))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }
                    }
                    .background(.ultraThinMaterial)
                    .cornerRadius(15)
                }
                .padding()
            }
        }
        .navigationTitle("关于")
        .alert("已复制群号", isPresented: $showCopied) {
            Button("好", role: .cancel) { }
        } message: {
            Text("QQ 群号 \(qqGroupNumber) 已复制，打开 QQ 搜索群号加入。")
        }
    }

    // 频道已公开，用户名 @Guhailon：先跳 Telegram App（tg://resolve），
    // 没装就退回网页版。
    private func openTelegram() {
        let appURL = URL(string: "tg://resolve?domain=Guhailon")!
        let webURL = URL(string: "https://t.me/Guhailon")!
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
