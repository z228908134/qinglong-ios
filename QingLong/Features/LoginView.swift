import SwiftUI
import UIKit

/// 登录页。
///
/// 直接使用青龙面板网页端同一套账号密码。用户令牌拥有全部模块权限，
/// 省去创建 OpenAPI 应用、逐项勾选 scopes 的麻烦；令牌失效时客户端
/// 会用保存的账号密码自动续期，无需反复登录。
struct LoginView: View {

    @EnvironmentObject private var store: PanelStore

    @State private var address = ""
    @State private var username = ""
    @State private var password = ""
    /// 面板开启两步验证时才出现（登录返回 code 420 后显示）。
    @State private var twoFactorCode = ""
    @State private var needTwoFactor = false
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
                        .font(.system(size: Theme.font(27), weight: .heavy))
                        .foregroundColor(.white)
                )

            Text("青龙面板")
                .font(.system(size: Theme.font(21), weight: .semibold))
                .foregroundColor(Theme.primaryText)

            Text("在 iPhone 上原生管理定时任务、环境变量与订阅")
                .font(.system(size: Theme.font(12.5)))
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
                            .font(.system(size: Theme.font(10)))
                        Text("将使用 \(normalized)")
                            .font(.system(size: Theme.font(11.5)))
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
                                    .font(.system(size: Theme.font(12)))
                            }
                            Text("测试连接")
                                .font(.system(size: Theme.font(13), weight: .medium))
                        }
                        .foregroundColor(Theme.info)
                    }
                    .disabled(probeState == .testing || address.isEmpty)

                    switch probeState {
                    case .reachable(let text):
                        Label(text, systemImage: "checkmark.circle.fill")
                            .font(.system(size: Theme.font(12)))
                            .foregroundColor(Theme.success)
                    case .failed(let text):
                        Label(text, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: Theme.font(12)))
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

    // MARK: - 账号密码

    private var credentialCard: some View {
        SectionCard("面板账号") {
            VStack(alignment: .leading, spacing: 12) {
                LabeledField(title: "用户名", placeholder: "面板网页端的登录用户名", text: $username)
                LabeledField(title: "密码", placeholder: "面板网页端的登录密码", text: $password, isSecure: true)

                if needTwoFactor {
                    LabeledField(title: "两步验证码", placeholder: "6 位动态验证码", text: $twoFactorCode, keyboard: .numberPad)
                    BannerView(text: "该账号开启了两步验证，请输入验证器 App 里的当前动态码后重新登录。", tone: .info)
                }

                Text("账号密码保存在系统钥匙串中，仅用于令牌失效后自动续期，不会上传到任何第三方服务器。")
                    .font(.system(size: Theme.font(11)))
                    .foregroundColor(Theme.tertiaryText)
            }
        }
    }

    // MARK: - 登录

    private var loginButton: some View {
        VStack(spacing: 10) {
            if needTwoFactor {
                Text("已开启两步验证，输入动态码后再点登录")
                    .font(.system(size: Theme.font(11.5)))
                    .foregroundColor(Theme.warning)
            }

            PrimaryButton(
                title: store.isAuthenticating ? "正在连接面板…" : (needTwoFactor ? "验证并登录" : "登录"),
                icon: store.isAuthenticating ? nil : "arrow.right.circle.fill",
                isLoading: store.isAuthenticating,
                isEnabled: !address.isEmpty && !username.isEmpty && !password.isEmpty
                    && (!needTwoFactor || !twoFactorCode.isEmpty)
            ) {
                Task {
                    let outcome = await store.signIn(
                        address: address,
                        username: username,
                        password: password,
                        twoFactorCode: needTwoFactor ? twoFactorCode : nil
                    )
                    if outcome == .needTwoFactor {
                        needTwoFactor = true
                    }
                }
            }

            if let connection = store.connection, !store.isAuthenticated {
                Text(connection.expirationText)
                    .font(.system(size: Theme.font(11.5)))
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
                            .font(.system(size: Theme.font(13)))
                        Text("登录遇到问题？")
                            .font(.system(size: Theme.font(13), weight: .medium))
                        Spacer()
                        Image(systemName: showHelp ? "chevron.up" : "chevron.down")
                            .font(.system(size: Theme.font(11)))
                    }
                    .foregroundColor(Theme.accent)
                }

                if showHelp {
                    VStack(alignment: .leading, spacing: 6) {
                        helpStep("1", "使用青龙面板网页端同一套账号密码，无需创建 OpenAPI 应用")
                        helpStep("2", "填 IP 地址时会自动补全 http:// 与默认端口 5700")
                        helpStep("3", "登录失败时检查密码是否修改过、账号是否被禁用")
                        helpStep("4", "开启了两步验证的账号，需要额外输入验证器里的 6 位动态码")
                    }
                    .padding(.top, 2)

                    Text("令牌失效后客户端会用保存的账号密码自动续期；在面板上修改密码后需要重新登录一次。")
                        .font(.system(size: Theme.font(11)))
                        .foregroundColor(Theme.secondaryText)
                        .padding(.top, 2)
                }
            }
        }
    }

    private func helpStep(_ index: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(index)
                .font(.system(size: Theme.font(10), weight: .bold))
                .foregroundColor(.white)
                .frame(width: 16, height: 16)
                .background(Circle().fill(Theme.accent))
            Text(text)
                .font(.system(size: Theme.font(12)))
                .foregroundColor(Theme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - 行为

    private func restoreLastAddress() {
        guard address.isEmpty, let saved = store.connection else { return }
        address = saved.rawAddress
        username = saved.username
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
                    .font(.system(size: Theme.font(12)))
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
            .font(.system(size: Theme.font(14)))
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
