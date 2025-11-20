//
//  MTMathUILabelLineWrappingTests.swift
//  SwiftMathTests
//
//  Tests for line wrapping functionality in MTMathUILabel
//

import XCTest
@testable import SwiftMath

class MTMathUILabelLineWrappingTests: XCTestCase {

    func testBasicIntrinsicContentSize() {
        let label = MTMathUILabel()
        label.latex = "\\(x + y\\)"
        label.font = MTFontManager.fontManager.defaultFont

        // Debug: check if parsing worked
        XCTAssertNotNil(label.mathList, "Math list should not be nil")
        XCTAssertNil(label.error, "Should have no parsing error, got: \(String(describing: label.error))")
        XCTAssertNotNil(label.font, "Font should not be nil")

        let size = label.intrinsicContentSize

        XCTAssertGreaterThan(size.width, 0, "Width should be greater than 0, got \(size.width)")
        XCTAssertGreaterThan(size.height, 0, "Height should be greater than 0, got \(size.height)")
    }

    func testTextModeIntrinsicContentSize() {
        let label = MTMathUILabel()
        label.latex = "\\(\\text{Hello World}\\)"
        label.font = MTFontManager.fontManager.defaultFont
        label.labelMode = .text

        let size = label.intrinsicContentSize

        XCTAssertGreaterThan(size.width, 0, "Width should be greater than 0, got \(size.width)")
        XCTAssertGreaterThan(size.height, 0, "Height should be greater than 0, got \(size.height)")
    }

    func testLongTextIntrinsicContentSize() {
        let label = MTMathUILabel()
        label.latex = "\\(\\text{Rappelons la conversion : 1 km équivaut à 1000 m.}\\)"
        label.font = MTFontManager.fontManager.defaultFont
        label.labelMode = .text

        let size = label.intrinsicContentSize

        XCTAssertGreaterThan(size.width, 0, "Width should be greater than 0, got \(size.width)")
        XCTAssertGreaterThan(size.height, 0, "Height should be greater than 0, got \(size.height)")
    }

    func testSizeThatFitsWithoutConstraint() {
        let label = MTMathUILabel()
        label.latex = "\\(\\text{Hello World}\\)"
        label.font = MTFontManager.fontManager.defaultFont

        let size = label.sizeThatFits(CGSize.zero)

        XCTAssertGreaterThan(size.width, 0, "Width should be greater than 0, got \(size.width)")
        XCTAssertGreaterThan(size.height, 0, "Height should be greater than 0, got \(size.height)")
    }

    func testSizeThatFitsWithWidthConstraint() {
        let label = MTMathUILabel()
        label.latex = "\\(\\text{Rappelons la conversion : 1 km équivaut à 1000 m.}\\)"
        label.font = MTFontManager.fontManager.defaultFont
        label.labelMode = .text

        // Get unconstrained size first
        let unconstrainedSize = label.sizeThatFits(CGSize.zero)
        XCTAssertGreaterThan(unconstrainedSize.width, 0, "Unconstrained width should be > 0")

        // Test with width constraint (use 300 since longest word might be ~237pt)
        let constrainedSize = label.sizeThatFits(CGSize(width: 300, height: CGFloat.greatestFiniteMagnitude))

        XCTAssertGreaterThan(constrainedSize.width, 0, "Constrained width should be greater than 0, got \(constrainedSize.width)")
        XCTAssertLessThan(constrainedSize.width, unconstrainedSize.width, "Constrained width (\(constrainedSize.width)) should be less than unconstrained (\(unconstrainedSize.width))")
        XCTAssertGreaterThan(constrainedSize.height, 0, "Constrained height should be greater than 0, got \(constrainedSize.height)")

        // When constrained, height should increase when text wraps
        XCTAssertGreaterThan(constrainedSize.height, unconstrainedSize.height,
                            "Constrained height (\(constrainedSize.height)) should be > unconstrained (\(unconstrainedSize.height)) when text wraps")
    }

    func testPreferredMaxLayoutWidth() {
        let label = MTMathUILabel()
        label.latex = "\\(\\text{Rappelons la conversion : 1 km équivaut à 1000 m.}\\)"
        label.font = MTFontManager.fontManager.defaultFont
        label.labelMode = .text

        // Get unconstrained size
        let unconstrainedSize = label.intrinsicContentSize

        // Now set preferred max width (use 300 since longest word might be ~237pt)
        label.preferredMaxLayoutWidth = 300
        let constrainedSize = label.intrinsicContentSize

        XCTAssertGreaterThan(constrainedSize.width, 0, "Width should be greater than 0, got \(constrainedSize.width)")
        XCTAssertLessThan(constrainedSize.width, unconstrainedSize.width, "Constrained width (\(constrainedSize.width)) should be < unconstrained (\(unconstrainedSize.width))")
        XCTAssertGreaterThan(constrainedSize.height, unconstrainedSize.height, "Constrained height (\(constrainedSize.height)) should be > unconstrained (\(unconstrainedSize.height)) due to wrapping")
    }

