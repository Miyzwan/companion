//
//  ControlPanelView.swift
//  companion
//
//  M4 Task 4 — compact control panel (PRD 46): input task (PRD 47) +
//  project context (PRD 48).
//  M4 Task 5 — kontrol approval Allow/Deny (PRD 50/51/52).
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
    /// User memutuskan approval (PRD 50). Pengiriman & exactly-once diurus
    /// controller + ApprovalGate, bukan view.
    var onApproval: ((ApprovalChoice) -> Void)?

    private let titleLabel = ControlPanelView.makeLabel("New Hermes Task", size: 13, weight: .semibold)
    private let promptCaption = ControlPanelView.makeLabel("What should Hermes do?", size: 11, secondary: true)
    private let promptField = NSTextField()
    private let projectCaption = ControlPanelView.makeLabel("Project", size: 11, secondary: true)
    private let projectLabel = ControlPanelView.makeLabel("", size: 12)
    private let chooseButton = NSButton()
    private let statusLabel = ControlPanelView.makeLabel("", size: 12)
    private let actionCaption = ControlPanelView.makeLabel("Action", size: 11, secondary: true)
    private let actionScroll = NSScrollView()
    private let actionText = NSTextView()
    private let reasonCaption = ControlPanelView.makeLabel("Context / reason", size: 11, secondary: true)
    private let reasonLabel = ControlPanelView.makeWrappingLabel(size: 12, maxLines: reasonMaxLines)
    private let permanentCheckbox = NSButton()
    private let denyButton = NSButton()
    private let allowButton = NSButton()
    private let answerCaption = ControlPanelView.makeLabel("Answer", size: 11, secondary: true)
    private let answerScroll = NSScrollView()
    private let answerText = NSTextView()
    private let startButton = NSButton()

    private var state: TaskState = .idle
    private(set) var projectPath = ""
    /// Jawaban akhir agent (PRD 22). Kosong → seksi Answer disembunyikan.
    private var answer = ""
    private var pendingApproval: ApprovalRequest?
    private var approvalAnswered = false

    // Layout — dilay out dari ATAS (view ini flipped) memakai konstanta bernama.
    private let pad: CGFloat = 14
    private let captionHeight: CGFloat = 14
    private let captionGap: CGFloat = 4
    private let sectionGap: CGFloat = 12
    private let fieldHeight: CGFloat = 24
    private let buttonHeight: CGFloat = 26
    private let chooseWidth: CGFloat = 92
    private let startWidth: CGFloat = 84
    private let decisionWidth: CGFloat = 84
    private let checkboxHeight: CGFloat = 18
    private let answerHeight: CGFloat = 92
    /// Perintah yang diminta izin harus terbaca utuh, tapi panel tidak boleh
    /// tumbuh tanpa batas — sisanya tersedia lewat tooltip.
    private static let actionMaxLines = 4
    private static let reasonMaxLines = 3

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
        // Allow SENGAJA tidak diberi key equivalent: menyetujui perintah tidak
        // boleh terjadi karena refleks menekan Enter (PRD 50).
        startButton.keyEquivalent = "\r"

        permanentCheckbox.setButtonType(.switch)
        permanentCheckbox.title = "Allow permanently"
        permanentCheckbox.font = .systemFont(ofSize: 11)
        permanentCheckbox.target = self
        permanentCheckbox.action = #selector(permanentToggled)

        denyButton.title = "Deny"
        denyButton.bezelStyle = .rounded
        denyButton.target = self
        denyButton.action = #selector(denyTapped)

        allowButton.title = "Allow"
        allowButton.bezelStyle = .rounded
        allowButton.target = self
        allowButton.action = #selector(allowTapped)

        // Area jawaban: read-only tapi tetap bisa diseleksi agar isinya
        // bisa disalin. Bukan mini-terminal (PRD 45) — hanya hasil akhir.
        Self.configureReadOnlyText(answerText, in: answerScroll, font: .systemFont(ofSize: 12))
        answerScroll.drawsBackground = true
        answerScroll.backgroundColor = NSColor(calibratedWhite: 0.93, alpha: 1)
        answerScroll.borderType = .lineBorder

        // Perintah yang dimintakan izin: kotaknya dibatasi tinggi tapi BISA
        // di-scroll. Label biasa akan memotong perintah panjang tanpa tanda →
        // user menyetujui teks yang ekornya tidak pernah dia lihat (PRD 50).
        Self.configureReadOnlyText(actionText, in: actionScroll,
                                   font: .monospacedSystemFont(ofSize: 12, weight: .regular))
        actionScroll.drawsBackground = false
        actionScroll.borderType = .noBorder
        actionScroll.autohidesScrollers = true

        [titleLabel, promptCaption, promptField, projectCaption,
         projectLabel, chooseButton, statusLabel,
         actionCaption, actionScroll, reasonCaption, reasonLabel,
         permanentCheckbox, denyButton, allowButton,
         answerCaption, answerScroll, startButton].forEach(addSubview)
        setFrameSize(NSSize(width: Self.contentWidth, height: requiredHeight))
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) tidak dipakai") }

    // MARK: - API untuk controller panel

    func update(state: TaskState) {
        self.state = state
        refresh()
        needsLayout = true
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

    /// Pasang approval yang menunggu keputusan (nil = tidak ada). `answered`
    /// membuat tombol non-interaktif tanpa menyembunyikan isinya (PRD 51/52).
    /// Ukuran panel berubah → pemanggil harus menata ulang panel.
    func update(approval: ApprovalRequest?, answered: Bool) {
        pendingApproval = approval
        approvalAnswered = answered
        if approval == nil { permanentCheckbox.state = .off }
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

    private var model: ControlPanelModel {
        ControlPanelModel(state: state, prompt: promptField.stringValue, projectPath: projectPath,
                          pendingApproval: pendingApproval, approvalAnswered: approvalAnswered)
    }

    private var requiredHeight: CGFloat { layoutPass(apply: false) }

    override func layout() {
        super.layout()
        layoutPass(apply: true)
    }

    /// SATU sumber posisi: dipakai `layout()` (apply) dan pengukuran tinggi
    /// panel (measure). Dulu keduanya dihitung terpisah — gampang melenceng
    /// begitu ada seksi baru.
    @discardableResult
    private func layoutPass(apply: Bool) -> CGFloat {
        let width = bounds.width > 0 ? bounds.width : Self.contentWidth
        let w = width - 2 * pad
        var y = pad
        func place(_ view: NSView, _ rect: NSRect) { if apply { view.frame = rect } }
        func show(_ views: [NSView], _ visible: Bool) { if apply { views.forEach { $0.isHidden = !visible } } }

        place(titleLabel, NSRect(x: pad, y: y, width: w, height: 17))
        y += 17 + 10

        place(promptCaption, NSRect(x: pad, y: y, width: w, height: captionHeight))
        y += captionHeight + captionGap
        place(promptField, NSRect(x: pad, y: y, width: w, height: fieldHeight))
        y += fieldHeight + sectionGap

        place(projectCaption, NSRect(x: pad, y: y, width: w, height: captionHeight))
        y += captionHeight + captionGap
        place(projectLabel, NSRect(x: pad, y: y + 2, width: w - chooseWidth - 8, height: 18))
        place(chooseButton, NSRect(x: width - pad - chooseWidth, y: y, width: chooseWidth, height: 22))
        y += 22 + sectionGap

        place(statusLabel, NSRect(x: pad, y: y, width: w, height: 16))
        y += 16 + 10

        // ── Approval (PRD 50) ──
        let m = model
        let approvalViews: [NSView] = [actionCaption, actionScroll, reasonCaption, reasonLabel,
                                       denyButton, allowButton]
        show(approvalViews, m.showsApproval)
        show([permanentCheckbox], m.allowsPermanent)
        if m.showsApproval {
            // + inset atas/bawah text view; sisanya di-scroll, tidak dipotong.
            let actionH = Self.textHeight(m.approvalAction ?? "", font: actionText.font, width: w - 12,
                                          maxLines: Self.actionMaxLines) + 12
            place(actionCaption, NSRect(x: pad, y: y, width: w, height: captionHeight))
            y += captionHeight + captionGap
            place(actionScroll, NSRect(x: pad, y: y, width: w, height: actionH))
            y += actionH + 10

            let reasonText = m.approvalReason ?? ""
            if !reasonText.isEmpty {
                let reasonH = Self.textHeight(reasonText, font: reasonLabel.font, width: w,
                                              maxLines: Self.reasonMaxLines)
                place(reasonCaption, NSRect(x: pad, y: y, width: w, height: captionHeight))
                y += captionHeight + captionGap
                place(reasonLabel, NSRect(x: pad, y: y, width: w, height: reasonH))
                y += reasonH + 10
            } else {
                show([reasonCaption, reasonLabel], false)
            }

            if m.allowsPermanent {
                place(permanentCheckbox, NSRect(x: pad, y: y, width: w, height: checkboxHeight))
                y += checkboxHeight + 8
            }
            place(denyButton, NSRect(x: pad, y: y, width: decisionWidth, height: buttonHeight))
            place(allowButton, NSRect(x: width - pad - decisionWidth, y: y, width: decisionWidth, height: buttonHeight))
            y += buttonHeight + sectionGap
        }

        // ── Jawaban akhir (PRD 22) ──
        show([answerCaption, answerScroll], !answer.isEmpty)
        if !answer.isEmpty {
            place(answerCaption, NSRect(x: pad, y: y, width: w, height: captionHeight))
            y += captionHeight + captionGap
            place(answerScroll, NSRect(x: pad, y: y, width: w, height: answerHeight))
            y += answerHeight + sectionGap
        }

        place(startButton, NSRect(x: width - pad - startWidth, y: y, width: startWidth, height: buttonHeight))
        return y + buttonHeight + pad
    }

    // MARK: - Render model

    private func refresh() {
        let m = model
        let folderOK = Self.directoryExists(projectPath)

        startButton.isEnabled = m.canStart(directoryExists: Self.directoryExists)
        promptField.isEnabled = !m.isBusy
        chooseButton.isEnabled = !m.isBusy

        projectLabel.stringValue = projectPath.isEmpty
            ? "Belum dipilih"
            : (projectPath as NSString).abbreviatingWithTildeInPath
        projectLabel.textColor = folderOK ? Self.primaryText : .systemRed
        statusLabel.stringValue = "\(state.glyph) \(state.statusLine)"

        // Isi approval tetap terbaca setelah dijawab; hanya tombolnya yang mati.
        let action = m.approvalAction ?? ""
        if actionText.string != action { actionText.string = action }
        reasonLabel.stringValue = m.approvalReason ?? ""
        reasonLabel.toolTip = m.approvalReason
        denyButton.isEnabled = m.approvalEnabled
        allowButton.isEnabled = m.approvalEnabled
        permanentCheckbox.isEnabled = m.approvalEnabled
    }

    func controlTextDidChange(_ obj: Notification) {
        refresh()
    }

    // MARK: - Aksi

    @objc private func startTapped() {
        guard model.canStart(directoryExists: Self.directoryExists) else { return }
        onStart?(promptField.stringValue, projectPath)
        promptField.stringValue = ""
        refresh()
    }

    @objc private func chooseTapped() {
        onChooseProject?()
    }

    @objc private func permanentToggled() { refresh() }

    @objc private func allowTapped() { decide(ControlPanelModel.allowChoice(permanent: permanentCheckbox.state == .on)) }

    @objc private func denyTapped() { decide(.deny) }

    /// Kunci tombol SEKARANG juga (sebelum controller sempat menjawab) supaya
    /// klik kedua tidak pernah jadi respons kedua — PRD 51. Penjaga sebenarnya
    /// tetap ApprovalGate di paket.
    private func decide(_ choice: ApprovalChoice) {
        guard model.approvalEnabled else { return }
        approvalAnswered = true
        refresh()
        onApproval?(choice)
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

    /// Tinggi teks yang di-wrap pada lebar tertentu, dibatasi `maxLines`
    /// (teknik yang sama dengan BubbleView.requiredSize).
    private static func textHeight(_ text: String, font: NSFont?, width: CGFloat, maxLines: Int) -> CGFloat {
        let font = font ?? .systemFont(ofSize: 12)
        let lineH = ceil(font.boundingRectForFont.height)
        guard !text.isEmpty else { return lineH }
        let rect = (text as NSString).boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font])
        return min(max(ceil(rect.height), lineH), lineH * CGFloat(maxLines))
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

    /// Label multi-baris yang bisa diseleksi. Dipakai untuk teks yang boleh
    /// dipotong (alasan); teks yang WAJIB terbaca utuh memakai text view
    /// ber-scroll, bukan ini.
    private static func makeWrappingLabel(size: CGFloat, maxLines: Int) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: "")
        label.font = .systemFont(ofSize: size)
        label.textColor = primaryText
        label.maximumNumberOfLines = maxLines
        // URUTAN PENTING: setter `lineBreakMode` di NSTextField ikut mematikan
        // wrapping, jadi harus dihidupkan lagi SETELAHNYA — kalau tidak, teks
        // panjang berhenti di baris pertama padahal tingginya sudah dialokasikan
        // beberapa baris.
        label.lineBreakMode = .byTruncatingTail
        label.usesSingleLineMode = false
        label.cell?.wraps = true
        label.cell?.isScrollable = false
        return label
    }

    /// Text view read-only yang bisa diseleksi (bisa disalin) di dalam scroll
    /// view — dipakai Answer dan Action.
    private static func configureReadOnlyText(_ text: NSTextView, in scroll: NSScrollView, font: NSFont) {
        text.isEditable = false
        text.isSelectable = true
        text.drawsBackground = false
        text.font = font
        text.textColor = primaryText
        text.textContainerInset = NSSize(width: 6, height: 6)
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        scroll.documentView = text
        scroll.hasVerticalScroller = true
    }
}
