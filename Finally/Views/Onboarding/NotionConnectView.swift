import SwiftUI
import SwiftData

struct NotionConnectView: View {
    var onConnected: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @State private var authService = NotionAuthService()

    private var buttonBackground: Color {
        colorScheme == .dark ? Color(.systemGray5) : Color.black
    }

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.primary)

            Text("Finally")
                .font(.largeTitle.bold())

            Text("Connect your Notion workspace to get started")
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

            Button {
                Task {
                    let success = await authService.startOAuthFlow(modelContext: modelContext)
                    if success {
                        onConnected()
                    }
                }
            } label: {
                HStack {
                    if authService.isAuthenticating {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(authService.isAuthenticating ? "Connecting..." : "Connect to Notion")
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(buttonBackground)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(authService.isAuthenticating)
            .padding(.horizontal, 40)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground).ignoresSafeArea())
        .onAppear {
            print("[NotionConnectView] appeared, colorScheme=\(colorScheme)")
        }
        .background(
            GeometryReader { geo in
                Color.clear.onAppear {
                    print("[NotionConnectView] frame size: \(geo.size)")
                }
            }
        )
    }
}
