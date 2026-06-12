import SwiftUI

/// One saved PC in the Connection Center grid.
struct DeviceCardView: View {
    var device: DeviceProfile
    var isSelected: Bool
    var onSelect: () -> Void
    var onConnect: () -> Void
    var onEdit: () -> Void
    var onDuplicate: () -> Void
    var onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            thumbnail
            details
        }
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    isSelected ? Color.accentColor : Color.primary.opacity(0.08),
                    lineWidth: isSelected ? 2 : 1
                )
        }
        .shadow(
            color: .black.opacity(isHovering ? 0.22 : 0.1),
            radius: isHovering ? 14 : 5,
            y: isHovering ? 8 : 2
        )
        .scaleEffect(isHovering ? 1.02 : 1)
        .animation(AppTheme.cardSpring, value: isHovering)
        .animation(AppTheme.cardSpring, value: isSelected)
        .onHover { hovering in
            isHovering = hovering
        }
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .gesture(
            TapGesture(count: 2).onEnded {
                onConnect()
            }.exclusively(before: TapGesture().onEnded {
                onSelect()
            })
        )
        .contextMenu {
            Button {
                onConnect()
            } label: {
                Label("Connect", systemImage: "play.fill")
            }

            Button {
                onEdit()
            } label: {
                Label("Edit…", systemImage: "pencil")
            }

            Button {
                onDuplicate()
            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }

            Divider()

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete…", systemImage: "trash")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: device.displayName))
        .accessibilityHint(Text("Double-tap to connect."))
    }

    private var thumbnail: some View {
        ZStack {
            AppTheme.deviceGradient(hue: device.accentHue)

            // A faint oversized glyph gives the tile some depth.
            Image(systemName: "display")
                .font(.system(size: 92, weight: .ultraLight))
                .foregroundStyle(.white.opacity(0.14))
                .offset(x: 28, y: 16)

            Text(verbatim: AppTheme.monogram(for: device.displayName))
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))
                .shadow(color: .black.opacity(0.25), radius: 4, y: 2)

            connectBadge
        }
        .frame(height: 124)
        .clipShape(UnevenRoundedRectangle(
            topLeadingRadius: 14,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: 14,
            style: .continuous
        ))
    }

    private var connectBadge: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button {
                    onConnect()
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(.black.opacity(0.45), in: Circle())
                        .overlay {
                            Circle()
                                .strokeBorder(.white.opacity(0.35), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .help("Connect")
                .padding(10)
                .opacity(isHovering ? 1 : 0)
                .scaleEffect(isHovering ? 1 : 0.7)
                .animation(AppTheme.cardSpring, value: isHovering)
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: device.displayName)
                .font(.headline)
                .lineLimit(1)

            Text(verbatim: device.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if let lastConnectedAt = device.lastConnectedAt {
                Text(verbatim: "Last used \(Self.relativeFormatter.localizedString(for: lastConnectedAt, relativeTo: Date()))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
}
