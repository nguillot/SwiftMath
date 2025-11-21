//
//  MTRenderContext.swift
//  SwiftMath
//
//  Created on 2025-11-20.
//  Architecture refactoring - Step 2: Extract rendering logic
//

import Foundation
import CoreGraphics
import CoreText

// MARK: - Render Context

/// Context information needed for rendering mathematical atoms.
/// Provides immutable configuration and current state for renderers.
struct MTRenderContext {
    /// The font to use for rendering
    let font: MTFont
    
    /// The styled font (with size adjusted for current style)
    let styleFont: MTFont
    
    /// The current line style (display, text, script, scriptscript)
    let style: MTLineStyle
    
    /// Whether to use cramped spacing
    let cramped: Bool
    
    /// Whether to add inter-element spacing
    let spaced: Bool
    
    /// Maximum width for line breaking (0 = no limit)
    let maxWidth: CGFloat
    
    /// Current rendering position
    let position: CGPoint
    
    /// Creates a render context with the given parameters
    init(font: MTFont, styleFont: MTFont, style: MTLineStyle, cramped: Bool, spaced: Bool, maxWidth: CGFloat, position: CGPoint = .zero) {
        self.font = font
        self.styleFont = styleFont
        self.style = style
        self.cramped = cramped
        self.spaced = spaced
        self.maxWidth = maxWidth
        self.position = position
    }
    
    /// Creates a modified context with a new position
    func with(position: CGPoint) -> MTRenderContext {
        return MTRenderContext(
            font: font,
            styleFont: styleFont,
            style: style,
            cramped: cramped,
            spaced: spaced,
            maxWidth: maxWidth,
            position: position
        )
    }
    
    /// Creates a modified context with a new style
    func with(style: MTLineStyle) -> MTRenderContext {
        let newStyleFont = font.copy(withSize: MTTypesetter.getStyleSize(style, font: font))
        return MTRenderContext(
            font: font,
            styleFont: newStyleFont,
            style: style,
            cramped: cramped,
            spaced: spaced,
            maxWidth: maxWidth,
            position: position
        )
    }
    
    /// Creates a modified context with new cramped setting
    func with(cramped: Bool) -> MTRenderContext {
        return MTRenderContext(
            font: font,
            styleFont: styleFont,
            style: style,
            cramped: cramped,
            spaced: spaced,
            maxWidth: maxWidth,
            position: position
        )
    }
}

// MARK: - Atom Renderer Protocol

/// Protocol for rendering specific types of mathematical atoms.
/// Each renderer is responsible for a specific atom type (fractions, radicals, etc.)
protocol MTAtomRenderer {
    /// Renders the given atom in the provided context
    /// - Parameters:
    ///   - atom: The atom to render
    ///   - context: The rendering context
    ///   - typesetter: The typesetter instance (for accessing helper methods like glyph finding)
    /// - Returns: The display for the rendered atom, or nil if rendering failed
    func render(_ atom: MTMathAtom, context: MTRenderContext, typesetter: MTTypesetter) -> MTDisplay?
    
    /// The atom types this renderer can handle
    var supportedTypes: Set<MTMathAtomType> { get }
}

// MARK: - Helper Extensions

extension MTRenderContext {
    /// Gets the math table from the style font
    var mathTable: MTFontMathTable? {
        return styleFont.mathTable
    }
    
    /// Creates a child context for nested rendering (e.g., fraction numerator)
    func childContext(style: MTLineStyle, cramped: Bool) -> MTRenderContext {
        let childStyleFont = font.copy(withSize: MTTypesetter.getStyleSize(style, font: font))
        return MTRenderContext(
            font: font,
            styleFont: childStyleFont,
            style: style,
            cramped: cramped,
            spaced: spaced,
            maxWidth: maxWidth,
            position: .zero  // Child contexts start at origin
        )
    }
}
