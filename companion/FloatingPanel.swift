//
//  FloatingPanel.swift
//  companion
//
//  Created by Dimas Dwi Ismaunnizam on 12/08/26.
//
//  M2 — macOS Window Spike (PRD section 42/79).
//  NSPanel borderless-transparan yang membuktikan:
//  transparent window · always-on-top · drag · click character · interactive bubble
//  · transparent area tidak memblokir app bawah · tanpa mencuri fokus
//  · Space switching · full-screen · multi-monitor · position restoration
//  · display disconnect recovery.
//  Karakter/bubble placeholder AppKit (PRD 41) — final mascot & SwiftUI state UI = M3.

import AppKit
import CompanionCore

/// Kontainer transparan: klik di area kosong TIDAK ditangkap (diteruskan ke app
/// di bawah), klik di subview interaktif (karakter) diterima.
final class PassThroughContainer: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }
}

/// Bubble status: display-only, selalu pass-through (PRD: bubble tidak boleh
/// jadi mini-terminal; interaksi spike = muncul/hilang lewat klik karakter).
final class BubbleView: NSView {
    var text = "● Idle — Ready when you are." {
        didSet { needsDisplay = true }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 4), xRadius: 12, yRadius: 12)
        NSColor(calibratedWhite: 0.98, alpha: 0.96).setFill()
        path.fill()
        NSColor(calibratedWhite: 0.75, alpha: 1).setStroke()
        path.lineWidth = 1
        path.stroke()
        let s = text as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor(calibratedWhite: 0.15, alpha: 1),
        ]
        let size = s.size(withAttributes: attrs)
        s.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2),
               withAttributes: attrs)
    }
}

/// Karakter placeholder (PRD 41: ◉ ● ⚠ ✓ ! ○) — satu-satunya area interaktif:
/// drag untuk memindah panel, klik untuk toggle bubble, klik-kanan untuk menu.
final class CharacterView: NSView {
    var onToggleBubble: (() -> Void)?
    var onDragEnd: (() -> Void)?

    private var dragStart: NSPoint = .zero
    private var didDrag = false

