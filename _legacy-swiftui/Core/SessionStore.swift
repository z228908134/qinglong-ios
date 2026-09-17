//
//  SessionStore.swift
//  全局登录态 + 服务器配置 + 轻提示
//

import Foundation
import SwiftUI

@MainActor
final class SessionStore: ObservableObject {

    enum Phase: Equatable {
        case restoring
        case loggedOut
        case loggedIn
    }

    struct Toast: Identifiable, Equatable {
        let id = UUID()
        let text: String
        let isError: Bool
    }

    // MARK: 对外状态

    @Published private(set) var phase: Phase = .restoring
    @Published var serverAddress: String
    @Published var username: String
    @Published private(set) var avatarPath: String?
    @Published private(set) var systemInfo: QLSystemInfo?
    @Published private(set) var twoFactorActivated = false
    @Published var toast: Toast?

    /// 登录后可用；未登录时为 nil
    @Published private(set) var client: APIClient?

    private static let serverKey = "ql.serverAddress"
    private static let usernameKey = "ql.username"
    private static let tokenKey = "ql.token"

    /// 首次启动时预填的地址（就是这台面板）
    static let fallbackServer = ""   // 不预填：这份代码会进仓库，写死 IP 等于公开面板地址

    init() {
        serverAddress = UserDefaults.standard.string(forKey: Self.serverKey) ?? Self.fallbackServer
        username = UserDefaults.standard.string(forKey: Self.usernameKey) ?? "admin"
    }

    // MARK: 生命周期

    /// 冷启动时尝试用钥匙串里的 token 直接进入
    func restore() async {
        guard phase == .restoring else { return }

        guard let baseURL = APIClient.normalizedBaseURL(from: serverAddress),
              let saved = KeychainStore.read(key: Self.tokenKey),
              !saved.isEmpty
        else {
            phase = .loggedOut
            return
        }

        let api = APIClient(baseURL: baseURL, token: saved)
        do {
            let user = try await api.currentUser()
            client = api
            apply(user: user)
            systemInfo = try? await api.systemInfo()
            phase = .loggedIn
        } catch let error as QLAPIError {
            if error.isUnauthorized {
                KeychainStore.delete(key: Self.tokenKey)
            }
            client = nil
            phase = .loggedOut
            show(error.localizedDescription, isError: true)
        } catch {
            client = nil
            phase = .loggedOut
            show(error.localizedDescription, isError: true)
        }
    }

    // MARK: 登录

    /// 账号密码登录。若面板开了两步验证，会抛出 `QLAPIError.twoFactorRequired`。
    func signIn(password: String) async throws {
        let api = try makeAnonymousClient()
        let result = try await api.login(username: username, password: password)
        await finishLogin(result: result, baseURL: api.baseURL)
    }

    /// 两步验证登录
    func signInWithTwoFactor(password: String, code: String) async throws {
        let api = try makeAnonymousClient()
        let result = try await api.twoFactorLogin(username: username, password: password, code: code)
        await finishLogin(result: result, baseURL: api.baseURL)
    }

    private func makeAnonymousClient() throws -> APIClient {
        guard let baseURL = APIClient.normalizedBaseURL(from: serverAddress) else {
            throw QLAPIError.invalidURL
        }
        return APIClient(baseURL: baseURL, token: nil)
    }

    private func finishLogin(result: QLLoginResult, baseURL: URL) async {
        KeychainStore.save(result.token, key: Self.tokenKey)
        UserDefaults.standard.set(serverAddress, forKey: Self.serverKey)
        UserDefaults.standard.set(username, forKey: Self.usernameKey)

        let api = APIClient(baseURL: baseURL, token: result.token)
        client = api
        if let user = try? await api.currentUser() {
            apply(user: user)
        }
        systemInfo = try? await api.systemInfo()
        phase = .loggedIn
        show("登录成功")
    }

    private func apply(user: QLUser) {
        if let name = user.username, !name.isEmpty {
            username = name
            UserDefaults.standard.set(name, forKey: Self.usernameKey)
        }
        avatarPath = user.avatar
        twoFactorActivated = user.twoFactorActivated ?? false
    }

    // MARK: 登出 / 切换服务器

    func signOut(silent: Bool = false) async {
        if let client {
            try? await client.logout()
        }
        KeychainStore.delete(key: Self.tokenKey)
        client = nil
        avatarPath = nil
        systemInfo = nil
        twoFactorActivated = false
        phase = .loggedOut
        if !silent { show("已退出登录") }
    }

    /// 修改面板地址：token 是按面板签发的，换地址必须重新登录
    func updateServerAddress(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        serverAddress = trimmed
        UserDefaults.standard.set(trimmed, forKey: Self.serverKey)
    }

    var currentBaseURL: URL? {
        APIClient.normalizedBaseURL(from: serverAddress)
    }

    // MARK: 工具

    func show(_ text: String, isError: Bool = false) {
        toast = Toast(text: text, isError: isError)
    }

    /// 取客户端，未登录直接抛错，省掉一堆 optional 解包
    func requireClient() throws -> APIClient {
        guard let client else { throw QLAPIError.unauthorized("登录已失效，请重新登录") }
        return client
    }

    /// 统一处理业务错误：登录失效时自动踢回登录页
    func handle(_ error: Error, context: String) {
        if let apiError = error as? QLAPIError {
            show("\(context)：\(apiError.localizedDescription)", isError: true)
            if apiError.isUnauthorized {
                Task { await signOut(silent: true) }
            }
        } else {
            show("\(context)：\(error.localizedDescription)", isError: true)
        }
    }
}
