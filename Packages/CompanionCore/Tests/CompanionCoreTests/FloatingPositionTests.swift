import Testing
import Foundation
import CoreGraphics
@testable import CompanionCore

// T2.1 — FloatingPosition: geometri murni panel melayang (PRD 40: position
// remembered, multi-monitor safe; PRD 42: position restoration, display
// disconnect recovery). Test dulu (RED), implement menyusul.

@Test func clampKeepsPositionInside() {
    let frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    let origin = CGPoint(x: 400, y: 500)
    let clamped = FloatingPosition.clamped(origin: origin, size: CGSize(width: 96, height: 96), visibleFrame: frame)
    #expect(clamped == origin)
}

@Test func clampPullsBackFromRightEdge() {
    let frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    let origin = CGPoint(x: 1900, y: 500)   // panel 96px → overflow 76px
    let clamped = FloatingPosition.clamped(origin: origin, size: CGSize(width: 96, height: 96), visibleFrame: frame)
    // Makro #expect mengevaluasi tiap sisi terpisah → homogenkan tipe dulu
    // (CGFloat == Int-expression bisa false walau nilainya sama).
    let expectedX = CGFloat(1920 - 96)
    #expect(clamped.x == expectedX)
    #expect(clamped.y == 500)
}

@Test func clampPullsBackFromTopEdge() {
    // Koordinat AppKit bottom-left: y naik ke atas.
    let frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    let origin = CGPoint(x: 400, y: 1050)
    let clamped = FloatingPosition.clamped(origin: origin, size: CGSize(width: 96, height: 96), visibleFrame: frame)
    let expectedY = CGFloat(1080 - 96)
    #expect(clamped.y == expectedY)
}

@Test func clampPullsBackFromLeftAndBottomEdges() {
    let frame = CGRect(x: 100, y: 100, width: 1920, height: 1080)
    let origin = CGPoint(x: 50, y: 50)
    let clamped = FloatingPosition.clamped(origin: origin, size: CGSize(width: 96, height: 96), visibleFrame: frame)
    #expect(clamped == CGPoint(x: 100, y: 100))
}

@Test func clampPanelBiggerThanScreenPinsMinEdge() {
    let frame = CGRect(x: 0, y: 0, width: 800, height: 600)
    let origin = CGPoint(x: 700, y: 500)   // panel 900px > layar
    let clamped = FloatingPosition.clamped(origin: origin, size: CGSize(width: 900, height: 800), visibleFrame: frame)
    #expect(clamped.x == 0)                // pinned ke minX — tidak pernah off-screen
    #expect(clamped.y == 0)
}

@Test func movedAddsDelta() {
    let origin = CGPoint(x: 100, y: 200)
    #expect(FloatingPosition.moved(origin: origin, by: CGSize(width: 30, height: -40)) == CGPoint(x: 130, y: 160))
}

@Test func nearestVisibleFramePrefersContaining() {
    let main = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    let second = CGRect(x: 1920, y: 0, width: 1440, height: 900)
    let inside = CGPoint(x: 2000, y: 300)
    #expect(FloatingPosition.nearestVisibleFrame(to: inside, frames: [main, second]) == second)
}

@Test func nearestVisibleFramePicksClosestWhenOutsideAll() {
    let main = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    let second = CGRect(x: 1920, y: 0, width: 1440, height: 900)
    // Titik di bawah monitor kedua (di luar SEMUA frame) → yang terdekat = second.
    let near = CGPoint(x: 2000, y: -50)
    #expect(FloatingPosition.nearestVisibleFrame(to: near, frames: [main, second]) == second)
}

@Test func nearestVisibleFrameNilWhenNoFrames() {
    #expect(FloatingPosition.nearestVisibleFrame(to: .zero, frames: []) == nil)
}