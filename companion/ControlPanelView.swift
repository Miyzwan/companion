//
//  ControlPanelView.swift
//  companion
//
//  M4 Task 4 — compact control panel (PRD 46): input task (PRD 47) +
//  project context (PRD 48).
//  View ini HANYA merender `ControlPanelModel` dari paket; aturan
//  enable/disable tidak boleh hidup di sini (paket yang punya test).
//  AppKit murni — NSHostingView akan membuat seluruh rect hit-testable dan
//  merusak click-through hasil spike M2.
//

import AppKit
import CompanionCore

final class ControlPanelView: NSView, NSTextFieldDelegate {
    /// Lebar konten panel (PRD 43: cukup untuk state, bukan chatbot window).
    static let contentWidth: CGFloat = 300

    /// User menekan Start — (prompt, projectPath).
    var onStart: ((String, String) -> Void)?
    /// User menekan Choose… — app yang memunculkan NSOpenPanel.
    var onChooseProject: (() -> Void)?

    private let titleLabel = ControlPanelView.makeLabel("New Hermes Task", size: 13, weight: .semibold)
    private let promptCaption = ControlPanelView.makeLabel("What should Hermes do?", size: 11, secondary: true)
    private let promptField = NSTextField()
    private let projectCaption = ControlPanelView.makeLabel("Project", size: 11, secondary: true)
    private let projectLabel = ControlPanelView.makeLabel("", size: 12)
    private let chooseButton = NSButton()
    private let statusLabel = ControlPanelView.makeLabel("", size: 12)
    private let answerCaption = ControlPanelView.makeLabel("Answer", size: 11, secondary: true)
    private let answerScroll = NSScrollView()
    private let answerText = NSTextView()
    private let startButton = NSButton()

    private var state: TaskState = .idle
    private(set) var projectPath = ""
    /// Jawaban akhir agent (PRD 22). Kosong → seksi Answer disembunyikan.
    private var answer = ""

    // Layout — dilay out dari ATAS (view ini flipped) memakai konstanta bernama.
    private let pad: CGFloat = 14
    private let fieldHeight: CGFloat = 24
    private let buttonHeight: CGFloat = 26
    private let chooseWidth: CGFloat = 92
    private let startWidth: CGFloat = 84
    private let answerHeight: CGFloat = 92

    override var isFlipped: Bool { true }

