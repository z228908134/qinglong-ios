//
//  LoginView.swift
//  登录页：面板地址 + 账号密码 + 两步验证
//

import SwiftUI

struct LoginView: View {

    private enum Field: Hashable {
        case server, username, password, code
    }

    @EnvironmentObject private var session: SessionStore

    @State private var password = ""
    @State private var code = ""
    @State private var needsTwoFactor = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @FocusState private var focus: Field?

    private var canSubmit: Bool {
        guard !session.serverAddress.isEmpty, !session.username.isEmpty, !password.isEmpty else { return false }
        if needsTwoFactor { return code.count >= 6 }
        return true
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    header

                    Card {
                        field(title: "面板地址", symbol: "server.rack") {
                            TextField("http://192.168.1.10:5700", text: $session.serverAddress)
                                .keyboardType(.URL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .focused($focus, equals: .server)
                                .submitLabel(.next)
                                .onSubmit { focus = .username }
                        }

                        Divider()

                        field(title: "用户名", symbol: "person") {
                            TextField("admin", text: $session.username)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .focused($focus, equals: .username)
                                .submitLabel(.next)
                                .onSubmit { focus = .password }
                        }

                        Divider()

                        field(title: "密码", symbol: "lock") {
                            SecureField("登录密码", text: $password)
                                .textContentType(.password)
                                .focused($focus, equals: .password)
                                .submitLabel(needsTwoFactor ? .next : .go)
                                .onSubmit {
                                    if needsTwoFactor { focus = .code } else { Task { await submit() } }
                                }
                        }

                        if needsTwoFactor {
                            Divider()
                            field(title: "动态码", symbol: "shield.lefthalf.filled") {
                                TextField("6 位验证码", text: $code)
                                    .keyboardType(.numberPad)
                                    .focused($focus, equals: .code)
                            }
                        }
                    }

                    if let errorMessage {
                        ErrorBanner(message: errorMessage)
                    }

                    Button {
                        Task { await submit() }
                    } label: {
                        HStack(spacing: 8) {
                            if isSubmitting { ProgressView().tint(.white) }
                            Text(needsTwoFactor ? "验证并登录" : "登录")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(canSubmit ? Color.accentColor : Color.gray.opacity(0.35),
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .foregroundStyle(.white)
                    }
                    .disabled(!canSubmit || isSubmitting)

                    footer
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    // MARK: 子视图

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "bolt.horizontal.circle.fill")
                .font(.system(size: 54))
                .foregroundStyle(Color.accentColor)
            Text("青龙管家")
                .font(.system(size: 22, weight: .bold))
            Text("连接你的青龙面板，随时随地看任务")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 24)
        .padding(.bottom, 4)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("凭据会保存在本机钥匙串，不会上传到任何第三方", systemImage: "lock.shield")
            Label("面板地址需带 http:// 或 https:// 与端口号", systemImage: "info.circle")
            Label("若使用明文 http，密码与令牌会以明文在网络中传输，建议给面板配 HTTPS", systemImage: "exclamationmark.triangle")
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 6)
    }

    private func field<Content: View>(title: String,
                                      symbol: String,
                                      @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .leading)
            content()
                .font(.system(size: 14))
        }
    }

    // MARK: 提交

    private func submit() async {
        guard !isSubmitting, canSubmit else { return }
        errorMessage = nil
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            if needsTwoFactor {
                try await session.signInWithTwoFactor(password: password, code: code)
            } else {
                try await session.signIn(password: password)
            }
        } catch let error as QLAPIError {
            if error == .twoFactorRequired {
                needsTwoFactor = true
                code = ""
                focus = .code
                errorMessage = "该账号已开启两步验证，请输入身份验证器上的 6 位动态码"
            } else {
                errorMessage = error.localizedDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
