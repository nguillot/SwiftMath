import Foundation
import CoreGraphics

/// Renderer for superscripts and subscripts (TeX Rule 18)
///
/// Implements TeX's algorithm for positioning superscripts and subscripts,
/// handling both individual scripts and combined subscript/superscript pairs.
///
/// Reference: The TeXbook, Appendix G, Rule 18
class MTScriptRenderer: MTAtomRenderer {
    
    var supportedTypes: Set<MTMathAtomType> {
        return []  // Scripts are modifiers, not standalone atom types
    }
    
    func render(_ atom: MTMathAtom, context: MTRenderContext, typesetter: MTTypesetter) -> MTDisplay? {
        // Scripts are handled as modifiers to existing displays, not as standalone renders
        // This method is not used - use makeScripts() directly
        return nil
    }
    
    /// Creates and positions subscript and/or superscript displays for an atom
    ///
    /// - Parameters:
    ///   - atom: The atom with subscript/superscript properties
    ///   - display: The display for the base atom
    ///   - index: The index of the element getting scripts
    ///   - delta: Italic correction for superscript positioning
    ///   - context: Rendering context with font and style
    ///   - typesetter: Typesetter for creating script displays and state management
    func makeScripts(
        _ atom: MTMathAtom?,
        display: MTDisplay?,
        index: UInt,
        delta: CGFloat,
        context: MTRenderContext,
        typesetter: MTTypesetter
    ) {
        guard let atom = atom else { return }
        assert(atom.subScript != nil || atom.superScript != nil)
        
        var superScriptShiftUp: CGFloat = 0.0
        var subscriptShiftDown: CGFloat = 0.0
        
        display?.hasScript = true
        
        // Calculate baseline shifts for non-simple displays
        if !(display is MTCTLineDisplay) {
            let scriptFontSize = MTTypesetter.getStyleSize(scriptStyle(for: context.style), font: context.font)
            let scriptFont = context.font.copy(withSize: scriptFontSize)
            
            guard let scriptFontMetrics = scriptFont.mathTable,
                  let display = display else { return }
            
            superScriptShiftUp = display.ascent - scriptFontMetrics.superscriptBaselineDropMax
            subscriptShiftDown = display.descent + scriptFontMetrics.subscriptBaselineDropMin
        }
        
        guard let mathTable = context.styleFont.mathTable else { return }
        
        // Handle subscript-only case
        if atom.superScript == nil {
            guard let subScript = atom.subScript else { return }
            
            let subscriptDisplay = MTTypesetter.createLineForMathList(
                subScript,
                font: context.font,
                style: scriptStyle(for: context.style),
                cramped: subscriptCramped()
            )
            
            guard let subscriptDisplay = subscriptDisplay else { return }
            
            subscriptDisplay.type = .ssubscript
            subscriptDisplay.index = Int(index)
            
            subscriptShiftDown = max(subscriptShiftDown, mathTable.subscriptShiftDown)
            subscriptShiftDown = max(subscriptShiftDown, subscriptDisplay.ascent - mathTable.subscriptTopMax)
            
            subscriptDisplay.position = CGPoint(
                x: context.position.x,
                y: context.position.y - subscriptShiftDown
            )
            
            typesetter.displayAtoms.append(subscriptDisplay)
            typesetter.currentPosition.x += subscriptDisplay.width + mathTable.spaceAfterScript
            return
        }
        
        // Handle superscript (with or without subscript)
        guard let superScript = atom.superScript else { return }
        
        let superScriptDisplay = MTTypesetter.createLineForMathList(
            superScript,
            font: context.font,
            style: scriptStyle(for: context.style),
            cramped: superScriptCramped(for: context.cramped)
        )
        
        guard let superScriptDisplay = superScriptDisplay else { return }
        
        superScriptDisplay.type = .superscript
        superScriptDisplay.index = Int(index)
        
        let minShiftUp = calculateSuperScriptShiftUp(for: context)
        superScriptShiftUp = max(superScriptShiftUp, minShiftUp)
        superScriptShiftUp = max(superScriptShiftUp, superScriptDisplay.descent + mathTable.superscriptBottomMin)
        
        // Handle superscript-only case
        if atom.subScript == nil {
            superScriptDisplay.position = CGPoint(
                x: context.position.x,
                y: context.position.y + superScriptShiftUp
            )
            
            typesetter.displayAtoms.append(superScriptDisplay)
            typesetter.currentPosition.x += superScriptDisplay.width + mathTable.spaceAfterScript
            return
        }
        
        // Handle combined subscript and superscript
        guard let subScript = atom.subScript else { return }
        
        let subscriptDisplay = MTTypesetter.createLineForMathList(
            subScript,
            font: context.font,
            style: scriptStyle(for: context.style),
            cramped: subscriptCramped()
        )
        
        guard let subscriptDisplay = subscriptDisplay else { return }
        
        subscriptDisplay.type = .ssubscript
        subscriptDisplay.index = Int(index)
        
        subscriptShiftDown = max(subscriptShiftDown, mathTable.subscriptShiftDown)
        
        // Joint positioning of subscript & superscript
        let subSuperScriptGap = (superScriptShiftUp - superScriptDisplay.descent) +
                                (subscriptShiftDown - subscriptDisplay.ascent)
        
        if subSuperScriptGap < mathTable.subSuperscriptGapMin {
            // Increase gap to minimum
            subscriptShiftDown += mathTable.subSuperscriptGapMin - subSuperScriptGap
            
            let superscriptBottomDelta = mathTable.superscriptBottomMaxWithSubscript -
                                        (superScriptShiftUp - superScriptDisplay.descent)
            
            if superscriptBottomDelta > 0 {
                // Superscript is lower than max allowed with subscript
                superScriptShiftUp += superscriptBottomDelta
                subscriptShiftDown -= superscriptBottomDelta
            }
        }
        
        // Position both scripts
        // Delta is italic correction that shifts superscript position
        superScriptDisplay.position = CGPoint(
            x: context.position.x + delta,
            y: context.position.y + superScriptShiftUp
        )
        
        subscriptDisplay.position = CGPoint(
            x: context.position.x,
            y: context.position.y - subscriptShiftDown
        )
        
        typesetter.displayAtoms.append(superScriptDisplay)
        typesetter.displayAtoms.append(subscriptDisplay)
        
        typesetter.currentPosition.x += max(superScriptDisplay.width + delta, subscriptDisplay.width) +
                                       mathTable.spaceAfterScript
    }
    
    // MARK: - Helper Methods
    
    /// Returns the appropriate style for scripts based on current style
    private func scriptStyle(for style: MTLineStyle) -> MTLineStyle {
        switch style {
        case .display, .text:
            return .script
        case .script, .scriptOfScript:
            return .scriptOfScript
        }
    }
    
    /// Subscripts are always cramped
    private func subscriptCramped() -> Bool {
        return true
    }
    
    /// Superscripts are cramped only if the current style is cramped
    private func superScriptCramped(for cramped: Bool) -> Bool {
        return cramped
    }
    
    /// Returns the baseline shift for superscripts
    private func calculateSuperScriptShiftUp(for context: MTRenderContext) -> CGFloat {
        guard let mathTable = context.styleFont.mathTable else { return 0 }
        
        if context.cramped {
            return mathTable.superscriptShiftUpCramped
        } else {
            return mathTable.superscriptShiftUp
        }
    }
}
