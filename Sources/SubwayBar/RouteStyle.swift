import SubwayBarCore
import SwiftUI

struct RouteStyle {
    let background: Color
    let foreground: Color

    static func style(for routeID: String) -> RouteStyle {
        switch RouteID.baseLine(routeID) {
        case "A", "C", "E": RouteStyle(background: Color(hex: 0x0039A6), foreground: .white)
        case "B", "D", "F", "M": RouteStyle(background: Color(hex: 0xFF6319), foreground: .white)
        case "G": RouteStyle(background: Color(hex: 0x6CBE45), foreground: .white)
        case "J", "Z": RouteStyle(background: Color(hex: 0x996633), foreground: .white)
        case "N", "Q", "R", "W": RouteStyle(background: Color(hex: 0xFCCC0A), foreground: .black)
        case "1", "2", "3": RouteStyle(background: Color(hex: 0xEE352E), foreground: .white)
        case "4", "5", "6": RouteStyle(background: Color(hex: 0x00933C), foreground: .white)
        case "7": RouteStyle(background: Color(hex: 0xB933AD), foreground: .white)
        case "SI": RouteStyle(background: Color(hex: 0x0039A6), foreground: .white)
        default: RouteStyle(background: Color(hex: 0x808183), foreground: .white)
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: 1
        )
    }
}
