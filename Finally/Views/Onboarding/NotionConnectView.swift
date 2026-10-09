import SwiftUI
import SwiftData

struct NotionConnectView: View {
    var onConnected: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(NotionAuthService.self) private var authService

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("F")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(Palette.onInk)
                .frame(width: 56, height: 56)
                .background(Palette.ink, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                .rotationEffect(.degrees(-4))
                .padding(.top, 48)

            Text("Finally")
                .font(.pageTitle)
                .foregroundStyle(Palette.ink)
                .padding(.top, 28)

            Text("Connect any Notion workspace where you're a member. Your tasks stay in Notion.")
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Palette.muted)
                .padding(.top, 10)

            if let errorMessage = authService.errorMessage {
                Callout(message: errorMessage)
                    .padding(.top, 20)
            }

            Spacer()

            Button {
                Task {
                    let success = await authService.startOAuthFlow(modelContext: modelContext)
                    if success {
                        onConnected()
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    if authService.isAuthenticating {
                        ProgressView()
                            .tint(Palette.onInk)
                    }
                    Text(authService.isAuthenticating ? "Connecting..." : "Connect to Notion")
                }
            }
            .buttonStyle(.ink)
            .disabled(authService.isAuthenticating)
            .accessibilityIdentifier("notion-authorize")

            Text("You'll sign in on notion.so")
                .font(.meta)
                .foregroundStyle(Palette.muted)
                .frame(maxWidth: .infinity)
                .padding(.top, 14)
                .padding(.bottom, 12)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.paper.ignoresSafeArea())
    }
}
