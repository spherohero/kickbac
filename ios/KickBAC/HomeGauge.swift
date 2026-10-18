import SwiftUI

@Animatable
struct GaugeArc: Shape {
    var progress: Double

    func path(in rect: CGRect) -> Path {
        guard progress > 0 else { return Path() }
        var path = Path()
        path.addArc(center: CGPoint(x: rect.midX, y: rect.midY),
                    radius: min(rect.width, rect.height) / 2,
                    startAngle: .degrees(135),
                    endAngle: .degrees(135 + 270 * min(progress, 1)), clockwise: false)
        return path
    }
}

struct GaugeSegment: Shape {
    let index: Int

    func path(in rect: CGRect) -> Path {
        let start = 135 + Double(index) * 45 + 2.4
        var path = Path()
        path.addArc(center: CGPoint(x: rect.midX, y: rect.midY),
                    radius: min(rect.width, rect.height) / 2,
                    startAngle: .degrees(start), endAngle: .degrees(start + 40.2), clockwise: false)
        return path
    }
}