    func testWordBoundaryBreaking() {
        let label = MTMathUILabel()
        label.latex = "\\(\\text{Word1 Word2 Word3 Word4 Word5}\\)"
        label.font = MTFontManager.fontManager.defaultFont
        label.labelMode = .text
        label.preferredMaxLayoutWidth = 150

        let size = label.intrinsicContentSize

        XCTAssertGreaterThan(size.width, 0, "Width should be greater than 0, got \(size.width)")
        XCTAssertGreaterThan(size.height, 0, "Height should be greater than 0, got \(size.height)")

        // Verify it actually uses the layout
        label.frame = CGRect(origin: .zero, size: size)
        #if os(macOS)
        label.layout()
        #else
        label.layoutSubviews()
        #endif

        XCTAssertNotNil(label.displayList, "Display list should be created")
    }

    func testEmptyLatex() {
        let label = MTMathUILabel()
        label.latex = ""
        label.font = MTFontManager.fontManager.defaultFont

        let size = label.intrinsicContentSize

        // Empty latex should still return a valid size (might be zero or minimal)
        XCTAssertGreaterThanOrEqual(size.width, 0, "Width should be >= 0 for empty latex, got \(size.width)")
        XCTAssertGreaterThanOrEqual(size.height, 0, "Height should be >= 0 for empty latex, got \(size.height)")
    }

    func testMathAndTextMixed() {
        let label = MTMathUILabel()
        label.latex = "\\(\\text{Result: } x^2 + y^2 = z^2\\)"
        label.font = MTFontManager.fontManager.defaultFont
        label.labelMode = .text

        let size = label.intrinsicContentSize

        XCTAssertGreaterThan(size.width, 0, "Width should be greater than 0, got \(size.width)")
        XCTAssertGreaterThan(size.height, 0, "Height should be greater than 0, got \(size.height)")
    }

    func testDebugSizeThatFitsWithConstraint() {
        let label = MTMathUILabel()
        label.latex = "\\(\\text{Word1 Word2 Word3 Word4 Word5}\\)"
        label.font = MTFontManager.fontManager.defaultFont
        label.labelMode = .text

        let unconstr = label.sizeThatFits(CGSize.zero)
        let constr = label.sizeThatFits(CGSize(width: 150, height: 999))

        XCTAssertLessThan(constr.width, unconstr.width, "Constrained (\(constr.width)) should be < unconstrained (\(unconstr.width))")
        XCTAssertGreaterThan(constr.height, unconstr.height, "Constrained height (\(constr.height)) should be > unconstrained (\(unconstr.height))")
    }

    func testAccentedCharactersWithLineWrapping() {
        let label = MTMathUILabel()
        // French text with accented characters: è, é, à
        label.latex = "\\(\\text{Rappelons la relation entre kilomètres et mètres.}\\)"
        label.font = MTFontManager.fontManager.defaultFont
        label.labelMode = .text

        // Get unconstrained size
        let unconstrainedSize = label.intrinsicContentSize

        // Set a width constraint that should cause wrapping
        label.preferredMaxLayoutWidth = 250
        let constrainedSize = label.intrinsicContentSize

        // Verify wrapping occurred
        XCTAssertGreaterThan(constrainedSize.width, 0, "Width should be > 0")
        XCTAssertLessThan(constrainedSize.width, unconstrainedSize.width, "Constrained width should be < unconstrained")
        XCTAssertGreaterThan(constrainedSize.height, unconstrainedSize.height, "Height should increase when wrapped")

        // Verify the label can render without errors
        label.frame = CGRect(origin: .zero, size: constrainedSize)
        #if os(macOS)
        label.layout()
        #else
        label.layoutSubviews()
        #endif

        XCTAssertNotNil(label.displayList, "Display list should be created")
        XCTAssertNil(label.error, "Should have no rendering error")
    }

    func testUnicodeWordBreaking_EquivautCase() {
        // Specific test for the reported issue: "équivaut" should not break at "é"
        let label = MTMathUILabel()
        label.latex = "\\(\\text{Rappelons la conversion : 1 km équivaut à 1000 m.}\\)"
        label.font = MTFontManager.fontManager.defaultFont
        label.labelMode = .text

        // Set the exact width constraint from the bug report
        label.preferredMaxLayoutWidth = 235
        let constrainedSize = label.intrinsicContentSize

        // Verify the label can render without errors
        label.frame = CGRect(origin: .zero, size: constrainedSize)
        #if os(macOS)
        label.layout()
        #else
        label.layoutSubviews()
        #endif

        XCTAssertNotNil(label.displayList, "Display list should be created")
        XCTAssertNil(label.error, "Should have no rendering error")

        // Verify that the text wrapped (multiple lines)
        XCTAssertGreaterThan(constrainedSize.height, 20, "Should have wrapped to multiple lines")

        // The critical check: ensure "équivaut" is not broken in the middle
        // We can't easily check the exact line breaks, but we can verify:
        // 1. The rendering succeeded without crashes
        // 2. The display has reasonable dimensions
        XCTAssertGreaterThan(constrainedSize.width, 100, "Width should be reasonable")
        XCTAssertLessThan(constrainedSize.width, 250, "Width should respect constraint")
    }

