//
//  MTFractionRenderer.swift
//  SwiftMath
//
//  Created on 2025-11-20.
//  Architecture refactoring - Step 2: Extract fraction rendering logic
//

import Foundation
import CoreGraphics

/// Renderer for mathematical fractions.
/// Handles both regular fractions (with horizontal bar) and stacked expressions (without bar).
/// Implements TeX's fraction rendering algorithm from Appendix G, Rule 15.
class MTFractionRenderer: MTAtomRenderer {
    
    var supportedTypes: Set<MTMathAtomType> {
        return [.fraction]
    }
    
    // MARK: - Main Rendering
    
    func render(_ atom: MTMathAtom, context: MTRenderContext, typesetter: MTTypesetter) -> MTDisplay? {
        guard let fraction = atom as? MTFraction else {
            return nil
        }
        return makeFraction(fraction, context: context, typesetter: typesetter)
    }
    
    // MARK: - Fraction Layout
    
    /// Creates the display for a fraction.
    /// Implements TeX's generalized fraction algorithm (Rule 15).
    private func makeFraction(_ frac: MTFraction, context: MTRenderContext, typesetter: MTTypesetter) -> MTDisplay? {
        // Determine styles for numerator and denominator
        let (numeratorStyle, denominatorStyle) = determineFractionStyles(frac, context: context)
        
        // Create child contexts for numerator and denominator
        let numeratorContext = context.childContext(style: numeratorStyle, cramped: false)
        let denominatorContext = context.childContext(style: denominatorStyle, cramped: true)
        
        // Render numerator and denominator
        guard let numeratorDisplay = MTTypesetter.createLineForMathList(
            frac.numerator,
            font: context.font,
            style: numeratorStyle,
            cramped: false,
            spaced: context.spaced,
            maxWidth: context.maxWidth
        ) else {
            return nil
        }
        
        guard let denominatorDisplay = MTTypesetter.createLineForMathList(
            frac.denominator,
            font: context.font,
            style: denominatorStyle,
            cramped: true,
            spaced: context.spaced,
            maxWidth: context.maxWidth
        ) else {
            return nil
        }
        
        // Calculate positioning
        let barLocation = context.styleFont.mathTable?.axisHeight ?? 0
        let barThickness = frac.hasRule ? (context.styleFont.mathTable?.fractionRuleThickness ?? 0) : 0
        
        var numeratorShiftUp = self.numeratorShiftUp(hasRule: frac.hasRule, context: context)
        var denominatorShiftDown = self.denominatorShiftDown(hasRule: frac.hasRule, context: context)
        
        // Apply gap constraints
        if frac.hasRule {
            // Ensure minimum gap between numerator and fraction bar
            let distanceFromNumeratorToBar = (numeratorShiftUp - numeratorDisplay.descent) - (barLocation + barThickness / 2)
            let minNumeratorGap = self.numeratorGapMin(context: context)
            if distanceFromNumeratorToBar < minNumeratorGap {
                numeratorShiftUp += (minNumeratorGap - distanceFromNumeratorToBar)
            }
            
            // Ensure minimum gap between denominator and fraction bar
            let distanceFromDenominatorToBar = (barLocation - barThickness / 2) - (denominatorDisplay.ascent - denominatorShiftDown)
            let minDenominatorGap = self.denominatorGapMin(context: context)
            if distanceFromDenominatorToBar < minDenominatorGap {
                denominatorShiftDown += (minDenominatorGap - distanceFromDenominatorToBar)
            }
        } else {
            // For stacked expressions (no bar), ensure minimum clearance
            let clearance = (numeratorShiftUp - numeratorDisplay.descent) - (denominatorDisplay.ascent - denominatorShiftDown)
            let minGap = self.stackGapMin(context: context)
            if clearance < minGap {
                numeratorShiftUp += (minGap - clearance) / 2
                denominatorShiftDown += (minGap - clearance) / 2
            }
        }
        
        // Create the fraction display
        let display = MTFractionDisplay(
            withNumerator: numeratorDisplay,
            denominator: denominatorDisplay,
            position: context.position,
            range: frac.indexRange
        )
        
        display.numeratorUp = numeratorShiftUp
        display.denominatorDown = denominatorShiftDown
        display.lineThickness = barThickness
        display.linePosition = barLocation
        
        // Add delimiters if specified
        if frac.leftDelimiter.isEmpty && frac.rightDelimiter.isEmpty {
            return display
        } else {
            return addDelimitersToFractionDisplay(display, fraction: frac, context: context, typesetter: typesetter)
        }
    }
    
    // MARK: - Delimiter Handling
    
