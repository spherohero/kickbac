import SwiftUI

struct TriviaWheel: View {
    @Binding var rotation: Double
    let isEnabled: Bool
    let onSpin: (Bool, Int, Double) -> Void
    @State private var previousAngle: Double?
    @State private var lastDelta = 0.0

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            Button { onSpin(true, 3, 0) } label: {
                ZStack {
                    ZStack {
                        ForEach(Array(TriviaCategory.allCases.enumerated()), id: \.element) { index, category in
                            let angle = Double(index) * 60 - 60
                            WheelSlice(index: index).fill(category.color)
                                .overlay { WheelSlice(index: index).stroke(Color("SplashBackground"), lineWidth: 3) }
                            Text(category.shortTitle)
                                .font(.system(size: side * 0.036, weight: .bold, design: .rounded))
                                .foregroundStyle(.black).rotationEffect(.degrees(angle + 90))
                                .offset(x: cos(angle * .pi / 180) * side * 0.32, y: sin(angle * .pi / 180) * side * 0.32)
                        }
                        Circle().fill(Color("SplashBackground")).frame(width: side * 0.22, height: side * 0.22)
                        KickBACStar(progress: 0, size: side * 0.105, isExpanding: false)
                    }.rotationEffect(.degrees(rotation))
                    WheelPointer().fill(.white).frame(width: 20, height: 22).offset(y: -side * 0.46)
                }.contentShape(.circle)
            }
            .buttonStyle(ProfilePressStyle()).disabled(!isEnabled)
            .highPriorityGesture(drag(side: side), including: isEnabled ? .all : .none)
            .accessibilityElement(children: .ignore).accessibilityLabel("Spin category wheel")
            .accessibilityHint("Double-tap to choose a category")
        }
    }

    private func drag(side: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                let current = angle(value.location, side: side)
                let previous = previousAngle ?? angle(value.startLocation, side: side)
                lastDelta = TriviaWheelMotion.delta(from: previous, to: current)
                rotation += lastDelta
                previousAngle = current
            }
            .onEnded { value in
                let projected = TriviaWheelMotion.delta(from: angle(value.location, side: side),
                                                       to: angle(value.predictedEndLocation, side: side))
                let radial = CGSize(width: value.location.x - side / 2, height: value.location.y - side / 2)
                let radiusSquared = radial.width * radial.width + radial.height * radial.height
                let velocity = radiusSquared > 100
                    ? (radial.width * value.velocity.height - radial.height * value.velocity.width) / radiusSquared * 180 / .pi
                    : 0
                let momentum = abs(velocity) > 20 ? velocity : abs(projected) > 2 ? projected : lastDelta
                previousAngle = nil
                onSpin(momentum >= 0, min(5, max(2, Int(abs(projected) / 35) + 2)), velocity)
            }
    }

    private func angle(_ point: CGPoint, side: CGFloat) -> Double {
        atan2(point.y - side / 2, point.x - side / 2) * 180 / .pi
    }
}

private struct WheelPointer: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

private struct WheelSlice: Shape {
    let index: Int
    func path(in rect: CGRect) -> Path {
        Path { path in
            let center = CGPoint(x: rect.midX, y: rect.midY)
            path.move(to: center)
            path.addArc(center: center, radius: min(rect.width, rect.height) / 2,
                        startAngle: .degrees(Double(index) * 60 - 90),
                        endAngle: .degrees(Double(index + 1) * 60 - 90), clockwise: false)
            path.closeSubpath()
        }
    }
}

extension TriviaCategory {
    var color: Color {
        switch self {
        case .world: Color(red: 0.55, green: 0.76, blue: 0.94)
        case .science: Color(red: 0.58, green: 0.83, blue: 0.68)
        case .history: Color(red: 0.94, green: 0.80, blue: 0.32)
        case .sports: Color(red: 0.97, green: 0.61, blue: 0.40)
        case .arts: Color(red: 0.72, green: 0.65, blue: 0.91)
        case .entertainment: Color(red: 0.94, green: 0.60, blue: 0.75)
        }
    }
}