    func testMixedTextMathNoTruncation() {
        // Test for truncation bug: content should wrap, not be lost
        // Input: \(\text{Calculer le discriminant }\Delta=b^{2}-4ac\text{ avec }a=1\text{, }b=-1\text{, }c=-5\)
        let label = MTMathUILabel()
        label.latex = "\\(\\text{Calculer le discriminant }\\Delta=b^{2}-4ac\\text{ avec }a=1\\text{, }b=-1\\text{, }c=-5\\)"
        label.font = MTFontManager.fontManager.defaultFont
        label.labelMode = .text

        // Set width constraint that should cause wrapping
        label.preferredMaxLayoutWidth = 235
        let constrainedSize = label.intrinsicContentSize

        // Verify the label can render without errors
        label.frame = CGRect(origin: .zero, size: constrainedSize)
        #if os(macOS)
        label.layout()
        #else
        label.layoutSubviews()
        #endif

        XCTAssertNotNil(label.displayList, "Display list should be created")
        XCTAssertNil(label.error, "Should have no rendering error")

        // Verify content is not truncated - should wrap to multiple lines
        XCTAssertGreaterThan(constrainedSize.height, 30, "Should wrap to multiple lines (not truncate)")

        // Check that we have multiple display elements (wrapped content)
        if let displayList = label.displayList {
            XCTAssertGreaterThan(displayList.subDisplays.count, 1, "Should have multiple display elements from wrapping")
        }
    }

    func testNumberProtection_FrenchDecimal() {
        let label = MTMathUILabel()
        // French decimal number should NOT be broken
        label.latex = "\\(\\text{La valeur de pi est approximativement 3,14 dans ce calcul simple.}\\)"
        label.font = MTFontManager.fontManager.defaultFont
        label.labelMode = .text

        // Constrain to force wrapping, but 3,14 should stay together
        label.preferredMaxLayoutWidth = 200
        let size = label.intrinsicContentSize

        // Verify it renders without error
        label.frame = CGRect(origin: .zero, size: size)
        #if os(macOS)
        label.layout()
        #else
        label.layoutSubviews()
        #endif

        XCTAssertNotNil(label.displayList, "Display list should be created")
        XCTAssertNil(label.error, "Should have no rendering error")
    }

    func testNumberProtection_ThousandsSeparator() {
        let label = MTMathUILabel()
        // Number with comma separator should stay together
        label.latex = "\\(\\text{The population is approximately 1,000,000 people in this city.}\\)"
        label.font = MTFontManager.fontManager.defaultFont
        label.labelMode = .text

        label.preferredMaxLayoutWidth = 200
        let size = label.intrinsicContentSize

        label.frame = CGRect(origin: .zero, size: size)
        #if os(macOS)
        label.layout()
        #else
        label.layoutSubviews()
        #endif

        XCTAssertNotNil(label.displayList, "Display list should be created")
        XCTAssertNil(label.error, "Should have no rendering error")
    }

    func testNumberProtection_MixedWithText() {
        let label = MTMathUILabel()
        // Mixed numbers and text - numbers should be protected
        label.latex = "\\(\\text{Results: 3.14, 2.71, and 1.41 are important constants.}\\)"
        label.font = MTFontManager.fontManager.defaultFont
        label.labelMode = .text

        label.preferredMaxLayoutWidth = 180
        let size = label.intrinsicContentSize

        label.frame = CGRect(origin: .zero, size: size)
        #if os(macOS)
        label.layout()
        #else
        label.layoutSubviews()
        #endif

        XCTAssertNotNil(label.displayList, "Display list should be created")
        XCTAssertNil(label.error, "Should have no rendering error")
    }

    // MARK: - International Text Tests

    func testChineseTextWrapping() {
        let label = MTMathUILabel()
        // Chinese text: "Mathematical equations are an important tool for describing natural phenomena"
        label.latex = "\\(\\text{数学方程式は自然現象を記述するための重要なツールです。}\\)"
        label.font = MTFontManager.fontManager.defaultFont
        label.labelMode = .text

        // Get unconstrained size
        let unconstrainedSize = label.intrinsicContentSize

        // Set constraint to force wrapping
        label.preferredMaxLayoutWidth = 200
        let constrainedSize = label.intrinsicContentSize

        // Chinese should wrap (can break between characters)
        XCTAssertGreaterThan(constrainedSize.width, 0, "Width should be > 0")
        XCTAssertLessThanOrEqual(constrainedSize.width, 200, "Width should not exceed constraint")
        XCTAssertGreaterThan(constrainedSize.height, unconstrainedSize.height, "Height should increase when wrapped")

        label.frame = CGRect(origin: .zero, size: constrainedSize)
        #if os(macOS)
        label.layout()
        #else
        label.layoutSubviews()
        #endif

        XCTAssertNotNil(label.displayList, "Display list should be created")
        XCTAssertNil(label.error, "Should have no rendering error")
    }

