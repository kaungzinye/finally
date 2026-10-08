import SwiftUI
import SwiftData

struct NotionConnectView: View {
    var onConnected: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(NotionAuthService.self) private var authService

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.primary)

            Text("Connect Notion")
                .font(.largeTitle.bold())

            Text("Authorize your Notion workspace, then choose the database that holds your tasks.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            if let errorMessage = authService.errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            connectButton
            .disabled(authService.isAuthenticating)
            .accessibilityIdentifier("notion-authorize")
            .padding(.horizontal, 40)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground).ignoresSafeArea())
        .navigationTitle("Notion")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var connectButton: some View {
        if #available(iOS 26, *) {
            Button(action: connect) { connectLabel }
                .buttonStyle(.glassProminent)
        } else {
            Button(action: connect) { connectLabel }
                .buttonStyle(.borderedProminent)
        }
    }

    private var connectLabel: some View {
        HStack {
            if authService.isAuthenticating { ProgressView() }
            Text(authService.isAuthenticating ? "Connecting…" : "Connect to Notion")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func connect() {
        Task {
            if await authService.startOAuthFlow(modelContext: modelContext) {
                onConnected()
            }
        }
    }
}