    override var acceptsFirstResponder: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let circle = NSBezierPath(ovalIn: bounds.insetBy(dx: 4, dy: 4))
        NSColor(calibratedWhite: 0.12, alpha: 1).setFill()
        circle.fill()
        NSColor(calibratedWhite: 0.85, alpha: 1).setStroke()
        circle.lineWidth = 2
        circle.stroke()
        let glyph = "◉" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 24, weight: .medium),
            .foregroundColor: NSColor(calibratedWhite: 0.85, alpha: 1),
        ]
        let size = glyph.size(withAttributes: attrs)
        glyph.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2),
                   withAttributes: attrs)
    }

    override func mouseDown(with event: NSEvent) {
        dragStart = event.locationInWindow
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        let p = event.locationInWindow
        let delta = NSSize(width: p.x - dragStart.x, height: p.y - dragStart.y)
        if abs(delta.width) > 2 || abs(delta.height) > 2 { didDrag = true }
        guard let w = window else { return }
        w.setFrameOrigin(FloatingPosition.moved(origin: w.frame.origin, by: delta))
    }

    override func mouseUp(with event: NSEvent) {
        if didDrag { onDragEnd?() } else { onToggleBubble?() }
        didDrag = false
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        menu.addItem(withTitle: "Toggle Bubble", action: #selector(toggleBubbleAction), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Companion", action: #selector(quitAction), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func toggleBubbleAction() { onToggleBubble?() }
    @objc private func quitAction() { NSApp.terminate(nil) }
}

/// Pengatur panel melayang: konfigurasi NSPanel + posisi + recovery layar.
final class FloatingPanelController: NSObject {
    private static let originKey = "companion.floating.origin"

    private let collapsedSize = NSSize(width: 120, height: 88)
    private let expandedSize = NSSize(width: 120, height: 160)

    private var panel: NSPanel!
    private var characterView: CharacterView!
    private var bubbleView: BubbleView!
    private var bubbleVisible = false

    func show() {
        // Accessory: tanpa Dock icon, app tidak pernah "aktif" → tidak mencuri fokus.
        NSApp.setActivationPolicy(.accessory)

        let panel = NSPanel(
            contentRect: NSRect(origin: restoredOrigin(), size: collapsedSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = false   // drag hanya via karakter
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.contentView = buildContentView()
        self.panel = panel
        panel.orderFrontRegardless()

        observeScreenChanges()
        NotificationCenter.default.addObserver(self, selector: #selector(persistOrigin),
                                               name: NSApplication.willTerminateNotification, object: nil)
    }

    private func buildContentView() -> NSView {
        let container = PassThroughContainer(frame: NSRect(origin: .zero, size: collapsedSize))
        characterView = CharacterView(frame: NSRect(x: 28, y: 12, width: 64, height: 64))
        characterView.onToggleBubble = { [weak self] in self?.toggleBubble() }
        characterView.onDragEnd = { [weak self] in self?.dragEnded() }
        bubbleView = BubbleView(frame: NSRect(x: 10, y: 88, width: 100, height: 60))
        bubbleView.isHidden = true
        container.addSubview(characterView)
        container.addSubview(bubbleView)
        return container
    }

    // ── Bubble ──────────────────────────────────────────────────────

    private func toggleBubble() {
        bubbleVisible.toggle()
        let newSize = bubbleVisible ? expandedSize : collapsedSize
        // Bottom-left anchor tetap → bubble muncul di ATAS karakter.
        panel.setFrame(NSRect(origin: panel.frame.origin, size: newSize), display: true)
        bubbleView.isHidden = !bubbleVisible
        clampPanelIntoVisibleFrame()
    }

    // ── Drag ────────────────────────────────────────────────────────

    private func dragEnded() {
        clampPanelIntoVisibleFrame()
        persistOrigin()
    }

    private func clampPanelIntoVisibleFrame() {
        guard let panel else { return }
        let frames = NSScreen.screens.map(\.visibleFrame)
        guard let nearest = FloatingPosition.nearestVisibleFrame(to: panel.frame.origin, frames: frames) else { return }
        let clamped = FloatingPosition.clamped(origin: panel.frame.origin, size: panel.frame.size, visibleFrame: nearest)
        if clamped != panel.frame.origin {
            panel.setFrameOrigin(clamped)
        }
    }

    // ── Posisi (PRD 40: position remembered; PRD 42: restoration) ───

    @objc private func persistOrigin() {
        guard let panel else { return }
        let d = UserDefaults.standard
        d.set(Double(panel.frame.origin.x), forKey: Self.originKey + ".x")
        d.set(Double(panel.frame.origin.y), forKey: Self.originKey + ".y")
    }

    private func restoredOrigin() -> CGPoint {
        let d = UserDefaults.standard
        guard d.object(forKey: Self.originKey + ".x") != nil else { return defaultOrigin() }
        let point = CGPoint(x: d.double(forKey: Self.originKey + ".x"),
                            y: d.double(forKey: Self.originKey + ".y"))
        let frames = NSScreen.screens.map(\.visibleFrame)
        guard let nearest = FloatingPosition.nearestVisibleFrame(to: point, frames: frames) else {
            return defaultOrigin()
        }
        return FloatingPosition.clamped(origin: point, size: collapsedSize, visibleFrame: nearest)
    }

    /// Default: kanan-bawah layar utama, sedikit dari tepi.
    private func defaultOrigin() -> CGPoint {
        let frame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return CGPoint(x: frame.maxX - collapsedSize.width - 24, y: frame.minY + 80)
    }

    // ── Multi-monitor + display disconnect recovery (PRD 42) ─────────

    private func observeScreenChanges() {
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.clampPanelIntoVisibleFrame()
        }
    }
}
