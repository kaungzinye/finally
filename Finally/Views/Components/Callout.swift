import SwiftUI

/// A status message on a tinted card. The icon carries the tone and the message stays in ink.
struct Callout: View {
    var icon = "exclamationmark.triangle.fill"
    let message: String
    var onRetry: (() -> Void)?
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(Palette.high)

            Text(message)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 8)

            if let onRetry {
                Button("Retry", action: onRetry)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Palette.ink)
            }

            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.muted)
                }
                .accessibilityLabel("Dismiss")
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Palette.high.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Palette.high.opacity(0.35), lineWidth: 1)
        )
    }
}