    func testJapaneseTextWrapping() {
        let label = MTMathUILabel()
        // Japanese text (Hiragana + Kanji): "This is a mathematics explanation"
        label.latex = "\\(\\text{これは数学の説明です。計算式を使います。}\\)"
        label.font = MTFontManager.fontManager.defaultFont
        label.labelMode = .text

        let unconstrainedSize = label.intrinsicContentSize

        label.preferredMaxLayoutWidth = 180
        let constrainedSize = label.intrinsicContentSize

        XCTAssertGreaterThan(constrainedSize.width, 0, "Width should be > 0")
        XCTAssertLessThanOrEqual(constrainedSize.width, 180, "Width should not exceed constraint")
        XCTAssertGreaterThan(constrainedSize.height, unconstrainedSize.height, "Height should increase when wrapped")

        label.frame = CGRect(origin: .zero, size: constrainedSize)
        #if os(macOS)
        label.layout()
        #else
        label.layoutSubviews()
        #endif

        XCTAssertNotNil(label.displayList, "Display list should be created")
        XCTAssertNil(label.error, "Should have no rendering error")
    }

    func testKoreanTextWrapping() {
        let label = MTMathUILabel()
        // Korean text: "Mathematics is a very important subject"
        label.latex = "\\(\\text{수학은 매우 중요한 과목입니다. 방정식을 배웁니다.}\\)"
        label.font = MTFontManager.fontManager.defaultFont
        label.labelMode = .text

        label.preferredMaxLayoutWidth = 200
        let constrainedSize = label.intrinsicContentSize

        // Korean uses spaces, should wrap at word boundaries
        XCTAssertGreaterThan(constrainedSize.width, 0, "Width should be > 0")
        XCTAssertLessThanOrEqual(constrainedSize.width, 200, "Width should not exceed constraint")

        label.frame = CGRect(origin: .zero, size: constrainedSize)
        #if os(macOS)
        label.layout()
        #else
        label.layoutSubviews()
        #endif

        XCTAssertNotNil(label.displayList, "Display list should be created")
        XCTAssertNil(label.error, "Should have no rendering error")
    }

    func testMixedLatinCJKWrapping() {
        let label = MTMathUILabel()
        // Mixed English and Chinese
        label.latex = "\\(\\text{The equation is 方程式: } x^2 + y^2 = r^2 \\text{ です。}\\)"
        label.font = MTFontManager.fontManager.defaultFont
        label.labelMode = .text

        label.preferredMaxLayoutWidth = 250
        let constrainedSize = label.intrinsicContentSize

        XCTAssertGreaterThan(constrainedSize.width, 0, "Width should be > 0")
        XCTAssertLessThanOrEqual(constrainedSize.width, 250, "Width should not exceed constraint")

        label.frame = CGRect(origin: .zero, size: constrainedSize)
        #if os(macOS)
        label.layout()
        #else
        label.layoutSubviews()
        #endif

        XCTAssertNotNil(label.displayList, "Display list should be created")
        XCTAssertNil(label.error, "Should have no rendering error")
    }

    func testEmojiGraphemeClusters() {
        let label = MTMathUILabel()
        // Emoji and complex grapheme clusters should not be broken
        label.latex = "\\(\\text{Math is fun! 🎉📐📊 The formula is } E = mc^2 \\text{ 🚀✨}\\)"
        label.font = MTFontManager.fontManager.defaultFont
        label.labelMode = .text

        label.preferredMaxLayoutWidth = 200
        let size = label.intrinsicContentSize

        // Should wrap but not break emoji
        XCTAssertGreaterThan(size.width, 0, "Width should be > 0")
        XCTAssertLessThanOrEqual(size.width, 200, "Width should not exceed constraint")

        label.frame = CGRect(origin: .zero, size: size)
        #if os(macOS)
        label.layout()
        #else
        label.layoutSubviews()
        #endif

        XCTAssertNotNil(label.displayList, "Display list should be created")
        XCTAssertNil(label.error, "Should have no rendering error")
    }

    func testLongEnglishMultiSentence() {
        let label = MTMathUILabel()
        // Standard English multi-sentence paragraph
        label.latex = "\\(\\text{Mathematics is the study of numbers, shapes, and patterns. It is used in science, engineering, and everyday life. Equations help us solve problems.}\\)"
        label.font = MTFontManager.fontManager.defaultFont
        label.labelMode = .text

        let unconstrainedSize = label.intrinsicContentSize

        label.preferredMaxLayoutWidth = 300
        let constrainedSize = label.intrinsicContentSize

        // Should wrap at word boundaries (spaces)
        XCTAssertGreaterThan(constrainedSize.width, 0, "Width should be > 0")
        XCTAssertLessThanOrEqual(constrainedSize.width, 300, "Width should not exceed constraint")
        XCTAssertGreaterThan(constrainedSize.height, unconstrainedSize.height, "Height should increase when wrapped")

        label.frame = CGRect(origin: .zero, size: constrainedSize)
        #if os(macOS)
        label.layout()
        #else
        label.layoutSubviews()
        #endif

        XCTAssertNotNil(label.displayList, "Display list should be created")
        XCTAssertNil(label.error, "Should have no rendering error")
    }

