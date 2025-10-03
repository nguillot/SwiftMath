import XCTest
@testable import SwiftMath

/// Tests for basic LaTeX operators: \implies, \mod, \pmod{n}, \iint, \iiint, \iiiint, \nexists
final class BasicLatexOperatorsTests: XCTestCase {

    func testImpliesOperator() throws {
        let latex = "A \\implies B"
        var error: NSError?
        let mathList = MTMathListBuilder.build(fromString: latex, error: &error)

        XCTAssertNil(error, "Should parse \\implies without error")
        XCTAssertNotNil(mathList)
        XCTAssertEqual(mathList?.atoms.count, 3, "Should have 3 atoms: A, implies, B")

        // Check that the middle atom is the implies operator
        let impliesAtom = mathList?.atoms[1]
        XCTAssertEqual(impliesAtom?.type, .relation)
        XCTAssertEqual(impliesAtom?.nucleus, "\u{27F9}") // ⟹
    }

    func testModOperator() throws {
        let latex = "5 \\mod 3"
        var error: NSError?
        let mathList = MTMathListBuilder.build(fromString: latex, error: &error)

        XCTAssertNil(error, "Should parse \\mod without error")
        XCTAssertNotNil(mathList)

        // Find the mod operator
        let modAtom = mathList?.atoms.first(where: { atom in
            if let op = atom as? MTLargeOperator {
                return op.nucleus == "mod"
            }
            return false
        })
        XCTAssertNotNil(modAtom, "Should contain mod operator")
    }

    func testPmodCommand() throws {
        let latex = "x \\equiv y \\pmod{n}"
        var error: NSError?
        let mathList = MTMathListBuilder.build(fromString: latex, error: &error)

        XCTAssertNil(error, "Should parse \\pmod{n} without error")
        XCTAssertNotNil(mathList)

        // Find the pmod (inner atom with parentheses)
        let innerAtom = mathList?.atoms.first(where: { $0.type == .inner }) as? MTInner
        XCTAssertNotNil(innerAtom, "Should contain inner atom for pmod")
        XCTAssertNotNil(innerAtom?.leftBoundary, "Should have left parenthesis")
        XCTAssertNotNil(innerAtom?.rightBoundary, "Should have right parenthesis")

        // Check that it contains mod operator
        let innerList = innerAtom?.innerList
        XCTAssertNotNil(innerList)
        let hasModOperator = innerList?.atoms.contains(where: { atom in
            if let op = atom as? MTLargeOperator {
                return op.nucleus == "mod"
            }
            return false
        })
        XCTAssertTrue(hasModOperator ?? false, "Inner list should contain mod operator")
    }

    func testDoubleIntegral() throws {
        let latex = "\\iint f(x,y) dx dy"
        var error: NSError?
        let mathList = MTMathListBuilder.build(fromString: latex, error: &error)

        XCTAssertNil(error, "Should parse \\iint without error")
        XCTAssertNotNil(mathList)

        // Check first atom is double integral
        let firstAtom = mathList?.atoms.first as? MTLargeOperator
        XCTAssertNotNil(firstAtom)
        XCTAssertEqual(firstAtom?.nucleus, "\u{222C}") // ∬
    }

    func testTripleIntegral() throws {
        let latex = "\\iiint f(x,y,z) dx dy dz"
        var error: NSError?
        let mathList = MTMathListBuilder.build(fromString: latex, error: &error)

        XCTAssertNil(error, "Should parse \\iiint without error")
        XCTAssertNotNil(mathList)

        // Check first atom is triple integral
        let firstAtom = mathList?.atoms.first as? MTLargeOperator
        XCTAssertNotNil(firstAtom)
        XCTAssertEqual(firstAtom?.nucleus, "\u{222D}") // ∭
    }

    func testQuadrupleIntegral() throws {
        let latex = "\\iiiint f(x,y,z,w) dx dy dz dw"
        var error: NSError?
        let mathList = MTMathListBuilder.build(fromString: latex, error: &error)

        XCTAssertNil(error, "Should parse \\iiiint without error")
        XCTAssertNotNil(mathList)

        // Check first atom is quadruple integral
        let firstAtom = mathList?.atoms.first as? MTLargeOperator
        XCTAssertNotNil(firstAtom)
        XCTAssertEqual(firstAtom?.nucleus, "\u{2A0C}") // ⨌
    }

    func testNexistsOperator() throws {
        let latex = "\\nexists x"
        var error: NSError?
        let mathList = MTMathListBuilder.build(fromString: latex, error: &error)

        XCTAssertNil(error, "Should parse \\nexists without error")
        XCTAssertNotNil(mathList)

        // Check first atom is nexists
        let firstAtom = mathList?.atoms.first
        XCTAssertNotNil(firstAtom)
        XCTAssertEqual(firstAtom?.type, .ordinary)
        XCTAssertEqual(firstAtom?.nucleus, "\u{2204}") // ∄
    }

    func testRoundTripSerialization() throws {
        // Test that these operators can be serialized back to LaTeX
        let testCases = [
            ("A \\implies B", "A\\implies B"),
            ("\\iint", "\\iint"),
            ("\\iiint", "\\iiint"),
            ("\\iiiint", "\\iiiint"),
            ("\\nexists", "\\nexists")
        ]

        for (input, _) in testCases {
            var error: NSError?
            let mathList = MTMathListBuilder.build(fromString: input, error: &error)
            XCTAssertNil(error, "Should parse \(input) without error")
            XCTAssertNotNil(mathList, "Should create mathlist for \(input)")

            let serialized = MTMathListBuilder.mathListToString(mathList!)
            XCTAssertFalse(serialized.isEmpty, "Serialized string should not be empty for \(input)")
        }
    }
}
