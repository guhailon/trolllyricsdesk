import SwiftUI
import WidgetKit

/// 激活页入口（1.0.3）：启动时读 App Group 的激活标记，未激活就全屏显示
/// 激活页，不进主界面；激活成功写标记后 @AppStorage 实时刷新，直接进主界面，
/// 不用重启。整个 App 第一次打开就要码；码不对不放行，没网也不放行。
struct ActivationGateView<Content: View>: View {

    @AppStorage(ActivationStore.activatedKey, store: UserDefaults(suiteName: LyricStore.groupID))
    private var activated = false

    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        if activated {
            content
        } else {
            ActivationView()
        }
    }
}

/// 激活失败分两种，提示也分两种，绝不混着说：
/// - 码不对（服务端 valid == false）→「激活码不正确」
/// - 没网／服务端不通／HTTP 非 200／回包解不出 →「需要联网激活」
enum ActivationError: Error {
    case wrongCode
    case needsNetwork
}

/// 服务端回包：{"valid": true, "type": "master"|"code"} 或 {"valid": false}。
private struct ActivationResponse: Decodable {
    let valid: Bool
    let type: String?
}

enum ActivationVerifier {

    /// 码先 trim 再大写（服务端同样不分大小写，两边一致）。
    static func normalized(_ code: String) -> String {
        code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    /// 成功返回激活类型（"master"／"code"）；码不对抛 .wrongCode，
    /// 没网或服务端不通抛 .needsNetwork。调用处绝不放行。
    /// URLSession.shared.data(for:) 是 iOS 15.0+ 的 API，MinOS 15.0 能用。
    static func verify(code: String) async throws -> String {
        let normalizedCode = normalized(code)
        guard let url = URL(string: ActivationStore.verifyURLString) else {
            throw ActivationError.needsNetwork
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        request.httpBody = try JSONSerialization.data(
            withJSONObject: ["code": normalizedCode]
        )
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ActivationError.needsNetwork
        }
        guard let http = response as? HTTPURLResponse,
              http.statusCode == 200 else {
            throw ActivationError.needsNetwork
        }
        guard let decoded = try? JSONDecoder().decode(
            ActivationResponse.self,
            from: data
        ) else {
            throw ActivationError.needsNetwork
        }
        guard decoded.valid, let type = decoded.type else {
            throw ActivationError.wrongCode
        }
        return type
    }
}

/// 激活页：输码框＋激活按钮，全屏显示。背景与主界面共用 AppBackgroundView。
/// 验过后把激活标记＋类型写进 App Group（tld.activated=true、
/// tld.activationType=master/code），@AppStorage 实时切到主界面；
/// 同时刷新小组件时间轴，未激活的占位立即换成正常内容。
/// 日志只记「成功／码不正确／网络失败」，绝不记码值。
struct ActivationView: View {

    @State private var code = ""
    @State private var isVerifying = false
    @State private var message: String?
    @State private var messageIsError = true

    var body: some View {
        ZStack {
            AppBackgroundView()

            ScrollView {
                VStack(spacing: 24) {

                    Text("桌面歌词")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.top, 80)

                    Text("首次使用需要激活码")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.85))

                    VStack(spacing: 16) {
                        TextField("输入激活码", text: $code)
                            .autocapitalization(.allCharacters)
                            .disableAutocorrection(true)
                            .textFieldStyle(.roundedBorder)

                        Button {
                            Task { await activate() }
                        } label: {
                            Text(isVerifying ? "激活中…" : "激活")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.purple)
                                .foregroundColor(.white)
                                .cornerRadius(15)
                        }
                        .disabled(
                            code.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            ).isEmpty || isVerifying
                        )

                        if let message = message {
                            Text(message)
                                .font(.footnote)
                                .foregroundColor(
                                    messageIsError
                                        ? .red
                                        : .green
                                )
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(20)

                    Text("激活需要联网；激活码只在服务端校验，不会保存在本机。")
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                .padding()
            }
        }
    }

    private func activate() async {
        guard !isVerifying else { return }
        isVerifying = true
        message = nil
        defer { isVerifying = false }
        do {
            let type = try await ActivationVerifier.verify(code: code)
            ActivationStore.markActivated(type: type)
            if !LyricStore.isLiveContainer { WidgetCenter.shared.reloadAllTimelines() }
            LyricLogger.log("激活成功（\(type)）")
        } catch ActivationError.wrongCode {
            message = "激活码不正确，请重新输入"
            messageIsError = true
            LyricLogger.log("激活失败：码不正确")
        } catch {
            message = "需要联网激活，请检查网络后重试"
            messageIsError = true
            LyricLogger.log("激活失败：网络或服务不可达")
        }
    }
}
