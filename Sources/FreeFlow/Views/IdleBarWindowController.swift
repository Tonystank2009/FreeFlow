//
//  IdleBarWindowController.swift
//  FreeFlow
//
//  Hosts the idle bar in a non-activating panel pinned to the bottom of the
//  active screen.
//

import AppKit
import SwiftUI

/// A borderless panel returns false from canBecomeKey by default, and a window
/// that cannot become key never delivers hover or click events to its content.
/// That is what made the first version of this bar inert.
private final class IdleBarPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class IdleBarWindowController {
    static let shared = IdleBarWindowController()

    private var panel: NSPanel?
    private var hiddenUntil: Date?
    private var reshowTimer: Timer?
    private var screenObserver: NSObjectProtocol?

    private let bottomMargin: CGFloat = 14

    private init() {}

    // MARK: - Visibility

    func start() {
        guard SettingsStore.shared.idleBarEnabled else { return }
        self.ensurePanel()
        self.reposition()
        self.panel?.orderFrontRegardless()
        self.observeScreenChanges()
    }

    func stop() {
        self.panel?.orderOut(nil)
        self.reshowTimer?.invalidate()
        self.reshowTimer = nil
    }

    /// Hidden during a dictation: the recording overlay occupies the same
    /// space, and two bars stacked there helps nobody.
    func setSuppressed(_ suppressed: Bool) {
        IdleBarState.shared.isSuppressed = suppressed
        self.refreshVisibility()
    }

    /// Gets it out of the way without making the user find a setting to undo.
    /// An hour is long enough to finish whatever it was covering and short
    /// enough that nobody has to remember they hid it.
    func hideForAnHour() {
        self.hiddenUntil = Date().addingTimeInterval(3600)
        self.panel?.orderOut(nil)

        self.reshowTimer?.invalidate()
        self.reshowTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.hiddenUntil = nil
                self?.refreshVisibility()
            }
        }
        DebugLogger.shared.info("Idle bar hidden for one hour", source: "IdleBar")
    }

    /// Called when the bar's content changes size, so it stays centred.
    func layoutChanged() {
        DispatchQueue.main.async { [weak self] in
            self?.reposition()
        }
    }

    func refreshVisibility() {
        guard SettingsStore.shared.idleBarEnabled else {
            self.panel?.orderOut(nil)
            return
        }
        if let hiddenUntil, Date() < hiddenUntil {
            self.panel?.orderOut(nil)
            return
        }
        if IdleBarState.shared.isSuppressed {
            self.panel?.orderOut(nil)
            return
        }
        self.ensurePanel()
        self.reposition()
        self.panel?.orderFrontRegardless()
    }

    // MARK: - Panel

    private func ensurePanel() {
        guard self.panel == nil else { return }

        let panel = IdleBarPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        // Follows the user across spaces and sits above full-screen apps
        // without pulling focus away from whatever they're typing into.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.isMovableByWindowBackground = false
        // Without this, onHover never fires: tracking areas only receive
        // mouse-moved events if the window asks for them.
        panel.acceptsMouseMovedEvents = true
        panel.ignoresMouseEvents = false

        let hosting = NSHostingView(rootView: IdleBarView())
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = .clear
        panel.contentView = hosting

        self.panel = panel
    }

    private func reposition() {
        guard let panel, let hosting = panel.contentView else { return }

        // Measure after layout. fittingSize before a layout pass returns a
        // stale value, which then centres the bar against the wrong width.
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        panel.setContentSize(size)

        // Anchor to the screen the pointer is on, not NSScreen.main, which is
        // whichever screen holds the key window.
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return }

        // visibleFrame excludes the Dock, which parks the bar well above the
        // bottom edge. Sit just above the Dock when there is one, and near the
        // screen edge when there is not.
        let full = screen.frame
        let visible = screen.visibleFrame
        let dockHeight = max(0, visible.minY - full.minY)
        let y = full.minY + (dockHeight > 0 ? dockHeight + 6 : self.bottomMargin)

        panel.setFrameOrigin(NSPoint(
            x: full.midX - size.width / 2,
            y: y
        ))
    }

    private func observeScreenChanges() {
        guard self.screenObserver == nil else { return }
        self.screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reposition() }
        }
    }
}
