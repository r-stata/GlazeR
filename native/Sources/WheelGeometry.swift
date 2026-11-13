// GlazeR — 转盘几何：扇区数量动态可配置（2...12）
import SwiftUI

enum WheelGeometry {
    static let size: CGFloat = 320
    static let center = CGPoint(x: 160, y: 160)
    static let radius: CGFloat = 152
    static let hubRadius: CGFloat = 60
    static let gapDeg: CGFloat = 2

    /// 楔形扇区路径（圆心 → 外弧 → 闭合）
    static func sectorPath(index: Int, count: Int) -> Path {
        let n = CGFloat(max(count, 2))
        let span = 360 / n
        let a0 = -90 + CGFloat(index) * span + gapDeg / 2
        let a1 = a0 + span - gapDeg
        var p = Path()
        p.move(to: center)
        p.addArc(center: center, radius: radius,
                 startAngle: .degrees(a0), endAngle: .degrees(a1), clockwise: false)
        p.closeSubpath()
        return p
    }

    static func midAngle(index: Int, count: Int) -> CGFloat {
        let n = CGFloat(max(count, 2))
        let span = 360 / n
        return -90 + CGFloat(index) * span + span / 2
    }

    /// 光标命中判定：入参为相对转盘中心的偏移（SwiftUI 坐标系，y 向下）
    static func sectorIndex(offset o: CGPoint, count: Int) -> Int {
        let r = sqrt(o.x * o.x + o.y * o.y)
        guard r >= hubRadius + 2, r <= radius - 2, count >= 2 else { return -1 }
        var deg = atan2(o.y, o.x) * 180 / .pi + 90
        if deg < 0 { deg += 360 }
        let idx = Int(deg / (360 / CGFloat(count)))
        return (idx >= 0 && idx < count) ? idx : -1
    }
}