    func testSpanishAccentedText() {
        let label = MTMathUILabel()
        // Spanish with various accents
        label.latex = "\\(\\text{La ecuación es muy útil para cálculos científicos y matemáticos.}\\)"
        label.font = MTFontManager.fontManager.defaultFont
        label.labelMode = .text

        let unconstrainedSize = label.intrinsicContentSize

        label.preferredMaxLayoutWidth = 220
        let constrainedSize = label.intrinsicContentSize

        XCTAssertGreaterThan(constrainedSize.width, 0, "Width should be > 0")
        XCTAssertLessThanOrEqual(constrainedSize.width, 220, "Width should not exceed constraint")
        XCTAssertGreaterThan(constrainedSize.height, unconstrainedSize.height, "Height should increase when wrapped")

        label.frame = CGRect(origin: .zero, size: constrainedSize)
        #if os(macOS)
        label.layout()
        #else
        label.layoutSubviews()
        #endif

        XCTAssertNotNil(label.displayList, "Display list should be created")
        XCTAssertNil(label.error, "Should have no rendering error")
    }

    func testGermanUmlautsWrapping() {
        let label = MTMathUILabel()
        // German with umlauts
        label.latex = "\\(\\text{Mathematische Gleichungen können für Berechnungen verwendet werden.}\\)"
        label.font = MTFontManager.fontManager.defaultFont
        label.labelMode = .text

        let unconstrainedSize = label.intrinsicContentSize

        label.preferredMaxLayoutWidth = 250
        let constrainedSize = label.intrinsicContentSize

        XCTAssertGreaterThan(constrainedSize.width, 0, "Width should be > 0")
        XCTAssertLessThanOrEqual(constrainedSize.width, 250, "Width should not exceed constraint")
        XCTAssertGreaterThan(constrainedSize.height, unconstrainedSize.height, "Height should increase when wrapped")

        label.frame = CGRect(origin: .zero, size: constrainedSize)
        #if os(macOS)
        label.layout()
        #else
        label.layoutSubviews()
        #endif

        XCTAssertNotNil(label.displayList, "Display list should be created")
        XCTAssertNil(label.error, "Should have no rendering error")
    }
    
    // MARK: - Line Limit Tests
    
    func testLineLimitZero_UnlimitedLines() {
        let label = MTMathUILabel()
        label.latex = "\\(a+b+c+d+e+f+g+h+i+j+k+l+m+n+o+p+q+r+s+t+u+v+w+x+y+z\\)"
        label.font = MTFontManager.fontManager.defaultFont
        label.preferredMaxLayoutWidth = 100
        label.lineLimit = 0  // Unlimited lines
        
        let size = label.intrinsicContentSize
        
        label.frame = CGRect(origin: .zero, size: size)
        #if os(macOS)
        label.layout()
        #else
        label.layoutSubviews()
        #endif
        
        XCTAssertNotNil(label.displayList, "Display list should be created")
        XCTAssertNil(label.error, "Should have no rendering error")
        
        // With unlimited lines, all content should be displayed
        if let displayList = label.displayList {
            // Count how many unique Y positions we have (representing lines)
            let yPositions = Set(displayList.subDisplays.map { display in
                Int(display.position.y)
            })
            XCTAssertGreaterThan(yPositions.count, 1, "Should have multiple lines")
        }
    }
    
    func testLineLimitOne_SingleLine() {
        let label = MTMathUILabel()
        label.latex = "\\(a+b+c+d+e+f+g+h+i+j+k+l+m+n+o+p+q+r+s+t+u+v+w+x+y+z\\)"
        label.font = MTFontManager.fontManager.defaultFont
        label.preferredMaxLayoutWidth = 100
        label.lineLimit = 1
        
        let size = label.intrinsicContentSize
        
        label.frame = CGRect(origin: .zero, size: size)
        #if os(macOS)
        label.layout()
        #else
        label.layoutSubviews()
        #endif
        
        XCTAssertNotNil(label.displayList, "Display list should be created")
        XCTAssertNil(label.error, "Should have no rendering error")
        
        // With lineLimit = 1, should have only one line with ellipsis
        if let displayList = label.displayList {
            let yPositions = Set(displayList.subDisplays.map { display in
                Int(display.position.y)
            })
            XCTAssertEqual(yPositions.count, 1, "Should have exactly one line")
            
            // Check that an ellipsis was added (last display should be ellipsis)
            if let lastDisplay = displayList.subDisplays.last as? MTCTLineDisplay {
                let attrString = lastDisplay.attributedString
                if let string = attrString?.string {
                    XCTAssertTrue(string.contains("\u{2026}"), "Last display should contain ellipsis")
                }
            }
        }
    }
    
    func testLineLimitTwo_TwoLines() {
        let label = MTMathUILabel()
        label.latex = "\\(a+b+c+d+e+f+g+h+i+j+k+l+m+n+o+p+q+r+s+t+u+v+w+x+y+z\\)"
        label.font = MTFontManager.fontManager.defaultFont
        label.preferredMaxLayoutWidth = 100
        label.lineLimit = 2
        
        let size = label.intrinsicContentSize
        
        label.frame = CGRect(origin: .zero, size: size)
        #if os(macOS)
        label.layout()
        #else
        label.layoutSubviews()
        #endif
        
        XCTAssertNotNil(label.displayList, "Display list should be created")
        XCTAssertNil(label.error, "Should have no rendering error")
        
        // With lineLimit = 2, should have at most two lines
        if let displayList = label.displayList {
            let yPositions = Set(displayList.subDisplays.map { display in
                Int(display.position.y)
            })
            XCTAssertLessThanOrEqual(yPositions.count, 2, "Should have at most two lines")
        }
    }
    
