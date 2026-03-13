import Foundation
import AuthenticationServices
import SwiftData

@Observable
final class NotionAuthService: NSObject {
    var isAuthenticating = false
    var errorMessage: String?

    private var presentationAnchor: ASPresentationAnchor?

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

    @MainActor
    func startOAuthFlow(anchor: ASPresentationAnchor, modelContext: ModelContext) async -> Bool {
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
                self.presentationAnchor = anchor
                session.presentationContextProvider = self
                session.prefersEphemeralWebBrowserSession = false
                session.start()
            }

            guard let code = extractAuthCode(from: callbackURL) else {
                errorMessage = "Could not extract authorization code."
                isAuthenticating = false
                return false
            }

            let tokenResponse = try await exchangeCodeForToken(code: code)
            try storeSession(tokenResponse: tokenResponse, modelContext: modelContext)

            isAuthenticating = false
            return true
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

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.tokenExchangeFailed
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw AuthError.tokenExchangeFailed
        }

        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    // MARK: - Store Session

    func storeSession(tokenResponse: TokenResponse, modelContext: ModelContext) throws {
        try KeychainHelper.saveNotionToken(tokenResponse.accessToken)

        let existing = try modelContext.fetch(FetchDescriptor<UserSession>())
        for session in existing {
            modelContext.delete(session)
        }

        let session = UserSession(
            workspaceId: tokenResponse.workspaceId,
            workspaceName: tokenResponse.workspaceName
        )
        modelContext.insert(session)
        try modelContext.save()
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
        presentationAnchor ?? ASPresentationAnchor()
    }
}
