import SwiftUI
import UIKit

/// 登录页。
///
/// 青龙面板的第三方对接方式不是"账号密码"，而是在面板内创建"应用"后拿到
/// Client ID / Client Secret，再用它换取访问令牌。这里如实按这套流程设计。
struct LoginView: View {

    @EnvironmentObject private var store: PanelStore

    @State private var address = ""
    @State private var clientID = ""
    @State private var clientSecret = ""
    @State private var showHelp = false
    @State private var probeState: ProbeState = .idle

    private enum ProbeState: Equatable {
        case idle
        case testing
        case reachable(String)
        case failed(String)
    }

    var body: some View {
        ZStack {
            Theme.groupedBackground.edgesIgnoringSafeArea(.all)

            ScrollView {
                VStack(spacing: 18) {
                    header
                    addressCard
                    credentialCard
                    loginButton
                    helpCard
                }
                .padding(.horizontal, 20)
                .padding(.top, 36)
                .padding(.bottom, 40)
            }
        }
        .onAppear(perform: restoreLastAddress)
    }

    // MARK: - 顶部

    private var header: some View {
        VStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 20)
                .fill(Theme.accent)
                .frame(width: 76, height: 76)
                .overlay(
                    Text("QL")
                        .font(.system(size: 27, weight: .heavy))
                        .foregroundColor(.white)
                )

            Text("青龙面板")
                .font(.system(size: 21, weight: .semibold))
                .foregroundColor(Theme.primaryText)

            Text("在 iPhone 上原生管理定时任务、环境变量与订阅")
                .font(.system(size: 12.5))
                .foregroundColor(Theme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(.bottom, 6)
    }

    // MARK: - 面板地址

    private var addressCard: some View {
        SectionCard("面板地址") {
            VStack(alignment: .leading, spacing: 10) {
                LabeledField(
                    title: "",
                    placeholder: "192.168.1.8:5700 或 https://ql.example.com",
                    text: $address,
                    keyboard: .URL
                )

                if let normalized = APIClient.normalizeBaseURL(address)?.absoluteString,
                   !address.trimmingCharacters(in: .whitespaces).isEmpty {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.turn.down.right")
                            .font(.system(size: 10))
                        Text("将使用 \(normalized)")
                            .font(.system(size: 11.5))
                            .lineLimit(1)
                    }
                    .foregroundColor(Theme.tertiaryText)
                }

                HStack(spacing: 10) {
                    Button(action: testConnection) {
                        HStack(spacing: 5) {
                            if probeState == .testing {
                                ProgressView().scaleEffect(0.7)
                            } else {
                                Image(systemName: "wifi")
                                    .font(.system(size: 12))
                            }
                            Text("测试连接")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundColor(Theme.info)
                    }
                    .disabled(probeState == .testing || address.isEmpty)

                    switch probeState {
                    case .reachable(let text):
                        Label(text, systemImage: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.success)
                    case .failed(let text):
                        Label(text, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.danger)
                            .lineLimit(2)
                    default:
                        EmptyView()
                    }

                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: - 应用凭据

    private var credentialCard: some View {
        SectionCard("应用凭据") {
            VStack(alignment: .leading, spacing: 12) {
                LabeledField(title: "Client ID", placeholder: "例如 AbC1dEf2GhI3", text: $clientID)
                LabeledField(title: "Client Secret", placeholder: "粘贴应用密钥", text: $clientSecret, isSecure: true)

                Text("凭据保存在系统钥匙串中，不会上传到任何第三方服务器。")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.tertiaryText)
            }
        }
    }

    // MARK: - 登录

    private var loginButton: some View {
        VStack(spacing: 10) {
            PrimaryButton(
                title: store.isAuthenticating ? "正在连接面板…" : "登录",
                icon: store.isAuthenticating ? nil : "arrow.right.circle.fill",
                isLoading: store.isAuthenticating,
                isEnabled: !address.isEmpty && !clientID.isEmpty && !clientSecret.isEmpty
            ) {
                Task {
                    await store.signIn(
                        address: address,
                        clientID: clientID,
                        clientSecret: clientSecret
                    )
                }
            }

            if let connection = store.connection, !store.isAuthenticated {
                Text(connection.expirationText)
                    .font(.system(size: 11.5))
                    .foregroundColor(Theme.warning)
            }
        }
    }

    // MARK: - 帮助

    private var helpCard: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 8) {
                Button(action: { showHelp.toggle() }) {
                    HStack {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 13))
                        Text("如何获取 Client ID 与 Client Secret？")
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                        Image(systemName: showHelp ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(Theme.accent)
                }

                if showHelp {
                    VStack(alignment: .leading, spacing: 6) {
                        helpStep("1", "在浏览器打开青龙面板，进入「系统设置 → 应用设置」")
                        helpStep("2", "点击「添加应用」，填写名称，并勾选需要管理的模块权限")
                        helpStep("3", "保存后列表里会出现 Client ID 与 Client Secret，复制过来即可")
                        helpStep("4", "若提示权限不足，回到面板为该应用补勾对应模块的权限")
                    }
                    .padding(.top, 2)

                    Text("注意：令牌默认 30 天有效；在面板上重置应用密钥会让已发出的令牌立即失效，届时重新登录一次即可。")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.secondaryText)
                        .padding(.top, 2)
                }
            }
        }
    }

    private func helpStep(_ index: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(index)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 16, height: 16)
                .background(Circle().fill(Theme.accent))
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(Theme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - 行为

    private func restoreLastAddress() {
        guard address.isEmpty, let saved = store.connection else { return }
        address = saved.rawAddress
        clientID = saved.clientID
    }

    private func testConnection() {
        guard let url = APIClient.normalizeBaseURL(address) else {
            probeState = .failed("地址格式不正确")
            return
        }
        probeState = .testing
        Task {
            do {
                _ = try await APIClient.shared.probe(host: url)
                probeState = .reachable("地址可达")
            } catch {
                probeState = .failed((error as? APIError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }
}

// MARK: - 带标题的输入框

struct LabeledField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var isSecure: Bool = false
    var keyboard: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !title.isEmpty {
                Text(title)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.secondaryText)
            }

            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .textFieldStyle(PlainTextFieldStyle())
            .font(.system(size: 14))
            .foregroundColor(Theme.primaryText)
            .autocapitalization(.none)
            .disableAutocorrection(true)
            .keyboardType(keyboard)
            .padding(.horizontal, 10)
            .padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 9).fill(Theme.fieldBackground))
        }
    }
}