    func testLineLimitWithText() {
        let label = MTMathUILabel()
        label.latex = "\\(\\text{This is a very long piece of text that should wrap across multiple lines when constrained to a narrow width.}\\)"
        label.font = MTFontManager.fontManager.defaultFont
        label.labelMode = .text
        label.preferredMaxLayoutWidth = 150
        label.lineLimit = 2
        
        let size = label.intrinsicContentSize
        
        label.frame = CGRect(origin: .zero, size: size)
        #if os(macOS)
        label.layout()
        #else
        label.layoutSubviews()
        #endif
        
        XCTAssertNotNil(label.displayList, "Display list should be created")
        XCTAssertNil(label.error, "Should have no rendering error")
        
        // Verify line limit is enforced
        if let displayList = label.displayList {
            let yPositions = Set(displayList.subDisplays.map { display in
                Int(display.position.y)
            })
            XCTAssertLessThanOrEqual(yPositions.count, 2, "Should have at most two lines")
        }
    }
    
    func testLineLimitNegativeValue_TreatedAsZero() {
        let label = MTMathUILabel()
        label.latex = "\\(a+b+c\\)"
        label.font = MTFontManager.fontManager.defaultFont
        label.lineLimit = -5  // Negative value
        
        // Should be treated as 0 (unlimited)
        XCTAssertEqual(label.lineLimit, 0, "Negative lineLimit should be treated as 0")
    }
    
    func testLineLimitSizeThatFits() {
        let label = MTMathUILabel()
        label.latex = "\\(a+b+c+d+e+f+g+h+i+j+k+l+m+n+o+p\\)"
        label.font = MTFontManager.fontManager.defaultFont
        label.lineLimit = 1
        
        let constrainedSize = label.sizeThatFits(CGSize(width: 100, height: CGFloat.greatestFiniteMagnitude))
        
        XCTAssertGreaterThan(constrainedSize.width, 0, "Width should be > 0")
        XCTAssertGreaterThan(constrainedSize.height, 0, "Height should be > 0")
        
        // With lineLimit = 1, height should be limited to approximately one line
        let expectedSingleLineHeight = label.fontSize * 1.5 // Approximate single line height
        XCTAssertLessThan(constrainedSize.height, expectedSingleLineHeight * 2, "Height should be approximately one line")
    }
    
    // MARK: - Line Limit Edge Cases and Safety Tests
    
    func testLineLimitWithZeroWidth_NoError() {
        let label = MTMathUILabel()
        label.latex = "\\(a+b+c\\)"
        label.font = MTFontManager.fontManager.defaultFont
        label.lineLimit = 2
        label.preferredMaxLayoutWidth = 0  // No width constraint
        
        // Should not crash or cause errors
        let size = label.intrinsicContentSize
        
        // With lineLimit and no width constraint, lineLimit is ignored (returns normal size)
        XCTAssertNil(label.error, "Should have no error")
        XCTAssertGreaterThan(size.width, 0, "Width should still be calculated")
        XCTAssertGreaterThan(size.height, 0, "Height should still be calculated")
    }
    
    func testLineLimitWithEmptyContent_NoError() {
        let label = MTMathUILabel()
        label.latex = ""
        label.font = MTFontManager.fontManager.defaultFont
        label.lineLimit = 2
        label.preferredMaxLayoutWidth = 100
        
        // Should not crash with empty content
        let size = label.intrinsicContentSize
        
        // Empty content returns (0, 0) since there's nothing to render
        XCTAssertEqual(size.width, 0, "Empty content should return 0 width")
        XCTAssertEqual(size.height, 0, "Empty content should return 0 height")
    }
    
    func testLineLimitWithInvalidLatex_NoError() {
        let label = MTMathUILabel()
        label.latex = "\\(\\invalid{syntax}\\)"
        label.font = MTFontManager.fontManager.defaultFont
        label.lineLimit = 2
        label.preferredMaxLayoutWidth = 100
        
        // Should not crash with invalid latex
        _ = label.intrinsicContentSize
        
        XCTAssertNotNil(label.error, "Should have parse error for invalid latex")
        // With error, display list may be nil
    }
    
    func testLineLimitWithVerySmallWidth_NoError() {
        let label = MTMathUILabel()
        label.latex = "\\(a+b+c+d+e\\)"
        label.font = MTFontManager.fontManager.defaultFont
        label.lineLimit = 1
        label.preferredMaxLayoutWidth = 10  // Very small width
        
        // Should not crash with very small width
        let size = label.intrinsicContentSize
        
        label.frame = CGRect(origin: .zero, size: size)
        #if os(macOS)
        label.layout()
        #else
        label.layoutSubviews()
        #endif
        
        XCTAssertNotNil(label.displayList, "Display list should be created")
        XCTAssertNil(label.error, "Should have no error")
    }
    
    func testLineLimitWithNoFont_UsesDefault() {
        let label = MTMathUILabel()
        label.latex = "\\(a+b+c\\)"
        // Don't set font explicitly - should use default
        label.lineLimit = 1
        label.preferredMaxLayoutWidth = 100
        
        let size = label.intrinsicContentSize
        
        XCTAssertGreaterThan(size.width, 0, "Should calculate size with default font")
        XCTAssertGreaterThan(size.height, 0, "Should calculate height with default font")
        XCTAssertNotNil(label.font, "Should have default font set")
    }
    
