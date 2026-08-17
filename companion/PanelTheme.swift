//
//  PanelTheme.swift
//  companion
//
//  M4 Task 9 — warna permukaan melayang (bubble PRD 45 + control panel PRD 46).
//  Sebelumnya panel mengunci `NSAppearance(named: .aqua)` karena latarnya
//  digambar terang: di Dark Mode, NSButton/placeholder memakai warna sistem
//  GELAP (teks putih) → putih di atas putih alias kontrol tidak terlihat.
//  Kuncinya dibuka dengan memberi SETIAP warna latar kita padanan gelapnya,
//  jadi kontrol sistem boleh mengikuti appearance asli user.
//
//  Warna dibuat lewat `NSColor(name:dynamicProvider:)`, bukan warna sistem apa
//  adanya, supaya nilai terang yang sudah disetujui di M2/M3 tidak berubah dan
//  alpha (panel melayang harus sedikit tembus) tetap terkendali.
//

import AppKit

enum PanelTheme {
    /// Latar control panel.
    static let background = dynamic(light: NSColor(calibratedWhite: 0.98, alpha: 0.98),
                                    dark: NSColor(calibratedWhite: 0.16, alpha: 0.98),
                                    name: "companion.panel.background")

    /// Latar bubble — sedikit lebih tembus daripada panel (M2/M3).
    static let bubbleBackground = dynamic(light: NSColor(calibratedWhite: 0.98, alpha: 0.96),
                                          dark: NSColor(calibratedWhite: 0.16, alpha: 0.96),
                                          name: "companion.bubble.background")

    /// Garis tepi kedua permukaan.
    static let border = dynamic(light: NSColor(calibratedWhite: 0.75, alpha: 1),
                                dark: NSColor(calibratedWhite: 0.42, alpha: 1),
                                name: "companion.panel.border")

    /// Kotak jawaban akhir (PRD 22) — sedikit berbeda dari latar panel.
    static let answerBackground = dynamic(light: NSColor(calibratedWhite: 0.93, alpha: 1),
                                          dark: NSColor(calibratedWhite: 0.22, alpha: 1),
                                          name: "companion.panel.answer")

    /// Teks memakai warna sistem: sudah adaptif dan ikut setelan aksesibilitas.
    static let primaryText = NSColor.labelColor
    static let secondaryText = NSColor.secondaryLabelColor

    private static func dynamic(light: NSColor, dark: NSColor, name: String) -> NSColor {
        NSColor(name: NSColor.Name(name)) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }
}