    /// Adds left and/or right delimiters around a fraction display.
    private func addDelimitersToFractionDisplay(
        _ display: MTFractionDisplay,
        fraction: MTFraction,
        context: MTRenderContext,
        typesetter: MTTypesetter
    ) -> MTDisplay? {
        assert(!fraction.leftDelimiter.isEmpty || !fraction.rightDelimiter.isEmpty,
               "Fraction should have delimiters to call this function")
        
        var innerElements = [MTDisplay]()
        let glyphHeight = fractionDelimiterHeight(context: context)
        var position = CGPoint.zero
        
        // Add left delimiter
        if !fraction.leftDelimiter.isEmpty {
            if let leftGlyph = typesetter.findGlyphForBoundary(fraction.leftDelimiter, withHeight: glyphHeight) {
                leftGlyph.position = position
                position.x += leftGlyph.width
                innerElements.append(leftGlyph)
            }
        }
        
        // Add fraction display
        display.position = position
        position.x += display.width
        innerElements.append(display)
        
        // Add right delimiter
        if !fraction.rightDelimiter.isEmpty {
            if let rightGlyph = typesetter.findGlyphForBoundary(fraction.rightDelimiter, withHeight: glyphHeight) {
                rightGlyph.position = position
                position.x += rightGlyph.width
                innerElements.append(rightGlyph)
            }
        }
        
        let innerDisplay = MTMathListDisplay(withDisplays: innerElements, range: fraction.indexRange)
        innerDisplay.position = context.position
        return innerDisplay
    }
    
    // MARK: - Style Determination
    
    /// Determines the appropriate styles for numerator and denominator.
    private func determineFractionStyles(
        _ frac: MTFraction,
        context: MTRenderContext
    ) -> (numerator: MTLineStyle, denominator: MTLineStyle) {
        if frac.isContinuedFraction {
            // Continued fractions always use display style
            return (.display, .display)
        } else {
            // Regular fractions: keep the same style level instead of incrementing
            // This ensures fraction content has the same font size as surrounding text
            let fractionStyle = context.style
            return (fractionStyle, fractionStyle)
        }
    }
    
    // MARK: - Positioning Calculations
    
    /// Calculates how far up the numerator should be shifted.
    /// Based on TeX's algorithm and font metrics.
    private func numeratorShiftUp(hasRule: Bool, context: MTRenderContext) -> CGFloat {
        guard let mathTable = context.mathTable else { return 0 }
        
        if hasRule {
            if context.style == .display {
                return mathTable.fractionNumeratorDisplayStyleShiftUp
            } else {
                return mathTable.fractionNumeratorShiftUp
            }
        } else {
            // Stacked expression (no rule)
            if context.style == .display {
                return mathTable.stackTopDisplayStyleShiftUp
            } else {
                return mathTable.stackTopShiftUp
            }
        }
    }
    
    /// Calculates how far down the denominator should be shifted.
    private func denominatorShiftDown(hasRule: Bool, context: MTRenderContext) -> CGFloat {
        guard let mathTable = context.mathTable else { return 0 }
        
        if hasRule {
            if context.style == .display {
                return mathTable.fractionDenominatorDisplayStyleShiftDown
            } else {
                return mathTable.fractionDenominatorShiftDown
            }
        } else {
            // Stacked expression (no rule)
            if context.style == .display {
                return mathTable.stackBottomDisplayStyleShiftDown
            } else {
                return mathTable.stackBottomShiftDown
            }
        }
    }
    
    /// Minimum gap between numerator and fraction bar.
    private func numeratorGapMin(context: MTRenderContext) -> CGFloat {
        guard let mathTable = context.mathTable else { return 0 }
        
        if context.style == .display {
            return mathTable.fractionNumeratorDisplayStyleGapMin
        } else {
            return mathTable.fractionNumeratorGapMin
        }
    }
    
    /// Minimum gap between denominator and fraction bar.
    private func denominatorGapMin(context: MTRenderContext) -> CGFloat {
        guard let mathTable = context.mathTable else { return 0 }
        
        if context.style == .display {
            return mathTable.fractionDenominatorDisplayStyleGapMin
        } else {
            return mathTable.fractionDenominatorGapMin
        }
    }
    
    /// Minimum gap between numerator and denominator for stacked expressions (no rule).
    private func stackGapMin(context: MTRenderContext) -> CGFloat {
        guard let mathTable = context.mathTable else { return 0 }
        
        if context.style == .display {
            return mathTable.stackDisplayStyleGapMin
        } else {
            return mathTable.stackGapMin
        }
    }
    
    /// Height for fraction delimiters.
    private func fractionDelimiterHeight(context: MTRenderContext) -> CGFloat {
        guard let mathTable = context.mathTable else { return 0 }
        
        if context.style == .display {
            return mathTable.fractionDelimiterDisplayStyleSize
        } else {
            return mathTable.fractionDelimiterSize
        }
    }
}