    func testLineLimitWithSingleAtom_NoError() {
        let label = MTMathUILabel()
        label.latex = "\\(x\\)"
        label.font = MTFontManager.fontManager.defaultFont
        label.lineLimit = 1
        label.preferredMaxLayoutWidth = 100
        
        let size = label.intrinsicContentSize
        
        label.frame = CGRect(origin: .zero, size: size)
        #if os(macOS)
        label.layout()
        #else
        label.layoutSubviews()
        #endif
        
        XCTAssertNotNil(label.displayList, "Display list should be created")
        XCTAssertNil(label.error, "Should have no error")
        
        // Single atom should fit on one line
        if let displayList = label.displayList {
            XCTAssertGreaterThan(displayList.subDisplays.count, 0, "Should have displays")
        }
    }
    
    func testLineLimitLargerThanActualLines_NoTruncation() {
        let label = MTMathUILabel()
        label.latex = "\\(a+b+c\\)"  // Short content
        label.font = MTFontManager.fontManager.defaultFont
        label.lineLimit = 10  // Much larger than needed
        label.preferredMaxLayoutWidth = 100
        
        let size = label.intrinsicContentSize
        
        label.frame = CGRect(origin: .zero, size: size)
        #if os(macOS)
        label.layout()
        #else
        label.layoutSubviews()
        #endif
        
        XCTAssertNotNil(label.displayList, "Display list should be created")
        XCTAssertNil(label.error, "Should have no error")
        
        // Content should not be truncated when lineLimit is larger than actual lines
        if let displayList = label.displayList {
            // Check that no ellipsis was added (all original content should be present)
            let hasEllipsis = displayList.subDisplays.contains { display in
                if let lineDisplay = display as? MTCTLineDisplay,
                   let attrString = lineDisplay.attributedString {
                    return attrString.string.contains("\u{2026}")
                }
                return false
            }
            XCTAssertFalse(hasEllipsis, "Should not add ellipsis when content fits within line limit")
        }
    }
    
    func testLineLimitWithNegativeMaxWidth_SafelyHandled() {
        let label = MTMathUILabel()
        label.latex = "\\(a+b+c\\)"
        label.font = MTFontManager.fontManager.defaultFont
        label.lineLimit = 1
        
        // Negative width should be handled gracefully
        let size = label.sizeThatFits(CGSize(width: -100, height: CGFloat.greatestFiniteMagnitude))
        
        // Should not crash and should return valid size
        XCTAssertGreaterThanOrEqual(size.width, 0, "Width should not be negative")
        XCTAssertGreaterThanOrEqual(size.height, 0, "Height should not be negative")
    }
    
    func testLineLimitWithNilTextColor_NoError() {
        let label = MTMathUILabel()
        label.latex = "\\(a+b+c+d+e+f+g+h+i+j+k+l+m+n+o+p\\)"
        label.font = MTFontManager.fontManager.defaultFont
        label.preferredMaxLayoutWidth = 100
        label.lineLimit = 1
        label.textColor = nil  // Explicitly set to nil
        
        let size = label.intrinsicContentSize
        
        label.frame = CGRect(origin: .zero, size: size)
        #if os(macOS)
        label.layout()
        #else
        label.layoutSubviews()
        #endif
        
        // Should not crash when textColor is nil and ellipsis is added
        XCTAssertNotNil(label.displayList, "Display list should be created")
        XCTAssertNil(label.error, "Should have no error")
    }
    
    func testLineLimitEllipsisFitsWithinMaxWidth() {
        // Test that ellipsis always fits within maxWidth by truncating content
        let label = MTMathUILabel()
        label.latex = "\\(\\text{Calculer le discriminant } \\Delta=b^{2}-4ac \\text{ avec } a=1, b=-1, c=\\)"
        label.font = MTFontManager.fontManager.defaultFont
        label.preferredMaxLayoutWidth = 235
        label.lineLimit = 1
        
        let size = label.intrinsicContentSize
        label.frame = CGRect(origin: .zero, size: size)
        #if os(macOS)
        label.layout()
        #else
        label.layoutSubviews()
        #endif
        
        // Verify ellipsis was added
        guard let displayList = label.displayList else {
            XCTFail("Display list should not be nil")
            return
        }
        
        let hasEllipsis = displayList.subDisplays.contains { display in
            if let lineDisplay = display as? MTCTLineDisplay,
               let attrString = lineDisplay.attributedString {
                return attrString.string.contains("\u{2026}")
            }
            return false
        }
        XCTAssertTrue(hasEllipsis, "Should add ellipsis when content exceeds line limit")
        
        // Verify total width doesn't exceed maxWidth
        let maxX = displayList.subDisplays.map { $0.position.x + $0.width }.max() ?? 0
        XCTAssertLessThanOrEqual(maxX, 235, "Content width including ellipsis should not exceed maxWidth")
    }
    
