import Foundation
import CoreGraphics

// T2.1 — FloatingPosition: geometri murni panel melayang, tanpa AppKit
// (biar bisa di-unit-test di CompanionCore). Caller (app target) yang
// menerjemahkan ke NSScreen/NSWindow.
// PRD 40: position remembered, multi-monitor safe; PRD 42: position
// restoration, display disconnect recovery; release blocker: "character
// can become permanently off-screen".

public enum FloatingPosition {
    /// Clamp origin panel (koordinat AppKit, bottom-left) supaya panel
    /// berukuran `size` tetap SEPENUHNYA di dalam `visibleFrame`.
    /// Panel lebih besar dari layar → pinned ke minX/minY (tidak pernah off-screen).
    public static func clamped(origin: CGPoint, size: CGSize, visibleFrame: CGRect) -> CGPoint {
        var x = origin.x
        var y = origin.y
        if size.width > visibleFrame.width {
            x = visibleFrame.minX
        } else {
            x = min(max(x, visibleFrame.minX), visibleFrame.maxX - size.width)
        }
        if size.height > visibleFrame.height {
            y = visibleFrame.minY
        } else {
            y = min(max(y, visibleFrame.minY), visibleFrame.maxY - size.height)
        }
        return CGPoint(x: x, y: y)
    }

    /// Geser origin (drag).
    public static func moved(origin: CGPoint, by delta: CGSize) -> CGPoint {
        CGPoint(x: origin.x + delta.width, y: origin.y + delta.height)
    }

    /// Pilih visible frame terdekat dari titik panel. Prioritas: frame yang
    /// MENGANDUNG titik; kalau tidak ada (mis. monitor dicabut), frame dengan
    /// jarak Euclidean terkecil dari titik.
    public static func nearestVisibleFrame(to point: CGPoint, frames: [CGRect]) -> CGRect? {
        guard !frames.isEmpty else { return nil }
        if let containing = frames.first(where: { $0.contains(point) }) {
            return containing
        }
        return frames.min { a, b in
            distanceSquared(from: point, to: a) < distanceSquared(from: point, to: b)
        }
    }

    private static func distanceSquared(from point: CGPoint, to frame: CGRect) -> CGFloat {
        let dx = max(frame.minX - point.x, 0, point.x - frame.maxX)
        let dy = max(frame.minY - point.y, 0, point.y - frame.maxY)
        return dx * dx + dy * dy
    }
}
