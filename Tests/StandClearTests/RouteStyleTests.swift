import AppKit
@testable import StandClear
import XCTest

final class RouteStyleTests: XCTestCase {
    func testABadgeStyleUsesBundledMTAColorInsteadOfLegacyFallback() {
        let metadata = RouteStyle.metadata(for: "A")
        let style = RouteStyle.style(for: "A")

        XCTAssertEqual(metadata.backgroundHex, "0062CF")
        XCTAssertEqual(metadata.foregroundHex, "FFFFFF")
        XCTAssertNotEqual(metadata.backgroundHex, "0039A6")
        XCTAssertEqual(NSColor(style.background).hexString, metadata.backgroundHex)
    }
}

private extension NSColor {
    var hexString: String {
        guard let rgb = usingColorSpace(.sRGB) else { return "" }
        return String(
            format: "%02X%02X%02X",
            Int((rgb.redComponent * 255).rounded()),
            Int((rgb.greenComponent * 255).rounded()),
            Int((rgb.blueComponent * 255).rounded())
        )
    }
}