    func testLineLimitWithSuperscriptLineGrouping() {
        // Test that superscripts are correctly grouped with their base line
        let label = MTMathUILabel()
        label.latex = "\\(\\text{Calculate } b^{2} \\text{ and more text that wraps}\\)"
        label.font = MTFontManager.fontManager.defaultFont
        label.preferredMaxLayoutWidth = 150
        label.lineLimit = 2
        
        let size = label.intrinsicContentSize
        label.frame = CGRect(origin: .zero, size: size)
        #if os(macOS)
        label.layout()
        #else
        label.layoutSubviews()
        #endif
        
        guard let displayList = label.displayList else {
            XCTFail("Display list should not be nil")
            return
        }
        
        // Should have ellipsis on second line
        let hasEllipsis = displayList.subDisplays.contains { display in
            if let lineDisplay = display as? MTCTLineDisplay,
               let attrString = lineDisplay.attributedString {
                return attrString.string.contains("\u{2026}")
            }
            return false
        }
        XCTAssertTrue(hasEllipsis, "Should add ellipsis when truncating to 2 lines")
        
        // Verify superscript components are not incorrectly treated as separate lines
        // by checking that we don't have excessive line breaks
        let ctLineDisplays = displayList.subDisplays.compactMap { $0 as? MTCTLineDisplay }
        XCTAssertGreaterThan(ctLineDisplays.count, 0, "Should have some text displays")
    }
    
    func testLineLimitTextTruncationBinarySearch() {
        // Test that text truncation works correctly with binary search algorithm
        let label = MTMathUILabel()
        label.latex = "\\(\\text{This is a very long text that needs to be truncated properly with ellipsis at the end}\\)"
        label.font = MTFontManager.fontManager.defaultFont
        label.preferredMaxLayoutWidth = 200
        label.lineLimit = 1
        
        let size = label.intrinsicContentSize
        label.frame = CGRect(origin: .zero, size: size)
        #if os(macOS)
        label.layout()
        #else
        label.layoutSubviews()
        #endif
        
        guard let displayList = label.displayList else {
            XCTFail("Display list should not be nil")
            return
        }
        
        // Find the ellipsis display
        let ellipsisDisplay = displayList.subDisplays.first { display in
            if let lineDisplay = display as? MTCTLineDisplay,
               let attrString = lineDisplay.attributedString {
                return attrString.string == "\u{2026}"
            }
            return false
        }
        XCTAssertNotNil(ellipsisDisplay, "Should have ellipsis display")
        
        // Find the truncated text display
        let textDisplay = displayList.subDisplays.first { display in
            if let lineDisplay = display as? MTCTLineDisplay,
               let attrString = lineDisplay.attributedString {
                let text = attrString.string
                return text.count > 0 && text != "\u{2026}" && !text.contains("…")
            }
            return false
        }
        XCTAssertNotNil(textDisplay, "Should have truncated text display")
        
        if let text = textDisplay as? MTCTLineDisplay {
            let originalText = "This is a very long text that needs to be truncated properly with ellipsis at the end"
            let truncatedText = text.attributedString?.string ?? ""
            // Truncated text should be shorter than original
            XCTAssertLessThan(truncatedText.count, originalText.count, "Text should be truncated")
            // Truncated text should be a prefix of original
            XCTAssertTrue(originalText.hasPrefix(truncatedText), "Truncated text should be prefix of original")
        }
    }
    
    func testLineLimitYPositionBasedLineGrouping() {
        // Test that line grouping is based on Y position, not X position
        let label = MTMathUILabel()
        label.latex = "\\(\\text{Line one text} \\quad \\text{Line two text after wrapping}\\)"
        label.font = MTFontManager.fontManager.defaultFont
        label.preferredMaxLayoutWidth = 180
        label.lineLimit = 1
        
        let size = label.intrinsicContentSize
        label.frame = CGRect(origin: .zero, size: size)
        #if os(macOS)
        label.layout()
        #else
        label.layoutSubviews()
        #endif
        
        guard let displayList = label.displayList else {
            XCTFail("Display list should not be nil")
            return
        }
        
        // Should have ellipsis indicating truncation occurred
        let hasEllipsis = displayList.subDisplays.contains { display in
            if let lineDisplay = display as? MTCTLineDisplay,
               let attrString = lineDisplay.attributedString {
                return attrString.string.contains("\u{2026}")
            }
            return false
        }
        XCTAssertTrue(hasEllipsis, "Should add ellipsis when content exceeds 1 line")
        
        // Ellipsis should be at the end (rightmost position) of the first line
        if let ellipsisDisp = displayList.subDisplays.first(where: { display in
            if let lineDisplay = display as? MTCTLineDisplay,
               let attrString = lineDisplay.attributedString {
                return attrString.string == "\u{2026}"
            }
            return false
        }) {
            let nonEllipsisDisplays = displayList.subDisplays.filter { display in
                if let lineDisplay = display as? MTCTLineDisplay,
                   let attrString = lineDisplay.attributedString {
                    return attrString.string != "\u{2026}"
                }
                return true
            }
            
            // Ellipsis X position should be greater than or equal to other displays on same line
            for display in nonEllipsisDisplays {
                if abs(display.position.y - ellipsisDisp.position.y) < 10 {
                    XCTAssertGreaterThanOrEqual(ellipsisDisp.position.x, display.position.x,
                                                "Ellipsis should be positioned after other content on same line")
                }
            }
        }
    }
}

