@testable import StandClearCore
import XCTest

final class DirectionVocabularyTests: XCTestCase {
    func testRouteVocabularyMapping() {
        let expected: [String: DirectionVocabulary] = [
            "1": .uptownDowntown,
            "2": .uptownDowntown,
            "3": .uptownDowntown,
            "4": .uptownDowntown,
            "5": .uptownDowntown,
            "5X": .uptownDowntown,
            "6": .uptownDowntown,
            "6X": .uptownDowntown,
            "A": .uptownDowntown,
            "B": .uptownDowntown,
            "C": .uptownDowntown,
            "D": .uptownDowntown,
            "E": .uptownDowntown,
            "F": .uptownDowntown,
            "FX": .uptownDowntown,
            "M": .uptownDowntown,
            "N": .uptownDowntown,
            "Q": .uptownDowntown,
            "R": .uptownDowntown,
            "W": .uptownDowntown,
            "J": .uptownDowntown,
            "Z": .uptownDowntown,
            "7": .queensManhattan,
            "7X": .queensManhattan,
            "L": .manhattanBrooklyn,
            "G": .queensBrooklyn,
            "GS": .timesSqGrandCentral,
            "FS": .franklinProspect,
            "H": .broadChannelRockaway,
            "SI": .stGeorgeTottenville,
        ]

        for (routeID, vocabulary) in expected {
            XCTAssertEqual(
                RouteID.vocabulary(routeID),
                vocabulary,
                "Unexpected vocabulary for \(routeID)"
            )
        }
    }

    func testUnknownRouteDefaultsToUptownDowntown() {
        XCTAssertEqual(RouteID.vocabulary("ZZ"), .uptownDowntown)
    }

    func testForSelectionDefaultsEmptyToUptownDowntown() {
        XCTAssertEqual(DirectionVocabulary.forSelection([] as Set<String>), .uptownDowntown)
    }

    func testForSelectionUsesSharedVocabulary() {
        XCTAssertEqual(DirectionVocabulary.forSelection(["Q", "N"]), .uptownDowntown)
        XCTAssertEqual(DirectionVocabulary.forSelection(["7", "7X"]), .queensManhattan)
        XCTAssertEqual(DirectionVocabulary.forSelection(["L"]), .manhattanBrooklyn)
    }

    func testForSelectionMajorityWinsOnMixedSets() {
        XCTAssertEqual(
            DirectionVocabulary.forSelection(["Q", "N", "7"]),
            .uptownDowntown
        )
        // Equal counts with no uptown/downtown entry: stable rawValue tie-break.
        XCTAssertEqual(
            DirectionVocabulary.forSelection(["7", "L"]),
            .manhattanBrooklyn
        )
    }

    func testCompatibleSubsetKeepsMajorityVocabulary() {
        XCTAssertEqual(
            DirectionVocabulary.compatibleSubset(of: ["Q", "N", "7"]),
            ["Q", "N"]
        )
        XCTAssertEqual(
            DirectionVocabulary.compatibleSubset(of: ["Q", "7"]),
            ["Q"]
        )
        XCTAssertEqual(
            DirectionVocabulary.compatibleSubset(of: ["7", "7X", "L"]),
            ["7", "7X"]
        )
    }

    func testCompatibleSubsetPreservesHomogeneousSelection() {
        XCTAssertEqual(
            DirectionVocabulary.compatibleSubset(of: ["N", "Q", "R"]),
            ["N", "Q", "R"]
        )
        XCTAssertEqual(
            DirectionVocabulary.compatibleSubset(of: ["L"]),
            ["L"]
        )
    }

    func testTitlesAndGlyphsForSpecialLines() {
        XCTAssertEqual(
            DirectionVocabulary.queensManhattan.title(for: .northbound),
            "QUEENS"
        )
        XCTAssertEqual(
            DirectionVocabulary.queensManhattan.glyph(for: .northbound),
            "→"
        )
        XCTAssertEqual(
            DirectionVocabulary.queensManhattan.title(for: .southbound),
            "MANHATTAN"
        )
        XCTAssertEqual(
            DirectionVocabulary.queensManhattan.glyph(for: .southbound),
            "←"
        )

        XCTAssertEqual(
            DirectionVocabulary.manhattanBrooklyn.title(for: .northbound),
            "MANHATTAN"
        )
        XCTAssertEqual(
            DirectionVocabulary.manhattanBrooklyn.glyph(for: .northbound),
            "←"
        )
        XCTAssertEqual(
            DirectionVocabulary.manhattanBrooklyn.title(for: .southbound),
            "BROOKLYN"
        )
        XCTAssertEqual(
            DirectionVocabulary.manhattanBrooklyn.glyph(for: .southbound),
            "→"
        )

        XCTAssertEqual(
            DirectionVocabulary.uptownDowntown.title(for: .northbound),
            "UPTOWN"
        )
        XCTAssertEqual(
            DirectionVocabulary.uptownDowntown.glyph(for: .northbound),
            "↑"
        )
    }

    func testAccessibilityNames() {
        XCTAssertEqual(
            DirectionVocabulary.uptownDowntown.accessibilityName(for: .northbound),
            "uptown"
        )
        XCTAssertEqual(
            DirectionVocabulary.queensManhattan.accessibilityName(for: .northbound),
            "toward Queens"
        )
        XCTAssertEqual(
            DirectionVocabulary.timesSqGrandCentral.accessibilityName(for: .southbound),
            "toward Grand Central"
        )
    }
}
