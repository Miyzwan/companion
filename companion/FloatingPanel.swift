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
/// Mendukung multi-baris (state + aktivitas/keputusan, M3); panel menskalakan
/// ukuran mengikuti teks terlebar (background tidak pernah lebih sempit).
final class BubbleView: NSView {
    private let font = NSFont.systemFont(ofSize: 12)
    var text = "◉ Ready when you are." {
        didSet { needsDisplay = true }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// Ukuran bubble yang pas untuk `text` (baris terlebar + padding).
    func requiredSize(for text: String) -> NSSize {
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let lines = text.components(separatedBy: "\n")
        let lineH = ((lines.first ?? "") as NSString).size(withAttributes: attrs).height
        let maxW = lines.map { ($0 as NSString).size(withAttributes: attrs).width }.max() ?? 0
        return NSSize(width: maxW + 28, height: CGFloat(lines.count) * lineH + 24)
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 4), xRadius: 12, yRadius: 12)
        NSColor(calibratedWhite: 0.98, alpha: 0.96).setFill()
        path.fill()
        NSColor(calibratedWhite: 0.75, alpha: 1).setStroke()
        path.lineWidth = 1
        path.stroke()
        let lines = text.components(separatedBy: "\n")
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(calibratedWhite: 0.15, alpha: 1),
        ]
        let lineH = ((lines.first ?? "") as NSString).size(withAttributes: attrs).height
        for (i, line) in lines.enumerated() {
            let s = line as NSString
            let size = s.size(withAttributes: attrs)
            let y = bounds.midY + (CGFloat(lines.count - 1) / 2 - CGFloat(i)) * lineH - size.height / 2
            s.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: y), withAttributes: attrs)
        }
    }
}

/// Renderer karakter (PRD 41): PlaceholderAsset ↔ FinalMascotAsset tanpa
/// mengubah integration. `.asset` = gambar 2D milik user dari asset catalog.
enum CharacterRenderer {
    case placeholder          // lingkaran + glyph (default, tanpa asset)
    case asset(NSImage)       // gambar user (PNG transparan)
}

/// Karakter placeholder (PRD 41: ◉ ● ⚠ ✓ ! ○) — satu-satunya area interaktif:
/// drag untuk memindah panel, klik untuk toggle bubble, klik-kanan untuk menu.
final class CharacterView: NSView {
    var onToggleBubble: (() -> Void)?
    var onDragEnd: (() -> Void)?

    var renderer: CharacterRenderer = .placeholder {
        didSet { needsDisplay = true }
    }

    private var dragStart: NSPoint = .zero
    private var didDrag = false

    override var acceptsFirstResponder: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        switch renderer {
        case .placeholder:
            drawPlaceholder()
        case .asset(let image):
            // Aspect-fit, centered — area interaktif (frame) tetap sama.
            let fit = aspectFit(size: image.size, in: bounds)
            image.draw(in: fit)
        }
    }

    private func drawPlaceholder() {
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

    /// Rectangle aspect-fit untuk gambar di dalam `container` (centered).
    private func aspectFit(size: NSSize, in container: NSRect) -> NSRect {
        guard size.width > 0, size.height > 0 else { return container }
        let scale = min(container.width / size.width, container.height / size.height)
        let w = size.width * scale
        let h = size.height * scale
        return NSRect(x: container.midX - w / 2, y: container.midY - h / 2, width: w, height: h)
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

    // Layout panel — konstanta bernama biar konsisten. Ubah `characterSize`
    // saja → panel, margin, dan bubble menyesuaikan otomatis.
    private var panelWidth: CGFloat { characterSize + 2 * edge }
    private let characterSize: CGFloat = 120
    private let edge: CGFloat = 8        // margin bawah & atas
    private let gap: CGFloat = 8         // jarak karakter → bubble
    private var collapsedSize: NSSize {
        NSSize(width: panelWidth, height: edge + characterSize + edge)
    }

    private var panel: NSPanel!
    private var characterView: CharacterView!
    private var bubbleView: BubbleView!
    private var bubbleVisible = false
    private var bubbleAutoShown = false

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
        // PRD 41: kalau asset "Character" ada di asset catalog → gambar user;
        // kalau tidak ada → placeholder (fallback aman, tidak crash).
        if let img = NSImage(named: "Character") {
            characterView.renderer = .asset(img)
        }
        self.panel = panel
        panel.orderFrontRegardless()

        observeScreenChanges()
        NotificationCenter.default.addObserver(self, selector: #selector(persistOrigin),
                                               name: NSApplication.willTerminateNotification, object: nil)
    }

    private func buildContentView() -> NSView {
        let container = PassThroughContainer(frame: NSRect(origin: .zero, size: collapsedSize))
        characterView = CharacterView(frame: NSRect(x: (panelWidth - characterSize) / 2, y: edge,
                                                    width: characterSize, height: characterSize))
        characterView.onToggleBubble = { [weak self] in self?.toggleBubble() }
        characterView.onDragEnd = { [weak self] in self?.dragEnded() }
        bubbleView = BubbleView(frame: NSRect(x: 10, y: 88, width: 100, height: 60))
        bubbleView.isHidden = true
        container.addSubview(characterView)
        container.addSubview(bubbleView)
        return container
    }

    // ── Bubble ──────────────────────────────────────────────────────

    private func toggleBubble() { setBubbleVisible(!bubbleVisible) }

    private func setBubbleVisible(_ visible: Bool) {
        bubbleVisible = visible
        if visible {
            bubbleView.isHidden = false
            resizePanelForBubble()
        } else {
            bubbleView.isHidden = true
            panel.setFrame(NSRect(origin: panel.frame.origin, size: collapsedSize), display: true)
        }
        clampPanelIntoVisibleFrame()
    }

    /// Ukur ulang panel agar bubble (teks terbaru) muat — bottom-left anchor tetap,
    /// bubble mengembang ke ATAS di atas karakter.
    private func resizePanelForBubble() {
        let need = bubbleView.requiredSize(for: bubbleView.text)
        let panelW = max(panelWidth, need.width + 2 * edge)
        bubbleView.frame = NSRect(x: (panelW - need.width) / 2, y: edge + characterSize + gap,
                                  width: need.width, height: need.height)
        let panelH = edge + characterSize + gap + need.height + edge
        panel.setFrame(NSRect(origin: panel.frame.origin,
                              size: NSSize(width: panelW, height: panelH)), display: true)
    }

    // ── Bind ke TaskController (M3) ─────────────────────────────────

    func bind(_ controller: TaskController) {
        controller.onBubbleChange = { [weak self] text in
            Task { @MainActor in self?.setBubbleText(text) }
        }
    }

    /// Update teks bubble dari state Hermes. Auto-buka bubble SEKALI saat
    /// state meninggalkan idle (spike M3) — setelah itu user yang kontrol.
    private func setBubbleText(_ text: String) {
        let idleDefault = "◉ Ready when you are."
        if bubbleView.isHidden && text != idleDefault && !bubbleAutoShown {
            bubbleAutoShown = true
            setBubbleVisible(true)
        }
        bubbleView.text = text
        if bubbleVisible { resizePanelForBubble() }
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
