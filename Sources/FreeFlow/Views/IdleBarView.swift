//
//  IdleBarView.swift
//  FreeFlow
//
//  A small persistent bar at the bottom of the screen: somewhere to start a
//  dictation without remembering the hotkey, and somewhere to get rid of it.
//

import AppKit
import Combine
import SwiftUI

/// Shared state for the idle bar. Callbacks are wired by ContentView, matching
/// how NotchContentState hands actions back to the app.
@MainActor
final class IdleBarState: ObservableObject {
    static let shared = IdleBarState()

    @Published var isHovering = false
    /// Set while a dictation is running — the recording overlay takes over and
    /// two bars stacked on top of each other helps nobody.
    @Published var isSuppressed = false

    var onStartDictationRequested: (() -> Void)?
    var onOpenPreferencesRequested: (() -> Void)?

    private init() {}
}

struct IdleBarView: View {
    @ObservedObject private var state = IdleBarState.shared
    @ObservedObject private var settings = SettingsStore.shared

    private var accent: Color { self.settings.accentColor }

    var body: some View {
        HStack(spacing: 10) {
            // Resting state is deliberately almost nothing: a waveform hint.
            // Anything more is clutter sitting over the user's work all day.
            Image(systemName: "waveform")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(self.state.isHovering ? self.accent : Color.white.opacity(0.75))

            if !self.state.isHovering {
                // Resting state still has to say what it is. A bare icon reads
                // as a rendering artefact rather than a control.
                Text("FreeFlow")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .fixedSize()
            }

            if self.state.isHovering {
                Text("Double-click to dictate")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.75))
                    .fixedSize()

                Divider()
                    .frame(height: 12)
                    .overlay(Color.white.opacity(0.18))

                Button {
                    IdleBarWindowController.shared.hideForAnHour()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "moon.zzz")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Hide 1h")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(Color.white.opacity(0.75))
                }
                .buttonStyle(.plain)
                .help("Hide the bar for one hour")

                Button {
                    self.state.onOpenPreferencesRequested?()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                .help("Settings")
            }
        }
        .padding(.horizontal, self.state.isHovering ? 14 : 12)
        .padding(.vertical, 7)
        .background(
            Capsule(style: .continuous)
                .fill(Color(red: 0.11, green: 0.11, blue: 0.12).opacity(0.92))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.24),
                                    Color.white.opacity(0.06),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.75
                        )
                )
                .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
        )
        .opacity(self.state.isHovering ? 1.0 : 0.80)
        .animation(.easeOut(duration: 0.16), value: self.state.isHovering)
        .onHover { hovering in
            self.state.isHovering = hovering
            // The bar changes width between states, so it has to be re-centred
            // or it appears to slide sideways on hover.
            IdleBarWindowController.shared.layoutChanged()
        }
        .onTapGesture(count: 2) {
            self.state.onStartDictationRequested?()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("FreeFlow. Double-click to dictate.")
    }
}
