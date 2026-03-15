import Foundation
import UIKit
import AuthenticationServices
import SwiftData

@Observable
final class NotionAuthService: NSObject {
    var isAuthenticating = false
    var errorMessage: String?

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
        guard let url = buildAuthorizationURL() else {
            errorMessage = "Failed to build authorization URL."
            return false
        }

        isAuthenticating = true
        errorMessage = nil

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
                session.start()
            }

            guard let code = extractAuthCode(from: callbackURL) else {
                errorMessage = "No authorization code in callback."
                isAuthenticating = false
                return false
            }

            return await completeOAuth(withCode: code, modelContext: modelContext)
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            isAuthenticating = false
            return false
        } catch {
            errorMessage = error.localizedDescription
            isAuthenticating = false
            return false
        }
    }

    // MARK: - Extract Code

    func extractAuthCode(from url: URL) -> String? {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        return components?.queryItems?.first(where: { $0.name == "code" })?.value
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
        isAuthenticating = true
        errorMessage = nil

        do {
            let tokenResponse = try await exchangeCodeForToken(code: code)
            try storeSession(tokenResponse: tokenResponse, modelContext: modelContext)
            isAuthenticating = false
            return true
        } catch {
            print("[OAuth] completeOAuth error: \(error)")
            errorMessage = error.localizedDescription
            isAuthenticating = false
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

        print("[OAuth] POST \(url) with code: \(code.prefix(10))...")
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.tokenExchangeFailed
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "no body"
            print("[OAuth] Token exchange failed: HTTP \(httpResponse.statusCode) — \(body)")
            throw AuthError.tokenExchangeFailed
        }

        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    // MARK: - Store Session

    @MainActor
    func storeSession(tokenResponse: TokenResponse, modelContext: ModelContext) throws {
        try KeychainHelper.saveNotionToken(tokenResponse.accessToken)

        print("[OAuth] Saving session for workspace: \(tokenResponse.workspaceName)")

        let container = try ModelContainer.shared()
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let existing = try context.fetch(FetchDescriptor<UserSession>())
        for session in existing {
            context.delete(session)
        }

        let session = UserSession(
            workspaceId: tokenResponse.workspaceId,
            workspaceName: tokenResponse.workspaceName
        )
        context.insert(session)
        try context.save()
        print("[OAuth] Session saved successfully")
    }

    // MARK: - Errors

    enum AuthError: LocalizedError {
        case noCallback
        case invalidTokenEndpoint
        case tokenExchangeFailed

        var errorDescription: String? {
            switch self {
            case .noCallback: return "No response from Notion."
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
