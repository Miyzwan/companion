# Milestone 2 — macOS Window Spike: HASIL

> **Tanggal:** 2026-08-12 · **Status:** ✅ LULUS — Window Spike selesai (look + behavior diverifikasi user)
> **Lingkungan:** macOS (Apple Silicon) · Xcode 16 · Swift 6 · Hermes Agent v0.18.0 (dipakai M1)
> **Lokasi kode:** `~/Documents/GitHub/companion/` (app target `companion/` + package `CompanionCore`)
> **Dokumen acuan:** PRD section 42 (Floating Window Engineering Spike) + section 79 (Engineering Milestone 2) + section 40 (Floating Character)

---

## 1. Acceptance (PRD section 79 / 42) — semua TERBUKTI

| Item | Bukti | Cara verifikasi |
|------|-------|-----------------|
| transparent window | `NSPanel` borderless, `isOpaque=false`, `backgroundColor=.clear`, `hasShadow=false` | visual: panel tanpa border/background |
| always-on-top | `panel.level = .floating` | visual: tetap di atas app normal |
| draggable | `CharacterView.mouseDragged` → `FloatingPosition.moved` + clamp | visual: drag karakter, panel ikut, nempel di tepi |
| click character | `mouseUp` tanpa drag = toggle bubble | visual |
| interactive bubble | bubble muncul/hilang; background selebar teks (dynamic `requiredSize`) | visual |
| transparent area tidak blokir app bawah | `PassThroughContainer.hitTest` → nil di area kosong; `BubbleView.hitTest` → nil; hanya `CharacterView` interaktif | visual: klik area transparan → tembus ke TextEdit/Finder |
| tidak mencuri fokus | `.nonactivatingPanel`, `canBecomeKey` default false, `becomesKeyOnlyIfNeeded`, activation policy `.accessory` | visual: TextEdit tetap aktif saat klik karakter |
| Space switching | `collectionBehavior = [.canJoinAllSpaces]` | visual: karakter tampil di semua Space |
| full-screen behavior | `collectionBehavior = [.fullScreenAuxiliary]` → tampil di ATAS app full-screen | visual + didokumentasikan (section 4) |
| multi-monitor | `FloatingPosition.nearestVisibleFrame` + clamp per screen | unit test (9 test) |
| position restoration | UserDefaults `companion.floating.origin.x/.y`; restore + clamp saat launch | visual: quit → relaunch → posisi sama |
| display disconnect recovery | observer `NSApplication.didChangeScreenParametersNotification` → re-clamp ke frame terdekat | unit test (nearestVisibleFrame) + kode |

Suite: **70/70 test** (`./verify.sh` — paket build+test + app build, semua hijau).

---

## 2. Komponen baru

| Komponen | File | Catatan |
|----------|------|---------|
| Panel melayang + controller | `companion/FloatingPanel.swift` | NSPanel config, drag, bubble, persist, screen observer |
| Pass-through container | `PassThroughContainer` (sama file) | hitTest nil di area transparan (click-through) |
| Karakter + renderer (PRD 41) | `CharacterView` + `CharacterRenderer` | `.placeholder` ↔ `.asset(NSImage)` — ganti gambar tanpa sentuh logic |
| Bubble status | `BubbleView` | display-only, selebar teks (`requiredSize`) |
| Geometri murni (testable) | `CompanionCore/Domain/FloatingPosition.swift` | clamp + nearestVisibleFrame + moved — 9 unit test |
| Asset karakter | `companion/Assets.xcassets/Character.imageset/` | idle.png 283×262 (500×500 asli di `idle.png` repo root, di-trim + rotasi) |
| App entry | `companionApp.swift` | `NSApplicationDelegateAdaptor`, no WindowGroup; accessory policy |

---

## 3. Temuan teknis (spike — dipakai M3/M4)

1. **Click-through yang benar = hitTest, bukan `ignoresMouseEvents`.** `ignoresMouseEvents=true` membuat window tidak menerima event apa pun termasuk tracking area → tidak bisa deteksi hover. `PassThroughContainer.hitTest` → nil untuk area kosong membuat AppKit meneruskan klik ke window di bawah, sementara `CharacterView` tetap interaktif. Ini pola yang dipakai app floating panel umum.
2. **`.accessory` activation policy** (tanpa Dock icon) + `.nonactivatingPanel` = fokus tidak pernah mencuri di level app. Konsekuensi: Cmd+Q tidak jalan (app tak pernah aktif) → Quit via klik-kanan karakter (menu). 
3. **Dynamic bubble sizing**: background bubble dihitung dari `NSString.size(withAttributes:)` + padding, panel melebar mengikuti teks — background tidak pernah lebih sempit dari tulisan.
4. **Ukuran = satu konstanta**: `characterSize` (120) → `panelWidth`/`collapsedSize`/posisi bubble semua turunan. Ganti satu angka, layout menyesuaikan.
5. **Asset PNG harus di-trim**: idle.png asli 500×500 tapi konten hanya 230×251 (46–50% kanvas, sisanya transparan) → karakter terlihat kecil. Di-trim ke content-bbox + padding 16px (via PIL) + rotasi 90° CCW (sumber asli ternyata miring). `CharacterRenderer` fallback ke placeholder kalau asset tidak ada — tidak crash.
6. **xcodebuild app target**: `-target` TIDAK resolve paket SPM ("Unable to resolve module dependency: CompanionCore") → WAJIB `-scheme companion`. Sudah dibakukan di `verify.sh`.
7. **Aksesibilitas**: klik kanan karakter = menu (Toggle Bubble / Quit). Akses keyboard penuh = M4.

---

## 4. Full-screen behavior (dokumentasi wajib PRD 79)

- Dengan `.fullScreenAuxiliary` di `collectionBehavior`, panel floating tampil DI ATAS app yang sedang full-screen (Safari, dll.) — diverifikasi user.
- Panel tetap bisa di-drag saat di atas full-screen app; bubble juga berfungsi normal.
- Konsekuensi desain: karena selalu tampil di atas full-screen, M4 perlu pertimbangan "jangan ganggu saat user menonton video/game" (mis. state ambient yang redup) — dicatat sebagai input desain M3/M4.

---

## 5. Yang sengaja ditunda (ke M3/M4)

- SwiftUI state UI (Working/NeedsYou/Success render dari `TaskStateMachine`) → M3 (Floating Companion).
- Per-state asset (idle/working/needsYou/success) → renderer sudah siap (`CharacterRenderer`), tinggal map state→asset → M3.
- Animasi karakter (subtle, sesuai preferensi user) → M3/M4.
- Keyboard aksesibilitas penuh + VoiceOver → M4 (Mac Product Loop).
- App Sandbox tetap OFF; distribusi Developer ID → keputusan release (PRD 0.1).

---

## 6. Command cheat sheet (M2)

```bash
./verify.sh                                              # paket build+test + app build (kanonik)
xcodebuild -project Companion.xcodeproj -scheme companion build   # app saja (wajib -scheme, bukan -target)
open ~/Library/Developer/Xcode/DerivedData/companion-*/Build/Products/Debug/companion.app
# ganti gambar karakter: replace companion/Assets.xcassets/Character.imageset/idle.png → build
# ganti ukuran: ubah `characterSize` di FloatingPanel.swift → build
```

---

*Dokumen ini adalah bukti Milestone 2. Lanjut ke Milestone 3 (Floating Companion — gabung state Hermes + floating UI, PRD section 80) setelah commit + review.*
