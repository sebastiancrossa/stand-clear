import StandClearCore
import SwiftUI

struct RouteStyle {
    let background: Color
    let foreground: Color

    static func style(for routeID: String) -> RouteStyle {
        RouteStyle(
            background: Color(hexString: RouteColor.backgroundHex(for: routeID)),
            foreground: Color(hexString: RouteColor.textHex(for: routeID))
        )
    }
}

extension Color {
    init(hexString: String) {
        self.init(hex: UInt32(hexString, radix: 16) ?? 0x808183)
    }

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
