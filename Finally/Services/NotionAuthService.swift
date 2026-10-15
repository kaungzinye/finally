import Foundation
import UIKit
import AuthenticationServices
import SwiftData

@Observable
final class NotionAuthService: NSObject {
    var isAuthenticating = false
    var errorMessage: String?
    private var webAuthenticationSession: ASWebAuthenticationSession?
    private let urlSession: URLSession
    private let saveToken: (String) throws -> Void

    init(
        urlSession: URLSession = .shared,
        saveToken: @escaping (String) throws -> Void = KeychainHelper.saveNotionToken
    ) {
        self.urlSession = urlSession
        self.saveToken = saveToken
        super.init()
    }

    // MARK: - OAuth URL

    func buildAuthorizationURL() -> URL? {
        var components = URLComponents(string: "https://api.notion.com/v1/oauth/authorize")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: AppConstants.notionOAuthClientID),
            URLQueryItem(name: "redirect_uri", value: AppConstants.notionOAuthRedirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "owner", value: "user"),
        ]
        return components?.url
    }

    // MARK: - Start OAuth Flow

    /// Presents an in-app auth sheet via ASWebAuthenticationSession.
    /// Notion auth → Vercel callback → finally:// redirect → session intercepts → token exchange.
    @MainActor
    func startOAuthFlow(modelContext: ModelContext) async -> Bool {
        guard !isAuthenticating else { return false }
        guard let url = buildAuthorizationURL() else {
            errorMessage = "Failed to build authorization URL."
            return false
        }

        isAuthenticating = true
        errorMessage = nil
        defer {
            isAuthenticating = false
            webAuthenticationSession = nil
        }

        do {
            let callbackURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
                let session = ASWebAuthenticationSession(
                    url: url,
                    callbackURLScheme: AppConstants.urlScheme
                ) { callbackURL, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let callbackURL {
                        continuation.resume(returning: callbackURL)
                    } else {
                        continuation.resume(throwing: AuthError.noCallback)
                    }
                }
                session.presentationContextProvider = self
                session.prefersEphemeralWebBrowserSession = false
                webAuthenticationSession = session
                if !session.start() {
                    continuation.resume(throwing: AuthError.cannotStart)
                }
            }

            guard let code = extractAuthCode(from: callbackURL) else {
                errorMessage = "No authorization code in callback."
                return false
            }

            return await exchangeAndStore(code: code, modelContext: modelContext)
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - Extract Code

    func extractAuthCode(from url: URL) -> String? {
        guard url.scheme == AppConstants.urlScheme,
              url.host == "oauth-callback" else { return nil }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        guard let code = components?.queryItems?.first(where: { $0.name == "code" })?.value,
              !code.isEmpty else { return nil }
        return code
    }

    // MARK: - Token Exchange

    struct TokenResponse: Decodable {
        let accessToken: String
        let workspaceId: String
        let workspaceName: String
        let botId: String

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case workspaceId = "workspace_id"
            case workspaceName = "workspace_name"
            case botId = "bot_id"
        }
    }

    @MainActor
    func completeOAuth(withCode code: String, modelContext: ModelContext) async -> Bool {
        guard !isAuthenticating else { return false }
        isAuthenticating = true
        errorMessage = nil
        defer { isAuthenticating = false }
        return await exchangeAndStore(code: code, modelContext: modelContext)
    }

    @MainActor
    private func exchangeAndStore(code: String, modelContext: ModelContext) async -> Bool {
        do {
            let tokenResponse = try await exchangeCodeForToken(code: code)
            try storeSession(tokenResponse: tokenResponse, modelContext: modelContext)
            return true
        } catch {
            print("[OAuth] completeOAuth error: \(error)")
            errorMessage = error.localizedDescription
            return false
        }
    }

    func exchangeCodeForToken(code: String) async throws -> TokenResponse {
        guard let url = URL(string: AppConstants.tokenExchangeEndpoint) else {
            throw AuthError.invalidTokenEndpoint
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["code": code])

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.tokenExchangeFailed
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw AuthError.tokenExchangeFailed
        }

        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    // MARK: - Store Session

    @MainActor
    func storeSession(tokenResponse: TokenResponse, modelContext: ModelContext) throws {
        let existing = try modelContext.fetch(FetchDescriptor<UserSession>())
        let notionSessions = existing.filter { $0.providerIdentity == .notion }
        let session = notionSessions.first { $0.workspaceId == tokenResponse.workspaceId }
            ?? UserSession(
                workspaceId: tokenResponse.workspaceId,
                workspaceName: tokenResponse.workspaceName,
                providerIdentity: .notion
            )
        try saveToken(tokenResponse.accessToken)

        for otherSession in notionSessions where otherSession.id != session.id {
            modelContext.delete(otherSession)
        }
        existing.forEach { $0.isSelected = false }
        session.workspaceName = tokenResponse.workspaceName
        session.isSelected = true
        if session.modelContext == nil { modelContext.insert(session) }
        try modelContext.save()
    }

    // MARK: - Errors

    enum AuthError: LocalizedError {
        case noCallback
        case cannotStart
        case invalidTokenEndpoint
        case tokenExchangeFailed

        var errorDescription: String? {
            switch self {
            case .noCallback: return "No response from Notion."
            case .cannotStart: return "The Notion sign-in sheet could not open. Please try again."
            case .invalidTokenEndpoint: return "Invalid token exchange URL."
            case .tokenExchangeFailed: return "Failed to exchange authorization code."
            }
        }
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension NotionAuthService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first else {
            return ASPresentationAnchor()
        }
        return window
    }
}
