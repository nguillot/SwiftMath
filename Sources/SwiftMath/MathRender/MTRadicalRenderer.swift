//
//  MTRadicalRenderer.swift
//  SwiftMath
//
//  Created on 2025-11-20.
//  Architecture refactoring - Step 2: Extract radical rendering logic
//

import Foundation
import CoreGraphics
import CoreText

/// Renderer for mathematical radicals (square roots, nth roots).
/// Implements TeX's radical rendering algorithm from Appendix G, Rule 11.
class MTRadicalRenderer: MTAtomRenderer {
    
    var supportedTypes: Set<MTMathAtomType> {
        return [.radical]
    }
    
    // MARK: - Main Rendering
    
    func render(_ atom: MTMathAtom, context: MTRenderContext, typesetter: MTTypesetter) -> MTDisplay? {
        guard let radical = atom as? MTRadical else {
            return nil
        }
        
        // Create the radical display
        guard let radicalDisplay = makeRadical(
            radical.radicand,
            range: radical.indexRange,
            context: context,
            typesetter: typesetter
        ) else {
            return nil
        }
        
        // Add degree if present (e.g., cube root)
        if let degree = radical.degree {
            let degreeDisplay = MTTypesetter.createLineForMathList(
                degree,
                font: context.font,
                style: .scriptOfScript,
                cramped: false,
                spaced: context.spaced,
                maxWidth: context.maxWidth
            )
            radicalDisplay.setDegree(degreeDisplay, fontMetrics: context.mathTable)
        }
        
        return radicalDisplay
    }
    
    // MARK: - Radical Construction
    
    /// Creates the display for a radical (square root or nth root).
    /// Implements TeX's algorithm for positioning the radical sign and radicand.
    private func makeRadical(
        _ radicand: MTMathList?,
        range: NSRange,
        context: MTRenderContext,
        typesetter: MTTypesetter
    ) -> MTRadicalDisplay? {
        // Render the radicand (the content under the radical)
        guard let innerDisplay = MTTypesetter.createLineForMathList(
            radicand,
            font: context.font,
            style: context.style,
            cramped: true,  // Radicands are always cramped
            spaced: context.spaced,
            maxWidth: context.maxWidth
        ) else {
            return nil
        }
        
        // Calculate clearance and radical height
        var clearance = radicalVerticalGap(context: context)
        guard let mathTable = context.mathTable else { return nil }
        let radicalRuleThickness = mathTable.radicalRuleThickness
        let radicalHeight = innerDisplay.ascent + innerDisplay.descent + clearance + radicalRuleThickness
        
        // Get the radical glyph (√ symbol) with appropriate height
        guard let glyph = getRadicalGlyphWithHeight(
            radicalHeight,
            context: context,
            typesetter: typesetter
        ) else {
            return nil
        }
        
        // Adjust clearance to center the radicand inside the radical sign
        // Note: This is a departure from LaTeX conventions
        // LaTeX assumes glyphAscent == thickness, but OpenType Math doesn't
        let delta = (glyph.descent + glyph.ascent) - (innerDisplay.ascent + innerDisplay.descent + clearance + radicalRuleThickness)
        if delta > 0 {
            clearance += delta / 2  // Increase clearance to center
        }
        
        // Calculate positioning
        // The radical glyph needs to be shifted up to align with the baseline of inner
        let radicalAscent = radicalRuleThickness + clearance + innerDisplay.ascent
        let shiftUp = radicalAscent - glyph.ascent
        if let glyphDisplay = glyph as? MTGlyphDisplay {
            glyphDisplay.shiftDown = -shiftUp
        } else if let glyphConstDisplay = glyph as? MTGlyphConstructionDisplay {
            glyphConstDisplay.shiftDown = -shiftUp
        }
        
        // Create the radical display
        let radical = MTRadicalDisplay(
            withRadicand: innerDisplay,
            glyph: glyph,
            position: context.position,
            range: range
        )
        
        radical.ascent = radicalAscent + mathTable.radicalExtraAscender
        radical.topKern = mathTable.radicalExtraAscender
        radical.lineThickness = radicalRuleThickness
        
        // Note: Until we have radical construction from parts, it's possible that
        // glyphAscent+glyphDescent < requested height, so use max with innerDisplay descent
        radical.descent = max(glyph.ascent + glyph.descent - radicalAscent, innerDisplay.descent)
        radical.width = glyph.width + innerDisplay.width
        
        return radical
    }
    
    // MARK: - Glyph Construction
    
    /// Gets the radical glyph (√) with the specified height.
    /// If no single glyph is large enough, constructs one from parts.
    private func getRadicalGlyphWithHeight(
        _ radicalHeight: CGFloat,
        context: MTRenderContext,
        typesetter: MTTypesetter
    ) -> MTDisplay? {
        var glyphAscent: CGFloat = 0
        var glyphDescent: CGFloat = 0
        var glyphWidth: CGFloat = 0
        
        // Find the glyph for the radical symbol (√)
        let radicalGlyph = typesetter.findGlyphForCharacterAtIndex(
            "\u{221A}".startIndex,
            inString: "\u{221A}"
        )
        
        // Find a variant that's tall enough
        let glyph = typesetter.findGlyph(
            radicalGlyph,
            withHeight: radicalHeight,
            glyphAscent: &glyphAscent,
            glyphDescent: &glyphDescent,
            glyphWidth: &glyphWidth
        )
        
        var glyphDisplay: MTDisplay?
        
        // If no variant is tall enough, construct from parts
        if glyphAscent + glyphDescent < radicalHeight {
            glyphDisplay = typesetter.constructGlyph(radicalGlyph, withHeight: radicalHeight)
        }
        
        // Fall back to the tallest variant if construction fails
        if glyphDisplay == nil {
            let display = MTGlyphDisplay(
                withGlpyh: glyph,
                range: NSMakeRange(NSNotFound, 0),
                font: context.styleFont
            )
            display.ascent = glyphAscent
            display.descent = glyphDescent
            display.width = glyphWidth
            glyphDisplay = display
        }
        
        return glyphDisplay
    }
    
    // MARK: - Spacing Calculations
    
    /// Calculates the vertical gap between the radicand and the radical bar.
    /// Uses different values for display vs. inline styles.
    private func radicalVerticalGap(context: MTRenderContext) -> CGFloat {
        guard let mathTable = context.mathTable else { return 0 }
        
        if context.style == .display {
            return mathTable.radicalDisplayStyleVerticalGap
        } else {
            return mathTable.radicalVerticalGap
        }
    }
}
