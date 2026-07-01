//
//  RadicalDegreeAscentTests.swift
//  SwiftMathTests
//
//  Verifies that the degree of an nth-root (e.g. the "8" in \sqrt[8]{x}) is
//  included in the radical display's reported ascent, so it does not protrude
//  above the radical and overlap content placed just above it. The reported
//  issue is that in "y^{3}=\sqrt[3]{x}+\dfrac{1}{\sqrt[8]{x}}-\sqrt[4]{x}" the
//  degree "8" of \sqrt[8]{x} crosses the horizontal fraction bar of the \dfrac.
//

import XCTest
@testable import SwiftMath

final class RadicalDegreeAscentTests: XCTestCase {

    var font: MTFont!

    override func setUpWithError() throws {
        try super.setUpWithError()
        self.font = MTFontManager.fontManager.defaultFont
    }

    override func tearDownWithError() throws {
        self.font = nil
        try super.tearDownWithError()
    }

    /// Recursively collects every MTRadicalDisplay in a display tree, descending
    /// into list displays as well as into the radicand/degree of radicals and the
    /// numerator/denominator of fractions.
    private func collectRadicals(_ display: MTDisplay) -> [MTRadicalDisplay] {
        var result = [MTRadicalDisplay]()
        switch display {
        case let radical as MTRadicalDisplay:
            result.append(radical)
            if let radicand = radical.radicand { result += collectRadicals(radicand) }
            if let degree = radical.degree { result += collectRadicals(degree) }
        case let fraction as MTFractionDisplay:
            if let n = fraction.numerator { result += collectRadicals(n) }
            if let d = fraction.denominator { result += collectRadicals(d) }
        case let list as MTMathListDisplay:
            for sub in list.subDisplays { result += collectRadicals(sub) }
        default:
            break
        }
        return result
    }

    /// Asserts that the degree of the single radical in `latex` fits within the
    /// radical's reported ascent (i.e. it does not protrude above the radical).
    private func assertDegreeFitsWithinAscent(_ latex: String, file: StaticString = #file, line: UInt = #line) throws {
        let mathList = try XCTUnwrap(MTMathListBuilder.build(fromString: latex),
                                     "Failed to parse: \(latex)", file: file, line: line)
        let display = try XCTUnwrap(MTTypesetter.createLineForMathList(mathList, font: self.font, style: .display),
                                    "Failed to typeset: \(latex)", file: file, line: line)
        let radical = try XCTUnwrap(collectRadicals(display).first(where: { $0.degree != nil }),
                                    "Expected a radical with a degree in: \(latex)", file: file, line: line)
        let degree = try XCTUnwrap(radical.degree, "Expected the radical to have a degree", file: file, line: line)

        // Degree position is relative to the radical's origin; its top above the
        // radical baseline must not exceed the radical's reported ascent.
        let degreeTopAboveBaseline = (degree.position.y - radical.position.y) + degree.ascent
        XCTAssertLessThanOrEqual(degreeTopAboveBaseline, radical.ascent + 0.01,
                                 "Degree protrudes above the radical's reported ascent in \(latex)",
                                 file: file, line: line)
    }

    func testDegreeFitsWithinRadicalAscent() throws {
        // Core reproduction: a short radicand makes the degree protrude above the
        // radical's (small) ascent. Guard all three indices from the reported case.
        try assertDegreeFitsWithinAscent("\\sqrt[8]{x}")
        try assertDegreeFitsWithinAscent("\\sqrt[3]{x}")
        try assertDegreeFitsWithinAscent("\\sqrt[4]{x}")
    }

    /// Recursively collects, in absolute canvas coordinates:
    /// - the bottom edge of every fraction bar, and
    /// - the top edge of every radical degree, flagged with whether it sits inside a fraction.
    /// `origin` is the absolute coordinate of the frame in which `display.position` is expressed.
    /// Y grows upward, matching the fraction-bar / ascent conventions used elsewhere.
    private func collectBarsAndDegrees(_ display: MTDisplay,
                                       origin: CGPoint,
                                       insideFraction: Bool,
                                       barBottoms: inout [CGFloat],
                                       degreeTops: inout [(top: CGFloat, insideFraction: Bool)]) {
        switch display {
        case let radical as MTRadicalDisplay:
            if let degree = radical.degree {
                degreeTops.append((top: origin.y + degree.position.y + degree.ascent, insideFraction: insideFraction))
                collectBarsAndDegrees(degree, origin: origin, insideFraction: insideFraction,
                                      barBottoms: &barBottoms, degreeTops: &degreeTops)
            }
            if let radicand = radical.radicand {
                collectBarsAndDegrees(radicand, origin: origin, insideFraction: insideFraction,
                                      barBottoms: &barBottoms, degreeTops: &degreeTops)
            }
        case let fraction as MTFractionDisplay:
            barBottoms.append(origin.y + fraction.position.y + fraction.linePosition - fraction.lineThickness / 2)
            if let n = fraction.numerator {
                collectBarsAndDegrees(n, origin: origin, insideFraction: insideFraction,
                                      barBottoms: &barBottoms, degreeTops: &degreeTops)
            }
            if let d = fraction.denominator {
                collectBarsAndDegrees(d, origin: origin, insideFraction: true,
                                      barBottoms: &barBottoms, degreeTops: &degreeTops)
            }
        case let list as MTMathListDisplay:
            let childOrigin = CGPoint(x: origin.x + list.position.x, y: origin.y + list.position.y)
            for sub in list.subDisplays {
                collectBarsAndDegrees(sub, origin: childOrigin, insideFraction: insideFraction,
                                      barBottoms: &barBottoms, degreeTops: &degreeTops)
            }
        default:
            break
        }
    }

    func testDegreeDoesNotCrossFractionBar() throws {
        let latex = "y^{3}=\\sqrt[3]{x}+\\dfrac{1}{\\sqrt[8]{x}}-\\sqrt[4]{x}"
        let mathList = try XCTUnwrap(MTMathListBuilder.build(fromString: latex))
        let display = try XCTUnwrap(MTTypesetter.createLineForMathList(mathList, font: self.font, style: .display))

        var barBottoms = [CGFloat]()
        var degreeTops = [(top: CGFloat, insideFraction: Bool)]()
        collectBarsAndDegrees(display, origin: .zero, insideFraction: false,
                              barBottoms: &barBottoms, degreeTops: &degreeTops)

        let barBottom = try XCTUnwrap(barBottoms.min(), "Expected a fraction bar")
        let denomDegreeTop = try XCTUnwrap(degreeTops.filter { $0.insideFraction }.map { $0.top }.max(),
                                           "Expected a degree inside the fraction denominator")

        // The \sqrt[8] degree must stay at or below the lower edge of the fraction bar.
        XCTAssertLessThanOrEqual(denomDegreeTop, barBottom + 0.01,
                                 "Degree of the denominator radical crosses the fraction bar")
    }
}
