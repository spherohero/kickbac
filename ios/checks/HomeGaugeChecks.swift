import SwiftUI

// DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc -target arm64-apple-macos26.0 ios/KickBAC/HomeGauge.swift ios/checks/HomeGaugeChecks.swift -o /tmp/kickbac-home-gauge-checks
// /tmp/kickbac-home-gauge-checks
@main
struct HomeGaugeChecks {
    static func main() {
        let rect = CGRect(x: 0, y: 0, width: 300, height: 300)
        let style = StrokeStyle(lineWidth: 10, lineCap: .round)
        func point(at angle: Double) -> CGPoint {
            let radians = angle * .pi / 180
            return CGPoint(x: 150 + 150 * cos(radians), y: 150 + 150 * sin(radians))
        }
        let full = GaugeArc(progress: 1).path(in: rect).strokedPath(style)
        precondition(!full.contains(point(at: 90)), "Gauge must leave bottom gap open")
        precondition(!full.contains(CGPoint(x: 150, y: 150)), "Gauge center must stay clear")
        precondition(GaugeArc(progress: 0).path(in: rect).isEmpty, "Empty progress must draw nothing")
        for progress in [0.25, 0.5, 0.75, 1.0] {
            let fill = GaugeArc(progress: progress).path(in: rect).strokedPath(style)
            for fraction in [0.125, 0.375, 0.625, 0.875] {
                precondition(fill.contains(point(at: 135 + 270 * fraction)) == (fraction < progress),
                             "Progress fill must grow along visible arc")
            }
        }
        for index in 0..<6 {
            let bounds = GaugeSegment(index: index).path(in: rect).boundingRect
            let mirror = GaugeSegment(index: 5 - index).path(in: rect).boundingRect
            precondition(abs(bounds.minX - (300 - mirror.maxX)) < 0.001
                         && abs(bounds.minY - mirror.minY) < 0.001,
                         "Result segments must mirror across gauge center")
            let segment = GaugeSegment(index: index).path(in: rect).strokedPath(style)
            precondition(!segment.contains(point(at: 90)), "Result segment must keep bottom gap open")
        }
        print("Home gauge checks passed: bottom gap, clear center, growing fill, and symmetric result segments.")
    }
}
