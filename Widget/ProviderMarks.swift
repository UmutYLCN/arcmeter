import QuotaCore
import SwiftUI

/// Provider marks drawn as vectors so they stay sharp at every widget size.
/// Claude, Codex and Gemini are simplified redrawings of the brand marks; the Antigravity
/// mark follows the official full-color icon from antigravity.google/press.
struct ProviderLogo: View {
    let mark: ProviderMark
    let size: CGFloat

    var body: some View {
        Group {
            switch mark {
            case .claude:
                ClaudeShape().fill(Color(red: 0.808, green: 0.529, blue: 0.416))
            case .codex:
                CodexShape().stroke(OrbitTheme.logo, style: StrokeStyle(lineWidth: size * 1.65 / 32, lineJoin: .round))
            case .gemini:
                GeminiShape().fill(Color(red: 0.4, green: 0.584, blue: 0.933))
            case .agy:
                AntigravityMark(size: size)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private func unit(_ rect: CGRect) -> CGAffineTransform {
    CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: rect.width / 32, y: rect.height / 32)
}

private func rotated(_ path: Path, count: Int) -> Path {
    var result = Path()
    let step = 360.0 / Double(count)
    for index in 0..<count {
        let angle = Angle.degrees(step * Double(index)).radians
        let transform = CGAffineTransform(translationX: 16, y: 16).rotated(by: angle).translatedBy(x: -16, y: -16)
        result.addPath(path, transform: transform)
    }
    return result
}

struct ClaudeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var ray = Path()
        ray.addRoundedRect(in: CGRect(x: 14.75, y: 3, width: 2.5, height: 8), cornerSize: CGSize(width: 1.25, height: 1.25))
        var result = rotated(ray, count: 12)
        result.addEllipse(in: CGRect(x: 11, y: 11, width: 10, height: 10))
        return result.applying(unit(rect))
    }
}

struct CodexShape: Shape {
    func path(in rect: CGRect) -> Path {
        var petal = Path()
        petal.move(to: CGPoint(x: 16, y: 5))
        petal.addCurve(to: CGPoint(x: 26, y: 13), control1: CGPoint(x: 22, y: 1), control2: CGPoint(x: 29, y: 7))
        petal.addLine(to: CGPoint(x: 16, y: 19))
        petal.addLine(to: CGPoint(x: 10, y: 15))
        petal.addLine(to: CGPoint(x: 10, y: 9))
        petal.closeSubpath()
        return rotated(petal, count: 6).applying(unit(rect))
    }
}

struct GeminiShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 16, y: 1))
        path.addCurve(to: CGPoint(x: 31, y: 16), control1: CGPoint(x: 18, y: 10), control2: CGPoint(x: 22, y: 14))
        path.addCurve(to: CGPoint(x: 16, y: 31), control1: CGPoint(x: 22, y: 18), control2: CGPoint(x: 18, y: 22))
        path.addCurve(to: CGPoint(x: 1, y: 16), control1: CGPoint(x: 14, y: 22), control2: CGPoint(x: 10, y: 18))
        path.addCurve(to: CGPoint(x: 16, y: 1), control1: CGPoint(x: 10, y: 14), control2: CGPoint(x: 14, y: 10))
        path.closeSubpath()
        return path.applying(unit(rect))
    }
}

/// Parses the absolute M, C and Z commands the Antigravity icon uses.
struct SVGPath {
    static func path(_ data: String) -> Path {
        var path = Path()
        var numbers: [CGFloat] = []
        var command: Character = "M"
        func flush() {
            switch command {
            case "M": if numbers.count >= 2 { path.move(to: CGPoint(x: numbers[0], y: numbers[1])) }
            case "C":
                var index = 0
                while index + 5 < numbers.count {
                    path.addCurve(to: CGPoint(x: numbers[index + 4], y: numbers[index + 5]),
                                  control1: CGPoint(x: numbers[index], y: numbers[index + 1]),
                                  control2: CGPoint(x: numbers[index + 2], y: numbers[index + 3]))
                    index += 6
                }
            default: break
            }
            numbers = []
        }
        var token = ""
        func endToken() { if let value = Double(token) { numbers.append(CGFloat(value)) }; token = "" }
        for character in data {
            if character.isLetter {
                endToken(); flush()
                command = character
                if character == "Z" { path.closeSubpath() }
            } else if character == " " || character == "," {
                endToken()
            } else if character == "-" {
                endToken(); token = "-"
            } else { token.append(character) }
        }
        endToken(); flush()
        return path
    }
}

