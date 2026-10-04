import AppKit
import SwiftUI

enum Theme {
    static let bg = Color(red: 0.09, green: 0.08, blue: 0.07)
    static let panel = Color(red: 0.13, green: 0.12, blue: 0.11)
    static let elevated = Color(red: 0.18, green: 0.16, blue: 0.14)
    static let field = Color(red: 0.10, green: 0.09, blue: 0.08)
    static let canvas = Color(red: 0.06, green: 0.055, blue: 0.05)
    static let line = Color(red: 0.34, green: 0.28, blue: 0.22)
    static let amber = Color(red: 0.93, green: 0.62, blue: 0.28)
    static let amberDeep = Color(red: 0.72, green: 0.42, blue: 0.16)
    static let text = Color(red: 0.94, green: 0.91, blue: 0.86)
    static let muted = Color(red: 0.64, green: 0.58, blue: 0.50)
    static let ink = Color(red: 0.14, green: 0.10, blue: 0.06)
    static let danger = Color(red: 0.86, green: 0.40, blue: 0.30)

    static let windowNS = NSColor(calibratedRed: 0.09, green: 0.08, blue: 0.07, alpha: 1)
}

struct PlateButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, ghost, tool }
    var kind: Kind = .secondary
    var selected = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, kind == .tool ? 0 : 12)
            .padding(.vertical, kind == .tool ? 0 : 6)
            .frame(maxWidth: kind == .tool ? .infinity : nil)
            .foregroundStyle(foreground)
            .background(background.opacity(configuration.isPressed ? 0.75 : 1))
            .clipShape(RoundedRectangle(cornerRadius: kind == .tool ? 8 : 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: kind == .tool ? 8 : 14, style: .continuous)
                    .stroke(stroke, lineWidth: 1)
            )
    }

    private var foreground: Color {
        switch kind {
        case .primary: return Theme.ink
        case .tool: return selected ? Theme.ink : Theme.text
        case .secondary, .ghost: return Theme.text
        }
    }

    private var background: Color {
        switch kind {
        case .primary: return Theme.amber
        case .tool: return selected ? Theme.amber : Theme.elevated
        case .secondary: return Theme.elevated
        case .ghost: return .clear
        }
    }

    private var stroke: Color {
        switch kind {
        case .primary: return Theme.amber
        case .tool: return selected ? Theme.amber : Theme.line
        case .secondary: return Theme.line
        case .ghost: return Theme.line.opacity(0.7)
        }
    }
}
