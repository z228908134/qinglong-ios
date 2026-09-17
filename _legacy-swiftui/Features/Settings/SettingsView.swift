//
//  SettingsView.swift
//  我的：账号信息、面板信息、服务器地址、退出登录
//

import SwiftUI

struct SettingsView: View {

    @EnvironmentObject private var session: SessionStore

    @State private var draftServer = ""
    @State private var showServerAlert = false
    @State private var confirmSignOut = false

    private let clientVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    avatar
                    VStack(alignment: .leading, spacing: 3) {
                        Text(session.username)
                            .font(.system(size: 16, weight: .semibold))
                        Text(session.serverAddress)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }

            Section("账号") {
                LabeledContent("用户名", value: session.username)
                LabeledContent("两步验证", value: session.twoFactorActivated ? "已开启" : "未开启")
                LabeledContent("登录状态", value: session.client == nil ? "未登录" : "已登录")
            }

            Section {
                LabeledContent("面板版本", value: session.systemInfo?.version ?? "未知")
                LabeledContent("分支", value: session.systemInfo?.branch ?? "未知")
                Button {
                    draftServer = session.serverAddress
                    showServerAlert = true
                } label: {
                    HStack {
                        Text("服务器地址")
                        Spacer()
                        Text(session.serverAddress)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .tint(.primary)
            } header: {
                Text("面板")
            } footer: {
                Text("令牌是按面板签发的，修改地址后需要重新登录。")
            }

            Section("关于") {
                LabeledContent("客户端版本", value: clientVersion)
                LabeledContent("适配面板", value: "青龙 v2.21.x")
                Link(destination: URL(string: "https://github.com/whyour/qinglong")!) {
                    HStack {
                        Text("青龙面板开源仓库")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .tint(.primary)
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("安全提示：如果面板走的是明文 http，登录密码与令牌会在网络中明文传输。建议给面板配置 HTTPS 或只在可信网络中使用。")
                    Text("本客户端不收集任何数据，令牌保存在系统钥匙串中。")
                }
                .font(.system(size: 11))
            }

            Section {
                Button(role: .destructive) {
                    confirmSignOut = true
                } label: {
                    Text("退出登录").frame(maxWidth: .infinity)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("我的")
        .alert("修改面板地址", isPresented: $showServerAlert) {
            TextField("http://192.168.1.10:5700", text: $draftServer)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("保存") { applyServer() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("需要带 http:// 或 https:// 以及端口号。")
        }
        .confirmationDialog("确认退出登录？",
                            isPresented: $confirmSignOut,
                            titleVisibility: .visible) {
            Button("退出登录", role: .destructive) {
                Task { await session.signOut() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("本机保存的令牌会被清除。")
        }
    }

    private var avatar: some View {
        Group {
            if let path = session.avatarPath, !path.isEmpty,
               let base = session.currentBaseURL,
               let url = URL(string: base.absoluteString + "/api/static/" + path) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    fallbackAvatar
                }
            } else {
                fallbackAvatar
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(Circle())
    }

    private var fallbackAvatar: some View {
        ZStack {
            Circle().fill(Color.accentColor.opacity(0.15))
            Image(systemName: "person.fill")
                .font(.system(size: 22))
                .foregroundStyle(Color.accentColor)
        }
    }

    private func applyServer() {
        let value = draftServer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value != session.serverAddress else { return }
        session.updateServerAddress(value)
        Task {
            await session.signOut(silent: true)
            session.show("地址已更新，请重新登录")
        }
    }
}