private struct SVGShape: Shape {
    let data: String
    func path(in rect: CGRect) -> Path { SVGPath.path(data) }
}

private struct Blob {
    let color: Color
    let blur: CGFloat
    let path: Path

    static func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat, rotate degrees: Double,
                        _ hex: UInt32, blur: CGFloat) -> Blob {
        let transform = CGAffineTransform(translationX: cx, y: cy).rotated(by: Angle.degrees(degrees).radians)
            .translatedBy(x: -cx, y: -cy)
        return Blob(color: Color(hex: hex), blur: blur,
                    path: Path(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: 2 * rx, height: 2 * ry)).applying(transform))
    }

    static func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat, matrix m: [CGFloat],
                        _ hex: UInt32, blur: CGFloat) -> Blob {
        let transform = CGAffineTransform(a: m[0], b: m[1], c: m[2], d: m[3], tx: m[4], ty: m[5])
        return Blob(color: Color(hex: hex), blur: blur,
                    path: Path(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: 2 * rx, height: 2 * ry)).applying(transform))
    }

    static let all: [Blob] = [
        .ellipse(36.6225, 43.0872, 36.6225, 43.0872, matrix: [-0.112784, 0.99362, -0.99362, -0.112781, 106.557, -26.4847], 0xFFE432, blur: 6.25),
        .ellipse(155.163, 54.9292, 47.4118, 48.4541, rotate: 76.9243, 0xFC413D, blur: 30.2),
        .ellipse(14.6006, 65.4425, 49.5515, 64.192, rotate: 74.1257, 0x00B95C, blur: 25.7),
        .ellipse(18.1226, 67.414, 48.5679, 53.4688, rotate: 45.6065, 0x00B95C, blur: 25.7),
        .ellipse(121.837, 166.945, 46.6356, 44.9084, rotate: 76.9243, 0x3186FF, blur: 24.4),
        .ellipse(53.9456, 56.8997, 53.9456, 56.8997, matrix: [-0.409539, 0.912293, -0.912294, -0.409537, 162.811, -25.895], 0xFBBC04, blur: 22.1),
        Blob(color: Color(hex: 0x3186FF), blur: 19.8, path: SVGPath.path("M4.21557 239.063C-25.3231 227.467 25.1577 132.061 37.7105 100.085C50.2634 68.1097 84.3853 51.5888 113.924 63.1848C143.463 74.7809 178.474 138.65 165.921 170.626C153.368 202.601 33.7543 250.659 4.21557 239.063Z")),
        Blob(color: Color(hex: 0x749BFF), blur: 17.7, path: SVGPath.path("M183.197 120.315C175.289 129.545 154.652 124.839 137.102 109.803C119.553 94.7668 111.738 75.0955 119.646 65.8656C127.554 56.6357 148.191 61.3423 165.74 76.3782C183.289 91.414 191.105 111.085 183.197 120.315Z")),
        .ellipse(148.928, 36.7252, 71.1018, 44.199, rotate: 34.0763, 0xFC413D, blur: 14.9),
        .ellipse(37.848, 46.0346, 38.1008, 22.1575, rotate: 112.516, 0xFFEE48, blur: 18.5),
    ]
}

struct AntigravityMark: View {
    let size: CGFloat
    private static let outline = "M144.248 149.062C151.748 154.688 162.998 150.938 152.685 140.625C121.748 110.625 128.31 28.125 89.8727 28.125C51.4352 28.125 57.9977 110.625 27.0602 140.625C15.8102 151.875 27.9977 154.688 35.4977 149.062C64.5602 129.375 62.6852 94.6875 89.8727 94.6875C117.06 94.6875 115.185 129.375 144.248 149.062Z"

    var body: some View {
        ZStack {
            ForEach(Array(Blob.all.enumerated()), id: \.offset) { _, blob in
                blob.path.fill(blob.color).blur(radius: blob.blur)
            }
        }
        .frame(width: 180, height: 180)
        .mask(SVGShape(data: Self.outline))
        .scaleEffect(size / 142)
        .frame(width: size, height: size)
    }
}
