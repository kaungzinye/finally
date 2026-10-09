import SwiftUI
import SwiftData

struct ProviderConnectView: View {
    var onConnected: () -> Void
    @Query private var sessions: [UserSession]
    @Environment(\.modelContext) private var modelContext
    @State private var errorMessage: String?

    private var savedWorkspaces: [UserSession] {
        sessions.filter { ProviderSessionRoute.resolve(selectedWorkspace: $0) == .tasks }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    VStack(alignment: .leading, spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 64))
                            .accessibilityHidden(true)
                        Text("Finally")
                            .font(.pageTitle)
                        Text("Make room for what matters.")
                            .font(.title2.weight(.medium))
                        Text("Choose where your tasks live.")
                            .foregroundStyle(.secondary)
                    }

                    if let errorMessage { Callout(message: errorMessage) }
                    if !savedWorkspaces.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Connected provider workspaces").font(.eyebrow)
                            ForEach(savedWorkspaces, id: \.id) { workspace in
                                Button {
                                    do {
                                        sessions.forEach { $0.isSelected = $0.id == workspace.id }
                                        try modelContext.save()
                                        onConnected()
                                    } catch {
                                        errorMessage = error.localizedDescription
                                    }
                                } label: {
                                    providerLabel(
                                        workspace.workspaceName,
                                        detail: "Open this provider workspace.",
                                        symbol: workspace.providerIdentity == .finallyServer ? "server.rack" : "building.2"
                                    )
                                }
                                .accessibilityIdentifier("open-saved-provider-workspace")
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    VStack(spacing: 16) {
                        NavigationLink {
                            NotionConnectView(onConnected: onConnected)
                        } label: {
                            providerLabel(
                                "Notion",
                                detail: "Connect your workspace and choose a task database.",
                                symbol: "building.2"
                            )
                        }
                        .accessibilityIdentifier("connect-notion-provider")

                        NavigationLink {
                            FinallyServerConnectView(onConnected: onConnected)
                        } label: {
                            providerLabel(
                                "Finally Server",
                                detail: "Sign in to your server and choose a provider workspace.",
                                symbol: "server.rack"
                            )
                        }
                        .accessibilityIdentifier("connect-server-provider")
                    }
                    .buttonStyle(.plain)

                    Text("Each task provider owns its tasks. Finally keeps your provider workspaces separate.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(24)
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(Palette.paper.ignoresSafeArea())
            .navigationTitle("Welcome")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func providerLabel(_ title: String, detail: String, symbol: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.title2)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.chip)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .foregroundStyle(.primary)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Palette.hairline)
        }
        .contentShape(Rectangle())
    }
}
