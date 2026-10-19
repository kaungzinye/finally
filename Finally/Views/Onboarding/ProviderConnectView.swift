import SwiftUI
import SwiftData

struct ProviderConnectView: View {
    var onConnected: () -> Void
    @Query private var sessions: [UserSession]
    @Environment(\.modelContext) private var modelContext
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    VStack(alignment: .leading, spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(Palette.ink)
                            .accessibilityHidden(true)
                        Text("Finally")
                            .font(.pageTitle)
                            .foregroundStyle(Palette.ink)
                        Text("Make room for what matters.")
                            .font(.system(.title2, design: .rounded, weight: .medium))
                            .foregroundStyle(Palette.ink)
                        Text("Choose where your tasks live.")
                            .foregroundStyle(Palette.muted)
                    }

                    if let errorMessage { Callout(message: errorMessage) }
                    if !sessions.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            SectionLabel("Your workspaces")
                            ForEach(sessions, id: \.id) { workspace in
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
                                        detail: ProviderSessionRoute.resolve(selectedWorkspace: workspace) == .databaseSetup
                                            ? "Finish choosing your tasks database."
                                            : "Open this workspace.",
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
                                detail: "Connect Notion and choose your tasks database.",
                                symbol: "building.2"
                            )
                        }
                        .accessibilityIdentifier("connect-notion-provider")

                        NavigationLink {
                            FinallyServerConnectView(onConnected: onConnected)
                        } label: {
                            providerLabel(
                                "Finally Server",
                                detail: "Sign in to your server and choose a workspace.",
                                symbol: "server.rack"
                            )
                        }
                        .accessibilityIdentifier("connect-server-provider")
                    }
                    .buttonStyle(.plain)

                    SectionNote("Your tasks stay where they live. Notion tasks stay in Notion, and server tasks stay on your server.")
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
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.muted)
                .accessibilityHidden(true)
        }
        .foregroundStyle(Palette.ink)
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
