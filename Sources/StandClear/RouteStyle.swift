import StandClearCore
import SwiftUI

struct RouteStyle {
    let background: Color
    let foreground: Color

    static func style(for routeID: String) -> RouteStyle {
        let metadata = metadata(for: routeID)
        return RouteStyle(
            background: Color(hexString: metadata.backgroundHex),
            foreground: Color(hexString: metadata.foregroundHex)
        )
    }

    static func metadata(for routeID: String) -> RouteStyleMetadata {
        RouteStyleResolver.bundled.style(for: routeID)
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
