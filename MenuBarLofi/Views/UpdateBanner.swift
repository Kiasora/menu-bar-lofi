import SwiftUI

/// A compact new-version notice with a download link and a per-version dismissal.
struct UpdateBanner: View {
    let updates: UpdateChecker
    let update: UpdateChecker.Update

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.title3)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Version \(update.version) is out")
                    .font(.caption.weight(.semibold))
                if let message = update.message, !message.isEmpty {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Get it") { NSWorkspace.shared.open(updates.link) }
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Capsule().fill(.primary.opacity(0.09)))
            Button { withAnimation(.snappy) { updates.dismiss() } } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Hide until the next version")
            .accessibilityLabel("Hide update")
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.primary.opacity(0.05)))
    }
}