    // MARK: - Init

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.contentWidth, height: 0))
        // Latar panel digambar terang (senada BubbleView M2/M3). Di Dark Mode,
        // NSButton/placeholder akan memakai warna sistem GELAP (teks putih) →
        // putih di atas putih alias tidak kelihatan. Kunci appearance ke light
        // supaya kontrol sistem ikut skema latar ini.
        appearance = NSAppearance(named: .aqua)
        promptField.placeholderString = "Contoh: rapikan README"
        promptField.font = .systemFont(ofSize: 12)
        promptField.bezelStyle = .roundedBezel
        promptField.delegate = self

        chooseButton.title = "Choose…"
        chooseButton.bezelStyle = .rounded
        chooseButton.font = .systemFont(ofSize: 12)
        chooseButton.target = self
        chooseButton.action = #selector(chooseTapped)

        startButton.title = "Start"
        startButton.bezelStyle = .rounded
        startButton.target = self
        startButton.action = #selector(startTapped)
        // Enter di dalam field memicu tombol default → satu jalur start saja.
        startButton.keyEquivalent = "\r"

        // Area jawaban: read-only tapi tetap bisa diseleksi agar isinya
        // bisa disalin. Bukan mini-terminal (PRD 45) — hanya hasil akhir.
        answerText.isEditable = false
        answerText.isSelectable = true
        answerText.drawsBackground = false
        answerText.font = .systemFont(ofSize: 12)
        answerText.textColor = Self.primaryText
        answerText.textContainerInset = NSSize(width: 6, height: 6)
        answerText.isVerticallyResizable = true
        answerText.isHorizontallyResizable = false
        answerText.autoresizingMask = [.width]
        answerText.textContainer?.widthTracksTextView = true
        answerScroll.documentView = answerText
        answerScroll.hasVerticalScroller = true
        answerScroll.drawsBackground = true
        answerScroll.backgroundColor = NSColor(calibratedWhite: 0.93, alpha: 1)
        answerScroll.borderType = .lineBorder

        [titleLabel, promptCaption, promptField, projectCaption,
         projectLabel, chooseButton, statusLabel,
         answerCaption, answerScroll, startButton].forEach(addSubview)
        setFrameSize(NSSize(width: Self.contentWidth, height: requiredHeight))
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) tidak dipakai") }

    // MARK: - API untuk controller panel

    func update(state: TaskState) {
        self.state = state
        refresh()
    }

    func update(projectPath: String) {
        self.projectPath = projectPath
        refresh()
    }

    /// Pasang jawaban akhir agent; string kosong menyembunyikan seksi Answer.
    /// Ukuran panel ikut berubah → pemanggil harus menata ulang panel.
    func update(answer: String) {
        self.answer = answer
        answerText.string = answer
        refresh()
        needsLayout = true
    }

    /// Ukuran yang dibutuhkan panel untuk memuat kontrol ini.
    var requiredSize: NSSize { NSSize(width: Self.contentWidth, height: requiredHeight) }

    /// Taruh fokus keyboard di field prompt (dipanggil saat panel dibuka).
    func focusPrompt() {
        window?.makeFirstResponder(promptField)
    }

    // MARK: - Layout

    private var requiredHeight: CGFloat {
        let base = pad + 17 + 10 + 14 + 4 + fieldHeight + 12 + 14 + 4 + 22 + 12 + 16 + 10 + buttonHeight + pad
        return base + (answer.isEmpty ? 0 : 14 + 4 + answerHeight + 12)
    }

    override func layout() {
        super.layout()
        let w = bounds.width - 2 * pad
        var y = pad

        titleLabel.frame = NSRect(x: pad, y: y, width: w, height: 17)
        y += 17 + 10

        promptCaption.frame = NSRect(x: pad, y: y, width: w, height: 14)
        y += 14 + 4
        promptField.frame = NSRect(x: pad, y: y, width: w, height: fieldHeight)
        y += fieldHeight + 12

        projectCaption.frame = NSRect(x: pad, y: y, width: w, height: 14)
        y += 14 + 4
        projectLabel.frame = NSRect(x: pad, y: y + 2, width: w - chooseWidth - 8, height: 18)
        chooseButton.frame = NSRect(x: bounds.width - pad - chooseWidth, y: y, width: chooseWidth, height: 22)
        y += 22 + 12

        statusLabel.frame = NSRect(x: pad, y: y, width: w, height: 16)
        y += 16 + 10

        if answer.isEmpty {
            answerCaption.isHidden = true
            answerScroll.isHidden = true
        } else {
            answerCaption.isHidden = false
            answerScroll.isHidden = false
            answerCaption.frame = NSRect(x: pad, y: y, width: w, height: 14)
            y += 14 + 4
            answerScroll.frame = NSRect(x: pad, y: y, width: w, height: answerHeight)
            y += answerHeight + 12
        }

        startButton.frame = NSRect(x: bounds.width - pad - startWidth, y: y, width: startWidth, height: buttonHeight)
    }

    // MARK: - Render model

    private func refresh() {
        let model = ControlPanelModel(state: state, prompt: promptField.stringValue, projectPath: projectPath)
        let folderOK = Self.directoryExists(projectPath)

        startButton.isEnabled = model.canStart(directoryExists: Self.directoryExists)
        promptField.isEnabled = !model.isBusy
        chooseButton.isEnabled = !model.isBusy

        projectLabel.stringValue = projectPath.isEmpty
            ? "Belum dipilih"
            : (projectPath as NSString).abbreviatingWithTildeInPath
        projectLabel.textColor = folderOK ? Self.primaryText : .systemRed
        statusLabel.stringValue = "\(state.glyph) \(state.statusLine)"
    }

    func controlTextDidChange(_ obj: Notification) {
        refresh()
    }

    // MARK: - Aksi

    @objc private func startTapped() {
        let model = ControlPanelModel(state: state, prompt: promptField.stringValue, projectPath: projectPath)
        guard model.canStart(directoryExists: Self.directoryExists) else { return }
        onStart?(promptField.stringValue, projectPath)
        promptField.stringValue = ""
        refresh()
    }

    @objc private func chooseTapped() {
        onChooseProject?()
    }

    // MARK: - Menggambar latar (senada BubbleView)

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 12, yRadius: 12)
        NSColor(calibratedWhite: 0.98, alpha: 0.98).setFill()
        path.fill()
        NSColor(calibratedWhite: 0.75, alpha: 1).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    // MARK: - Helper

    private static let primaryText = NSColor(calibratedWhite: 0.15, alpha: 1)
    private static let secondaryText = NSColor(calibratedWhite: 0.45, alpha: 1)

    /// Folder benar-benar ada DAN memang direktori (PRD 48).
    static func directoryExists(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        let found = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        return found && isDirectory.boolValue
    }

    private static func makeLabel(_ text: String, size: CGFloat,
                                  weight: NSFont.Weight = .regular,
                                  secondary: Bool = false) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = secondary ? secondaryText : primaryText
        label.lineBreakMode = .byTruncatingMiddle
        return label
    }
}
