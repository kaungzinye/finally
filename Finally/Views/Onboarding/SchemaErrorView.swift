import SwiftUI

struct SchemaErrorView: View {
    let issues: [ValidationResult.Issue]
    var onRetry: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Group {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Your database needs a few changes", systemImage: "exclamationmark.triangle.fill")
                                .font(.headline)
                                .foregroundStyle(Palette.ink)
                            Text("Make these changes in Notion, then check again.")
                                .font(.subheadline)
                                .foregroundStyle(Palette.muted)
                        }
                        .padding(.vertical, 4)
                    }

                    Section {
                        ForEach(issues, id: \.propertyName) { issue in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(Palette.urgent)
                                    Text(issue.propertyName)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(Palette.ink)
                                    Text(issue.expectedType)
                                        .font(.meta)
                                        .foregroundStyle(Palette.muted)
                                }
                                Text(issue.message)
                                    .font(.callout)
                                    .foregroundStyle(Palette.muted)
                            }
                            .padding(.vertical, 2)
                        }
                    } header: {
                        SectionLabel("Changes to make")
                    }
                }
                .cardRow()

                Section {
                    Button("Check again", action: onRetry)
                        .buttonStyle(.ink)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }
            }
            .paperList()
            .navigationTitle("Set up your database")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
