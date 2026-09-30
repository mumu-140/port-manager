import SwiftUI

struct TunnelStatusBadge: View {
    let tunnel: CloudflareTunnelState
    let onCopyURL: () -> Void
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            // Main content area
            HStack(spacing: 8) {
                // Status indicator
                StatusDot(color: tunnel.status.color)

                if tunnel.status == .active, let url = tunnel.tunnelURL {
                    Text(url.shortenedTunnelURL)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                } else if tunnel.status == .starting || tunnel.status == .stopping {
                    ProgressView()
                        .controlSize(.small)
                    Text(L(tunnel.status == .starting ? "tunnel.startingTunnel" : "tunnel.stopping"))
                        .font(.body)
                        .foregroundStyle(.secondary)
                } else if tunnel.status == .error {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(tunnel.lastError ?? L("tunnel.statusError"))
                        .font(.body)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Action buttons
            if tunnel.status == .active {
                Button {
                    onCopyURL()
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help(L("tunnel.copyTunnelURLHelp"))
            }

            Button {
                onStop()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(tunnel.status == .active ? .red : .secondary)
            }
            .buttonStyle(.borderless)
            .help(L(tunnel.status == .error ? "tunnel.dismiss" : "tunnel.stopTunnelShort"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: Radius.sm)
                .fill(Theme.Colors.surfaceCard)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Radius.sm)
                .strokeBorder(Theme.Colors.border, lineWidth: 0.5)
        }
    }
}
