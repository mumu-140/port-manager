/**
 * FavoriteWatchButtons.swift
 * PortKiller
 *
 * Reusable favorite and watch toggle buttons for ports.
 * Supports icon-only and labeled button styles.
 */

import SwiftUI

/// Style for favorite/watch buttons
enum FavoriteWatchButtonStyle {
    /// Icon-only button with plain style (for rows)
    case iconOnly
    /// Labeled button with bordered style (for detail views)
    case labeled
}

/// Favorite toggle button for a port
struct FavoriteButton: View {
    let portNumber: Int
    let style: FavoriteWatchButtonStyle

    @Environment(AppState.self) private var appState

    init(portNumber: Int, style: FavoriteWatchButtonStyle = .iconOnly) {
        self.portNumber = portNumber
        self.style = style
    }

    private var isFavorite: Bool {
        appState.isFavorite(portNumber)
    }

    var body: some View {
        switch style {
        case .iconOnly:
            Button {
                appState.toggleFavorite(portNumber)
            } label: {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .foregroundStyle(isFavorite ? .yellow : .secondary)
            }
            .buttonStyle(.plain)
            .help(L("ports.toggleFavoriteHelp"))

        case .labeled:
            Button {
                appState.toggleFavorite(portNumber)
            } label: {
                Text(isFavorite ? L("ports.removeFavorite") : L("ports.addFavorite"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }
}

/// Watch toggle button for a port
struct WatchButton: View {
    let portNumber: Int
    let style: FavoriteWatchButtonStyle

    @Environment(AppState.self) private var appState

    init(portNumber: Int, style: FavoriteWatchButtonStyle = .iconOnly) {
        self.portNumber = portNumber
        self.style = style
    }

    private var isWatching: Bool {
        appState.isWatching(portNumber)
    }

    var body: some View {
        switch style {
        case .iconOnly:
            Button {
                appState.toggleWatch(portNumber)
            } label: {
                Image(systemName: isWatching ? "eye.fill" : "eye")
                    .foregroundStyle(isWatching ? .blue : .secondary)
            }
            .buttonStyle(.plain)
            .help(L("ports.toggleWatchHelp"))

        case .labeled:
            Button {
                appState.toggleWatch(portNumber)
            } label: {
                Text(isWatching ? L("ports.stopWatching") : L("ports.watch"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }
}

/// Combined favorite and watch buttons in a horizontal stack
struct FavoriteWatchButtons: View {
    let portNumber: Int
    let style: FavoriteWatchButtonStyle
    let spacing: CGFloat

    @Environment(AppState.self) private var appState

    init(
        portNumber: Int,
        style: FavoriteWatchButtonStyle = .iconOnly,
        spacing: CGFloat = 8
    ) {
        self.portNumber = portNumber
        self.style = style
        self.spacing = spacing
    }

    var body: some View {
        HStack(spacing: spacing) {
            FavoriteButton(portNumber: portNumber, style: style)
            WatchButton(portNumber: portNumber, style: style)
        }
    }
}
