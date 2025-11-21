//
//  Created by Mike Griebling on 2022-12-31.
//  Translated from an Objective-C implementation by Kostub Deshmukh.
//
//  This software may be modified and distributed under the terms of the
//  MIT license. See the LICENSE file for details.
//

// MARK: - TeX Algorithm Implementation Reference

/// This file implements mathematical typesetting based on The TeXbook, Appendix G:
/// "Generating Boxes from Formulas" by Donald E. Knuth.
///
/// ## TeX Rule Implementation Mapping
///
/// **Preprocessing (Appendix G, Rules 1-6):**
/// - Rule 5 (Binary → Ordinary): ✅ Implemented in `MTMathList.finalize()`
/// - Rule 6 (Remove empty boundaries): ✅ Implemented in `MTMathList.finalize()`
/// - Rule 14 (Merge adjacent ordinary): ✅ Implemented in `preprocessMathList()` (line ~468)
///
/// **Spacing (Appendix G, Rule 16):**
/// - Inter-element spacing table: ✅ Implemented in `getInterElementSpaces()` (line ~26)
/// - Spacing calculation: ✅ Implemented in `addInterElementSpace()` (line ~496)
/// - Thin space (3mu): ✅ `.thin`
/// - Medium space (4mu): ✅ `.nsMedium`
/// - Thick space (5mu): ✅ `.nsThick`
/// - Note: "ns" prefix = "not in script mode" (suppressed in cramped/script styles)
///
/// **Fractions (Appendix G, Rule 15):**
/// - Generalized fractions: ✅ Implemented in `makeFraction()` (line ~1877)
/// - Numerator/denominator styling: ✅ Adaptive style selection
/// - Fraction bar positioning: ✅ Axis-aligned with configurable gaps
/// - Continued fractions: ✅ Special handling (always display style)
///
/// **Scripts (Appendix G, Rule 17):**
/// - Superscript positioning: ✅ Implemented in `MTScriptRenderer`
/// - Subscript positioning: ✅ Implemented in `MTScriptRenderer`
/// - Cramped styles: ✅ Controlled by `cramped` flag
/// - Script size reduction: ✅ Via `scriptStyle()`, `scriptOfScriptStyle()`
///
/// **Radicals (Appendix G, Rule 11):**
/// - Radical construction: ✅ Implemented in `makeRadical()` (line ~2029)
/// - Vertical gap calculation: ✅ `radicalVerticalGap()` (line ~1997)
/// - Glyph assembly: ✅ `getRadicalGlyphWithHeight()` (line ~2011)
/// - Rule thickness: ✅ Uses math table parameters
///
/// **Large Operators (Appendix G, Rule 13):**
/// - Display style enlargement: ✅ Implemented in `makeLargeOp()` (line ~2234)
/// - Limits positioning: ✅ `addLimitsToDisplay()` (line ~2277)
/// - Vertical centering: ✅ Axis-aligned using `axisHeight`
/// - Italic correction: ✅ Applied to superscripts
///
/// **Accents (Appendix G, Rule 12):**
/// - Accent positioning: ✅ Implemented in `makeAccent()` (line ~2535)
/// - Horizontal skew: ✅ `getSkew()` (line ~2469)
/// - Width-based variant selection: ✅ `findVariantGlyph()` (line ~2490)
/// - Base height consideration: ✅ Uses `accentBaseHeight`
///
/// **Delimiters (Appendix G, Rules 19-20):**
/// - Variable-size delimiters: ✅ `findGlyphForBoundary()` (line ~2390)
/// - Height-based selection: ✅ `findGlyph()` (line ~2076)
/// - Extensible construction: ✅ `constructGlyph()` (line ~2113)
/// - Delimiter factor (901): ✅ `kDelimiterFactor` (line ~2336)
/// - Delimiter shortfall (5pt): ✅ `kDelimiterShortfallPoints` (line ~2337)
///
/// **Line Breaking (TeX \discretionary):**
/// - Break point detection: ✅ `checkAndPerformInteratomLineBreak()` (line ~541)
/// - Penalty calculation: ✅ `calculateBreakPenalty()` (line ~666)
/// - Width estimation: ✅ `estimateRemainingAtomsWidth()` (line ~674)
/// - Look-ahead optimization: ✅ Up to 5 atoms ahead
///
/// **Tables/Matrices (TeX \halign):**
/// - Multi-row layout: ✅ `makeTable()` (line ~2600)
/// - Column alignment: ✅ Left, center, right support
/// - Row positioning: ✅ `positionRows()` (line ~2680)
/// - Baseline skip: ✅ Configurable inter-row spacing
///
/// **Deviations from TeX:**
/// 1. **Radical spacing** (line ~70): Adds space after \sqrt in non-row contexts
///    - TeX: Treats radical as ordinary (no right spacing)
///    - SwiftMath: Adds 8mu spacing for better visuals (e.g., "√4 4" → "√4 4")
///
/// 2. **Line breaking**: Not part of original TeX math mode
///    - SwiftMath: Custom algorithm for multi-line equations
///    - Uses penalty scores to avoid breaking at poor locations
///
/// 3. **Unicode normalization** (line ~1131): Modern Unicode composition
///    - TeX: Uses font-based accent positioning only
///    - SwiftMath: Attempts Unicode NFC composition first, falls back to positioning
///
/// ## References
/// - The TeXbook (Knuth, 1984), Appendix G
/// - TeX Math Layout: https://www.tug.org/TUGboat/tb30-1/tb94vieth.pdf
/// - OpenType Math Table: https://docs.microsoft.com/typography/opentype/spec/math

import Foundation
import CoreText

// MARK: - Inter Element Spacing

/// Inter-element spacing types based on TeX Appendix G, Rule 16.
///
/// TeX defines spacing in "mu" (math units), where 18mu = 1em.
/// This implementation uses the following mapping:
/// - `.none`: 0mu (no space)
/// - `.thin`: 3mu (\,)
/// - `.nsThin`: 3mu, suppressed in script mode
/// - `.nsMedium`: 4mu (\:), suppressed in script mode  
/// - `.nsThick`: 5mu (\;), suppressed in script mode
///
/// The "ns" prefix means "not in script mode" - these spaces are
/// omitted when `spaced = false` (cramped or script styles).
///
/// ## TeX Spacing Rules (Appendix G, Table 18.2)
/// Spacing depends on the types of adjacent atoms:
/// - Ord Op: thin space
/// - Ord Bin: medium space (in display/text mode)
/// - Bin Rel: invalid (Rule 5 converts Bin → Ord)
/// - Rel Rel: no space (e.g., "< =" becomes "<=")
/// - Open anything: no space
/// - Punct anything: thin space
enum InterElementSpaceType : Int {
    case invalid = -1
    case none = 0
    case thin
    case nsThin    // Thin but not in script mode
    case nsMedium
    case nsThick
}

var interElementSpaceArray = [[InterElementSpaceType]]()
private let interElementLock = NSLock()

/// Returns the inter-element spacing table from TeX Appendix G, Rule 16.
///
/// This table defines spacing between adjacent math atoms based on their types.
/// Based on The TeXbook, Appendix G, page 170, Table 18.2.
///
/// ## Table Structure
/// - Rows: Left atom type (first atom)
/// - Columns: Right atom type (second atom)
/// - Values: Space type to insert between atoms
///
/// ## TeX Rule 16: Spacing
/// "If the math list to be typeset has length ≥ 2, we examine pairs of adjacent items
/// (x, y) and insert glue between them based on their types."
///
/// ## Deviations from TeX
/// - **Radical (row 8):** Added spacing after radicals (TeX treats as Ord)
///   - Reason: Visual clarity (e.g., "√4 4" needs space)
/// - **Fraction (col 7):** Custom spacing for continued fractions
///
/// - Returns: 9×8 spacing table where `table[leftType][rightType]` gives the space
func getInterElementSpaces() -> [[InterElementSpaceType]] {
    if interElementSpaceArray.isEmpty {
        
        interElementLock.lock()
        defer { interElementLock.unlock() }
        guard interElementSpaceArray.isEmpty else { return interElementSpaceArray }
        
        // TeX Appendix G, Table 18.2: Inter-atom spacing
        // Reference: The TeXbook, page 170
        interElementSpaceArray =
        //   ordinary   operator   binary     relation  open       close     punct     fraction
        [  [.none,     .thin,     .nsMedium, .nsThick, .none,     .none,    .none,    .nsThin],    // ordinary
           [.thin,     .thin,     .invalid,  .nsThick, .none,     .none,    .none,    .nsThin],    // operator
           [.nsMedium, .nsMedium, .invalid,  .invalid, .nsMedium, .invalid, .invalid, .nsMedium],  // binary
           [.nsThick,  .nsThick,  .invalid,  .none,    .nsThick,  .none,    .none,    .nsThick],   // relation
           [.none,     .none,     .invalid,  .none,    .none,     .none,    .none,    .none],      // open
           [.none,     .thin,     .nsMedium, .nsThick, .none,     .none,    .none,    .nsThin],    // close
           [.nsThin,   .nsThin,   .invalid,  .nsThin,  .nsThin,   .nsThin,  .nsThin,  .nsThin],    // punct
           [.nsThin,   .thin,     .nsMedium, .nsThick, .nsThin,   .none,    .nsThin,  .nsThin],    // fraction
           [.nsMedium, .nsThin,   .nsMedium, .nsThick, .none,     .none,    .none,    .nsThin]]    // radical
    }
    return interElementSpaceArray
}


// Get's the index for the given type. If row is true, the index is for the row (i.e. left element) otherwise it is for the column (right element)
func getInterElementSpaceArrayIndexForType(_ type:MTMathAtomType, row:Bool) -> Int {
    switch type {
        case .color, .textcolor, .colorBox, .ordinary, .placeholder:   // A placeholder is treated as ordinary
            return 0
        case .largeOperator:
            return 1
        case .binaryOperator:
            return 2;
        case .relation:
            return 3;
        case .open:
            return 4;
        case .close:
            return 5;
        case .punctuation:
            return 6;
        case .fraction,  // Fraction and inner are treated the same.
             .inner:
            return 7;
        case .radical:
            if row {
                // Radicals have inter element spaces only when on the left side.
                // Note: This is a departure from latex but we don't want \sqrt{4}4 to look weird so we put a space in between.
                // They have the same spacing as ordinary except with ordinary.
                return 8;
            } else {
                // Treat radical as ordinary on the right side
                return 0
            }
        // Numbers, variables, and unary operators are treated as ordinary
        case .number, .variable, .unaryOperator:
            return 0
        // Decorative types (accent, underline, overline) are treated as ordinary
        case .accent, .underline, .overline:
            return 0
        // Special types that don't typically participate in spacing are treated as ordinary
        case .boundary, .space, .style, .table:
            return 0
    }
}

// MARK: - Italics
// mathit
func getItalicized(_ ch:Character) -> UTF32Char  {
    var unicode = ch.utf32Char
    
    // Special cases for italics
    if ch == "h" { return UnicodeSymbol.planksConstant }
    
    if ch.isUpperEnglish {
        unicode = UnicodeSymbol.capitalItalicStart + (ch.utf32Char - Character("A").utf32Char)
    } else if ch.isLowerEnglish {
        unicode = UnicodeSymbol.lowerItalicStart + (ch.utf32Char - Character("a").utf32Char)
    } else if ch.isCapitalGreek {
        // Capital Greek characters
        unicode = UnicodeSymbol.greekCapitalItalicStart + (ch.utf32Char - UnicodeSymbol.capitalGreekStart)
    } else if ch.isLowerGreek {
        // Greek characters
        unicode = UnicodeSymbol.greekLowerItalicStart + (ch.utf32Char - UnicodeSymbol.lowerGreekStart)
    } else if ch.isGreekSymbol {
        return UnicodeSymbol.greekSymbolItalicStart + ch.greekSymbolOrder!
    }
    // Note there are no italicized numbers in unicode so we don't support italicizing numbers.
    return unicode
}

// mathbf
func getBold(_ ch:Character) -> UTF32Char {
    var unicode = ch.utf32Char
    if ch.isUpperEnglish {
        unicode = UnicodeSymbol.mathCapitalBoldStart + (ch.utf32Char - Character("A").utf32Char)
    } else if ch.isLowerEnglish {
        unicode = UnicodeSymbol.mathLowerBoldStart + (ch.utf32Char - Character("a").utf32Char)
    } else if ch.isCapitalGreek {
        // Capital Greek characters
        unicode = UnicodeSymbol.greekCapitalBoldStart + (ch.utf32Char - UnicodeSymbol.capitalGreekStart);
    } else if ch.isLowerGreek {
        // Greek characters
        unicode = UnicodeSymbol.greekLowerBoldStart + (ch.utf32Char - UnicodeSymbol.lowerGreekStart);
    } else if ch.isGreekSymbol {
        return UnicodeSymbol.greekSymbolBoldStart + ch.greekSymbolOrder!
    } else if ch.isNumber {
        unicode = UnicodeSymbol.numberBoldStart + (ch.utf32Char - Character("0").utf32Char)
    }
    return unicode
}

// mathbfit
func getBoldItalic(_ ch:Character) -> UTF32Char {
    var unicode = ch.utf32Char
    if ch.isUpperEnglish {
        unicode = UnicodeSymbol.mathCapitalBoldItalicStart + (ch.utf32Char - Character("A").utf32Char)
    } else if ch.isLowerEnglish {
        unicode = UnicodeSymbol.mathLowerBoldItalicStart + (ch.utf32Char - Character("a").utf32Char)
    } else if ch.isCapitalGreek {
        // Capital Greek characters
        unicode = UnicodeSymbol.greekCapitalBoldItalicStart + (ch.utf32Char - UnicodeSymbol.capitalGreekStart);
    } else if ch.isLowerGreek {
        // Greek characters
        unicode = UnicodeSymbol.greekLowerBoldItalicStart + (ch.utf32Char - UnicodeSymbol.lowerGreekStart);
    } else if ch.isGreekSymbol {
        return UnicodeSymbol.greekSymbolBoldItalicStart + ch.greekSymbolOrder!
    } else if ch.isNumber {
        // No bold italic for numbers so we just bold them.
        unicode = getBold(ch);
    }
    return unicode;
}

// LaTeX default
func getDefaultStyle(_ ch:Character) -> UTF32Char {
    if ch.isLowerEnglish || ch.isUpperEnglish || ch.isLowerGreek || ch.isGreekSymbol {
        return getItalicized(ch);
    } else if ch.isNumber || ch.isCapitalGreek {
        // In the default style numbers and capital greek is roman
        return ch.utf32Char
    } else if ch == "." {
        // . is treated as a number in our code, but it doesn't change fonts.
        return ch.utf32Char
    } else {
        NSException(name: NSExceptionName("IllegalCharacter"), reason: "Unknown character \(ch) for default style.").raise()
    }
    return ch.utf32Char
}

// mathcal/mathscr (caligraphic or script)
func getCaligraphic(_ ch:Character) -> UTF32Char {
    // Caligraphic has lots of exceptions:
    switch ch {
        case "B":
            return 0x212C;   // Script B (bernoulli)
        case "E":
            return 0x2130;   // Script E (emf)
        case "F":
            return 0x2131;   // Script F (fourier)
        case "H":
            return 0x210B;   // Script H (hamiltonian)
        case "I":
            return 0x2110;   // Script I
        case "L":
            return 0x2112;   // Script L (laplace)
        case "M":
            return 0x2133;   // Script M (M-matrix)
        case "R":
            return 0x211B;   // Script R (Riemann integral)
        case "e":
            return 0x212F;   // Script e (Natural exponent)
        case "g":
            return 0x210A;   // Script g (real number)
        case "o":
            return 0x2134;   // Script o (order)
        default:
            break;
    }
    var unicode:UTF32Char
    if ch.isUpperEnglish {
        unicode = UnicodeSymbol.mathCapitalScriptStart + (ch.utf32Char - Character("A").utf32Char)
    } else if ch.isLowerEnglish {
        // Latin Modern Math does not have lower case caligraphic characters, so we use
        // the default style instead of showing a ?
        unicode = getDefaultStyle(ch)
    } else {
        // Caligraphic characters don't exist for greek or numbers, we give them the
        // default treatment.
        unicode = getDefaultStyle(ch)
    }
    return unicode;
}

// mathtt (monospace)
func getTypewriter(_ ch:Character) -> UTF32Char {
    if ch.isUpperEnglish {
        return UnicodeSymbol.mathCapitalTTStart + (ch.utf32Char - Character("A").utf32Char)
    } else if ch.isLowerEnglish {
        return UnicodeSymbol.mathLowerTTStart + (ch.utf32Char - Character("a").utf32Char)
    } else if ch.isNumber {
        return UnicodeSymbol.numberTTStart + (ch.utf32Char - Character("0").utf32Char)
    }
    // Monospace characters don't exist for greek, we give them the
    // default treatment.
    return getDefaultStyle(ch);
}

// mathsf
func getSansSerif(_ ch:Character) -> UTF32Char {
    if ch.isUpperEnglish {
        return UnicodeSymbol.mathCapitalSansSerifStart + (ch.utf32Char - Character("A").utf32Char)
    } else if ch.isLowerEnglish {
        return UnicodeSymbol.mathLowerSansSerifStart + (ch.utf32Char - Character("a").utf32Char)
    } else if ch.isNumber {
        return UnicodeSymbol.numberSansSerifStart + (ch.utf32Char - Character("0").utf32Char)
    }
    // Sans-serif characters don't exist for greek, we give them the
    // default treatment.
    return getDefaultStyle(ch);
}

// mathfrak
func getFraktur(_ ch:Character) -> UTF32Char {
    // Fraktur has exceptions:
    switch ch {
        case "C":
            return 0x212D;   // C Fraktur
        case "H":
            return 0x210C;   // Hilbert space
        case "I":
            return 0x2111;   // Imaginary
        case "R":
            return 0x211C;   // Real
        case "Z":
            return 0x2128;   // Z Fraktur
        default:
            break;
    }
    if ch.isUpperEnglish {
        return UnicodeSymbol.mathCapitalFrakturStart + (ch.utf32Char - Character("A").utf32Char)
    } else if ch.isLowerEnglish {
        return UnicodeSymbol.mathLowerFrakturStart + (ch.utf32Char - Character("a").utf32Char)
    }
    // Fraktur characters don't exist for greek & numbers, we give them the
    // default treatment.
    return getDefaultStyle(ch);
}

// mathbb (double struck)
func getBlackboard(_ ch:Character) -> UTF32Char {
    // Blackboard has lots of exceptions:
    switch(ch) {
        case "C":
            return 0x2102;   // Complex numbers
        case "H":
            return 0x210D;   // Quarternions
        case "N":
            return 0x2115;   // Natural numbers
        case "P":
            return 0x2119;   // Primes
        case "Q":
            return 0x211A;   // Rationals
        case "R":
            return 0x211D;   // Reals
        case "Z":
            return 0x2124;   // Integers
        default:
            break;
    }
    if ch.isUpperEnglish {
        return UnicodeSymbol.mathCapitalBlackboardStart + (ch.utf32Char - Character("A").utf32Char)
    } else if ch.isLowerEnglish {
        return UnicodeSymbol.mathLowerBlackboardStart + (ch.utf32Char - Character("a").utf32Char)
    } else if ch.isNumber {
        return UnicodeSymbol.numberBlackboardStart + (ch.utf32Char - Character("0").utf32Char)
    }
    // Blackboard characters don't exist for greek, we give them the
    // default treatment.
    return getDefaultStyle(ch);
}

func styleCharacter(_ ch:Character, fontStyle:MTFontStyle) -> UTF32Char {
    switch fontStyle {
        case .defaultStyle:
            return getDefaultStyle(ch);
        case .roman:
            return ch.utf32Char
        case .bold:
            return getBold(ch);
        case .italic:
            return getItalicized(ch);
        case .boldItalic:
            return getBoldItalic(ch);
        case .caligraphic:
            return getCaligraphic(ch);
        case .typewriter:
            return getTypewriter(ch);
        case .sansSerif:
            return getSansSerif(ch);
        case .fraktur:
            return getFraktur(ch);
        case .blackboard:
            return getBlackboard(ch);
    }
}

func changeFont(_ str:String, fontStyle:MTFontStyle) -> String {
    var retval = ""
    let codes = Array(str)
    for i in 0..<str.count {
        let ch = codes[i]
        var unicode = styleCharacter(ch, fontStyle: fontStyle);
        unicode = NSSwapHostIntToLittle(unicode)
        let charStr = String(UnicodeScalar(unicode)!)
        retval.append(charStr)
    }
    return retval
}

func getBboxDetails(_ bbox:CGRect, ascent:inout CGFloat, descent:inout CGFloat) {
    ascent = max(0, CGRectGetMaxY(bbox) - 0)
    
    // Descent is how much the line goes below the origin. However if the line is all above the origin, then descent can't be negative.
    descent = max(0, 0 - CGRectGetMinY(bbox))
}

// MARK: - MTTypesetter

class MTTypesetter {
    var font:MTFont!
    var displayAtoms = [MTDisplay]()
    var currentPosition = CGPoint.zero
    var currentLine:NSMutableAttributedString!
    var currentAtoms = [MTMathAtom]()   // List of atoms that make the line
    var currentLineIndexRange = NSMakeRange(0, 0)
    var style:MTLineStyle { didSet { _styleFont = nil } }
    private var _styleFont:MTFont?
    var styleFont:MTFont {
        if _styleFont == nil {
            _styleFont = font.copy(withSize: Self.getStyleSize(style, font: font))
        }
        return _styleFont!
    }
    var cramped = false
    var spaced = false
    var maxWidth: CGFloat = 0  // Maximum width for line breaking, 0 means no constraint
    var currentLineStartIndex: Int = 0  // Index in displayAtoms where current line starts
    var minimumLineSpacing: CGFloat = 0  // Minimum spacing between lines (will be set based on fontSize)

    // Performance optimization: skip line breaking checks if we know all remaining content fits
    private var remainingContentFits = false
    
    // MARK: - Renderers
    private let fractionRenderer = MTFractionRenderer()
    private let radicalRenderer = MTRadicalRenderer()
    private let scriptRenderer = MTScriptRenderer()

    static func createLineForMathList(_ mathList:MTMathList?, font:MTFont?, style:MTLineStyle) -> MTMathListDisplay? {
        let finalizedList = mathList?.finalized
        // default is not cramped, no width constraint
        return self.createLineForMathList(finalizedList, font:font, style:style, cramped:false, maxWidth: 0)
    }

    static func createLineForMathList(_ mathList:MTMathList?, font:MTFont?, style:MTLineStyle, maxWidth:CGFloat) -> MTMathListDisplay? {
        let finalizedList = mathList?.finalized
        // default is not cramped
        return self.createLineForMathList(finalizedList, font:font, style:style, cramped:false, maxWidth: maxWidth)
    }

    // Internal
    static func createLineForMathList(_ mathList:MTMathList?, font:MTFont?, style:MTLineStyle, cramped:Bool) -> MTMathListDisplay? {
        return self.createLineForMathList(mathList, font:font, style:style, cramped:cramped, spaced:false, maxWidth: 0)
    }

    // Internal
    static func createLineForMathList(_ mathList:MTMathList?, font:MTFont?, style:MTLineStyle, cramped:Bool, maxWidth:CGFloat) -> MTMathListDisplay? {
        return self.createLineForMathList(mathList, font:font, style:style, cramped:cramped, spaced:false, maxWidth: maxWidth)
    }

    // Internal
    static func createLineForMathList(_ mathList:MTMathList?, font:MTFont?, style:MTLineStyle, cramped:Bool, spaced:Bool) -> MTMathListDisplay? {
        return self.createLineForMathList(mathList, font:font, style:style, cramped:cramped, spaced:spaced, maxWidth: 0)
    }

    // Internal
    static func createLineForMathList(_ mathList:MTMathList?, font:MTFont?, style:MTLineStyle, cramped:Bool, spaced:Bool, maxWidth:CGFloat) -> MTMathListDisplay? {
        assert(font != nil)
        let preprocessedAtoms = self.preprocessMathList(mathList)
        let typesetter = MTTypesetter(withFont:font, style:style, cramped:cramped, spaced:spaced, maxWidth: maxWidth)
        typesetter.createDisplayAtoms(preprocessedAtoms)
        let lastAtom = mathList?.atoms.last
        let last = lastAtom?.indexRange ?? NSMakeRange(0, 0)
        let line = MTMathListDisplay(withDisplays: typesetter.displayAtoms, range: NSMakeRange(0, NSMaxRange(last)))
        return line
    }
    
    static var placeholderColor: MTColor { MTColor.blue }

    init(withFont font:MTFont?, style:MTLineStyle, cramped:Bool, spaced:Bool, maxWidth:CGFloat = 0) {
        self.font = font
        self.displayAtoms = [MTDisplay]()
        self.currentPosition = CGPoint.zero
        self.cramped = cramped
        self.spaced = spaced
        self.maxWidth = maxWidth
        self.currentLine = NSMutableAttributedString()
        self.currentAtoms = [MTMathAtom]()
        self.style = style
        self.currentLineIndexRange = NSMakeRange(NSNotFound, NSNotFound);
        self.currentLineStartIndex = 0
        // Set minimum line spacing to 20% of fontSize for some breathing room
        self.minimumLineSpacing = (font?.fontSize ?? 0) * 0.2
    }
    
    /// Preprocesses the math list according to TeX Appendix G preprocessing rules.
    ///
    /// ## TeX Rule Implementation
    ///
    /// **Rule 5 (Binary → Ordinary):** ✅ Handled in `MTMathList.finalize()`
    /// - Converts binary operators to ordinary at start/end of lists
    /// - Example: "+ x" → ordinary +, "x -" → ordinary -
    ///
    /// **Rule 6 (Boundary removal):** ✅ Handled in `MTMathList.finalize()`
    /// - Removes empty left/right boundaries
    /// - Simplifies inner lists before typesetting
    ///
    /// **Rule 14 (Merge ordinary characters):** ✅ Implemented here (lines 468-478)
    /// - Combines adjacent ordinary atoms into single atoms
    /// - Prevents unnecessary spacing between letters in identifiers
    /// - Example: "a", "b", "c" → "abc" (single atom)
    /// - Only merges if no sub/superscripts (to preserve positioning)
    ///
    /// **Non-TeX Extensions:**
    /// - Converts `.variable` and `.number` types to `.ordinary` with italic font
    /// - Converts `.unaryOperator` to `.ordinary` (TeX handles during parsing)
    ///
    /// - Parameter ml: The math list to preprocess
    /// - Returns: Array of preprocessed atoms ready for typesetting
    ///
    /// - Note: This is step 1 of the typesetting pipeline. After this,
    ///   `createDisplayAtoms()` applies Rules 15-20 (fractions, radicals, etc.)
    static func preprocessMathList(_ ml:MTMathList?) -> [MTMathAtom] {
        
        // Guard against nil input
        guard let mathList = ml, !mathList.atoms.isEmpty else {
            return []
        }
        
        var preprocessed = [MTMathAtom]() //  arrayWithCapacity:ml.atoms.count)
        var prevNode:MTMathAtom! = nil
        preprocessed.reserveCapacity(mathList.atoms.count)
        for atom in mathList.atoms {
            if atom.type == .variable || atom.type == .number {
                // This is not a TeX type node. TeX does this during parsing the input.
                // switch to using the italic math font
                // We convert it to ordinary
                let newFont = changeFont(atom.nucleus, fontStyle: atom.fontStyle) // mathItalicize(atom.nucleus)
                atom.type = .ordinary
                atom.nucleus = newFont
            } else if atom.type == .unaryOperator {
                // Neither of these are TeX nodes. TeX treats these as Ordinary. So will we.
                atom.type = .ordinary
            }
            
            if atom.type == .ordinary {
                // This is Rule 14 to merge ordinary characters.
                // combine ordinary atoms together
                if prevNode != nil && prevNode.type == .ordinary && prevNode.subScript == nil && prevNode.superScript == nil {
                    prevNode.fuse(with: atom)
                    // skip the current node, we are done here.
                    continue
                }
            }
            
            // TODO: add italic correction here or in second pass?
            prevNode = atom
            preprocessed.append(atom)
        }
        return preprocessed
    }
    
    // returns the size of the font in this style
    static func getStyleSize(_ style:MTLineStyle, font:MTFont?) -> CGFloat {
        guard let font = font, let mathTable = font.mathTable else {
            return 0
        }
        let original = font.fontSize
        switch style {
            case .display, .text:
                return original
            case .script:
                return original * mathTable.scriptScaleDown
            case .scriptOfScript:
                return original * mathTable.scriptScriptScaleDown
        }
    }
    
    func addInterElementSpace(_ prevNode:MTMathAtom?, currentType type:MTMathAtomType) {
        var interElementSpace = CGFloat(0)
        if let prevNode = prevNode {
            interElementSpace = getInterElementSpace(prevNode.type, right:type)
        } else if self.spaced {
            // For the first atom of a spaced list, treat it as if it is preceded by an open.
            interElementSpace = getInterElementSpace(.open, right:type)
        }
        self.currentPosition.x += interElementSpace
    }

    // MARK: - Interatom Line Breaking

    /// Calculate the width that would result from adding this atom to the current line
    /// Returns the approximate width including inter-element spacing
    func calculateAtomWidth(_ atom: MTMathAtom, prevNode: MTMathAtom?) -> CGFloat {
        // Skip atoms that don't participate in normal width calculation
        // These are handled specially in the rendering code
        if atom.type == .space || atom.type == .style {
            return 0
        }

        // Calculate inter-element spacing (only for types that have defined spacing)
        var interElementSpace: CGFloat = 0
        if let prevNode = prevNode, prevNode.type != .space && prevNode.type != .style {
            interElementSpace = getInterElementSpace(prevNode.type, right: atom.type)
        } else if self.spaced && prevNode?.type != .space {
            interElementSpace = getInterElementSpace(.open, right: atom.type)
        }

        // Calculate the width of the atom's nucleus
        let atomString = NSAttributedString(string: atom.nucleus, attributes: [
            kCTFontAttributeName as NSAttributedString.Key: styleFont.ctFont as Any
        ])
        let ctLine = CTLineCreateWithAttributedString(atomString as CFAttributedString)
        let atomWidth = CGFloat(CTLineGetTypographicBounds(ctLine, nil, nil, nil))

        return interElementSpace + atomWidth
    }

    /// Calculate the current line width
    func getCurrentLineWidth() -> CGFloat {
        if currentLine.length == 0 {
            return 0
        }
        let attrString = currentLine.mutableCopy() as! NSMutableAttributedString
        attrString.addAttribute(kCTFontAttributeName as NSAttributedString.Key, value: styleFont.ctFont as Any, range: NSMakeRange(0, attrString.length))
        let ctLine = CTLineCreateWithAttributedString(attrString)
        return CGFloat(CTLineGetTypographicBounds(ctLine, nil, nil, nil))
    }

    /// Determines optimal line break point for mathematical typesetting.
    ///
    /// ## Line Breaking Algorithm (Non-TeX Extension)
    /// This implements a modified Knuth-Plass line breaking algorithm specifically
    /// adapted for mathematical formulas. TeX's original math mode doesn't support
    /// automatic line breaking - this is a SwiftMath extension.
    ///
    /// ### Algorithm Overview:
    /// 1. **Width calculation**: Check if adding atom exceeds `maxWidth`
    /// 2. **Look-ahead**: Examine next 3-5 atoms to find better break points
    /// 3. **Penalty scoring**: Assign penalties to different break locations
    /// 4. **Break decision**: Execute break if penalty is acceptable
    ///
    /// ### Penalty Scores (lower = better):
    /// - **0**: After operators, relations, punctuation (ideal break points)
    /// - **10**: After ordinary atoms (acceptable)
    /// - **50**: After fractions (moderately bad)
    /// - **100**: After open brackets, before close brackets (bad)
    /// - **150**: After unary/large operators (very bad)
    /// - **200**: Mid-expression with no good alternatives (worst)
    ///
    /// ### Break Conditions:
    /// - **Usage < 60%**: Continue without breaking (room available)
    /// - **Usage 60-120%**: Use penalty scoring for optimal break
    /// - **Usage > 120%**: Break immediately (severe overflow)
    ///
    /// ### Word Boundary Protection:
    /// Never breaks between consecutive ordinary atoms (e.g., "abc" stays together)
    ///
    /// ### Examples:
    /// - Good break: `a + b |newline c + d` (after operator)
    /// - Bad break: `(a + |newline b)` (after open paren)
    /// - Avoided: `ab|newline c` (mid-word)
    ///
    /// - Parameters:
    ///   - atom: Current atom being processed
    ///   - prevNode: Previous atom (for spacing context)
    ///   - nextAtoms: Upcoming atoms for look-ahead (max 5)
    /// - Returns: `true` if a line break was performed
    ///
    /// Check if we should break to a new line before adding this atom
    /// Uses look-ahead to find better break points aesthetically
    /// Returns true if a line break was performed
    @discardableResult
    func checkAndPerformInteratomLineBreak(_ atom: MTMathAtom, prevNode: MTMathAtom?, nextAtoms: [MTMathAtom] = []) -> Bool {
        // Only perform interatom breaking when maxWidth is set
        guard maxWidth > 0 else { return false }

        // Don't break if current line is empty
        guard currentLine.length > 0 else { return false }

        // Performance optimization: if we've determined remaining content fits, skip breaking checks
        if remainingContentFits {
            return false
        }

        // CRITICAL: Don't break in the middle of words
        // When "équivaut" is decomposed as "é" (accent) + "quivaut" (ordinary),
        // we must not break between them even if the line exceeds maxWidth.
        // Check if currentLine ends with a letter and next atom starts with a letter
        // This prevents breaking mid-word (like "é|quivaut")
        if atom.type == .ordinary && !atom.nucleus.isEmpty {
            let lineText = currentLine.string
            if !lineText.isEmpty {
                let lastChar = lineText.last!
                let firstChar = atom.nucleus.first!

                // If line ends with a letter (no trailing space/punctuation) and next atom
                // starts with a letter, they're part of the same word - don't break!
                // Example: "...é" + "quivaut" should not break
                // But "...km " + "équivaut" can break (has space)
                // IMPORTANT: Only apply this to multi-character atoms (text words), not single
                // letters (math variables). In math "4ac" splits as "4","a","c" - these are
                // separate and CAN be broken between.
                if lastChar.isLetter && firstChar.isLetter && atom.nucleus.count > 1 {
                    // Don't break - this would split a word
                    return false
                }
            }
        }

        // Calculate what the width would be if we add this atom
        // IMPORTANT: Use currentPosition.x instead of getCurrentLineWidth()
        // because currentLine only measures the current text segment, but after
        // superscripts/subscripts, the line may be split into multiple segments.
        // currentPosition.x tracks the actual visual horizontal position.
        let currentLineWidth = getCurrentLineWidth()
        let visualLineWidth = currentPosition.x + currentLineWidth
        let atomWidth = calculateAtomWidth(atom, prevNode: prevNode)
        let projectedWidth = visualLineWidth + atomWidth

        // If we're well within the limit, no need to break
        if projectedWidth <= maxWidth {
            // Performance optimization: if we have plenty of space left and limited atoms remaining,
            // we can skip all future line breaking checks for this line
            if !remainingContentFits && !nextAtoms.isEmpty {
                // Conservative estimate: if we're using less than 60% of available width
                // and have only a few atoms left, assume remaining content will fit
                let usageRatio = projectedWidth / maxWidth
                if usageRatio < 0.6 && nextAtoms.count <= 5 {
                    remainingContentFits = true
                } else if usageRatio < 0.75 {
                    // For moderate usage, estimate remaining content width
                    let estimatedRemainingWidth = estimateRemainingAtomsWidth(nextAtoms)
                    if projectedWidth + estimatedRemainingWidth <= maxWidth {
                        remainingContentFits = true
                    }
                }
            }
            return false
        }

        // We've exceeded the width. Now use break quality scoring to find the best break point.

        // If we're far over the limit (>20% excess), break immediately regardless of quality
        if projectedWidth > maxWidth * 1.2 {
            performInteratomLineBreak()
            return true
        }

        // We're slightly over the limit. Look ahead to see if there's a better break point coming soon.
        let currentPenalty = calculateBreakPenalty(afterAtom: prevNode, beforeAtom: atom)

        // Look ahead up to 3 atoms to find better break points
        var bestBreakOffset = 0  // 0 = break now (before current atom)
        var bestPenalty = currentPenalty

        var cumulativeWidth = projectedWidth
        var lookAheadPrev = atom

        for (offset, nextAtom) in nextAtoms.prefix(3).enumerated() {
            // Calculate width if we continue to this atom
            let nextAtomWidth = calculateAtomWidth(nextAtom, prevNode: lookAheadPrev)
            cumulativeWidth += nextAtomWidth

            // If we'd be way over the limit, stop looking ahead
            if cumulativeWidth > maxWidth * 1.3 {
                break
            }

            // Calculate penalty for breaking before this next atom
            let penalty = calculateBreakPenalty(afterAtom: lookAheadPrev, beforeAtom: nextAtom)

            // If this is a better break point (lower penalty), remember it
            if penalty < bestPenalty {
                bestPenalty = penalty
                bestBreakOffset = offset + 1  // +1 because we want to break before nextAtom
            }

            // If we found a perfect break point (penalty = 0), use it
            if penalty == 0 {
                break
            }

            lookAheadPrev = nextAtom
        }

        // If best break point is not at current position, defer the break
        if bestBreakOffset > 0 {
            // Don't break yet - continue adding atoms to find the better break point
            return false
        }

        // Break at current position (best option available)
        performInteratomLineBreak()
        return true
    }

    /// Estimate the approximate width of remaining atoms
    /// Returns a conservative (upper bound) estimate
    private func estimateRemainingAtomsWidth(_ atoms: [MTMathAtom]) -> CGFloat {
        // Use a simple heuristic: average character width * character count
        let avgCharWidth = styleFont.mathTable?.muUnit ?? (styleFont.fontSize / 18.0)
        var totalChars = 0

        for atom in atoms {
            // Count nucleus characters
            totalChars += atom.nucleus.count

            // Add extra for subscripts/superscripts (rough estimate)
            if atom.subScript != nil {
                totalChars += 3
            }
            if atom.superScript != nil {
                totalChars += 3
            }
        }

        // Return conservative estimate (multiply by 1.5 for safety margin)
        return CGFloat(totalChars) * avgCharWidth * 1.5
    }

    /// Perform the actual line break operation
    private func performInteratomLineBreak() {
        // Reset optimization flag - after breaking, we need to check again
        remainingContentFits = false

        // Flush the current line
        self.addDisplayLine()

        // Calculate dynamic line height based on actual content
        let lineHeight = calculateCurrentLineHeight()

        // Move down for new line using dynamic height
        currentPosition.y -= lineHeight
        currentPosition.x = 0

        // Update line start index for next line
        currentLineStartIndex = displayAtoms.count

        // Reset for new line
        currentLine = NSMutableAttributedString()
        currentAtoms = []
        currentLineIndexRange = NSMakeRange(NSNotFound, NSNotFound)
    }

    /// Check if we should break before adding a complex display (fraction, radical, etc.)
    /// Returns true if breaking is needed
    func shouldBreakBeforeDisplay(_ display: MTDisplay, prevNode: MTMathAtom?, displayType: MTMathAtomType = .ordinary) -> Bool {
        // No breaking if no width constraint
        guard maxWidth > 0 else { return false }

        // No breaking if line is empty
        guard currentLine.length > 0 else { return false }

        // Calculate spacing between current content and new display
        var interElementSpace: CGFloat = 0
        if let prevNode = prevNode {
            interElementSpace = getInterElementSpace(prevNode.type, right: displayType)
        }

        // Calculate projected width
        let currentWidth = getCurrentLineWidth()
        let projectedWidth = currentWidth + interElementSpace + display.width

        // Break only if it would exceed max width
        return projectedWidth > maxWidth
    }

    /// Perform line break for complex displays
    func performLineBreak() {
        if currentLine.length > 0 {
            self.addDisplayLine()
        }

        // Calculate dynamic line height based on actual content
        let lineHeight = calculateCurrentLineHeight()

        // Move down for new line using dynamic height
        currentPosition.y -= lineHeight
        currentPosition.x = 0

        // Update line start index for next line
        currentLineStartIndex = displayAtoms.count
    }

    /// Calculate the height of the current line based on actual display heights
    /// Returns the total height (max ascent + max descent) plus minimum spacing
    func calculateCurrentLineHeight() -> CGFloat {
        // If no displays added for current line, use default spacing
        guard currentLineStartIndex < displayAtoms.count else {
            return styleFont.fontSize * 1.5
        }

        var maxAscent: CGFloat = 0
        var maxDescent: CGFloat = 0

        // Iterate through all displays added for the current line
        for i in currentLineStartIndex..<displayAtoms.count {
            let display = displayAtoms[i]
            maxAscent = max(maxAscent, display.ascent)
            maxDescent = max(maxDescent, display.descent)
        }

        // Total line height = max ascent + max descent + minimum spacing
        let lineHeight = maxAscent + maxDescent + minimumLineSpacing

        // Ensure we have at least the baseline fontSize spacing for readability
        return max(lineHeight, styleFont.fontSize * 1.2)
    }

    /// Estimate the width of an atom including its scripts (without actually creating the displays)
    /// This is used for width-checking decisions for atoms with super/subscripts
    func estimateAtomWidthWithScripts(_ atom: MTMathAtom) -> CGFloat {
        // Estimate base atom width
        var atomWidth = CGFloat(atom.nucleus.count) * styleFont.fontSize * 0.5 // rough estimate

        // If atom has scripts, estimate their contribution
        if atom.superScript != nil || atom.subScript != nil {
            let scriptFontSize = Self.getStyleSize(self.scriptStyle(), font: font)

            var scriptWidth: CGFloat = 0
            if let superScript = atom.superScript {
                // Estimate superscript width
                let superScriptAtomCount = superScript.atoms.count
                scriptWidth = max(scriptWidth, CGFloat(superScriptAtomCount) * scriptFontSize * 0.5)
            }

            if let subScript = atom.subScript {
                // Estimate subscript width
                let subScriptAtomCount = subScript.atoms.count
                scriptWidth = max(scriptWidth, CGFloat(subScriptAtomCount) * scriptFontSize * 0.5)
            }

            // Add script width plus space after script
            if let mathTable = styleFont.mathTable {
                atomWidth += scriptWidth + mathTable.spaceAfterScript
            }
        }

        return atomWidth
    }

    /// Calculate break penalty score for breaking after a given atom type
    /// Lower scores indicate better break points (0 = best, higher = worse)
    func calculateBreakPenalty(afterAtom: MTMathAtom?, beforeAtom: MTMathAtom?) -> Int {
        // No atom context - neutral penalty
        guard let after = afterAtom else { return 50 }

        let afterType = after.type
        let beforeType = beforeAtom?.type

        // Best break points (penalty = 0): After binary operators, relations, punctuation
        if afterType == .binaryOperator {
            return 0  // Great: break after +, -, ×, ÷
        }
        if afterType == .relation {
            return 0  // Great: break after =, <, >, ≤, ≥
        }
        if afterType == .punctuation {
            return 0  // Great: break after commas, semicolons
        }

        // Good break points (penalty = 10): After ordinary atoms (variables, numbers)
        if afterType == .ordinary {
            return 10  // Good: break after variables like a, b, c
        }

        // Bad break points (penalty = 100): After open brackets or before close brackets
        if afterType == .open {
            return 100  // Bad: don't break immediately after (
        }
        if beforeType == .close {
            return 100  // Bad: don't break immediately before )
        }

        // Worse break points (penalty = 150): Would break operator-operand pairing
        if afterType == .unaryOperator || afterType == .largeOperator {
            return 150  // Worse: don't break after operators like ∑, ∫
        }

        // Neutral default
        return 50
    }

    func createDisplayAtoms(_ preprocessed:[MTMathAtom]) {
        // items should contain all the nodes that need to be layed out.
        // convert to a list of DisplayAtoms
        var prevNode:MTMathAtom? = nil
        var lastType:MTMathAtomType!
        for (index, atom) in preprocessed.enumerated() {
            // Get next atoms for look-ahead (up to 3 atoms ahead)
            let nextAtoms = Array(preprocessed.suffix(from: min(index + 1, preprocessed.count)).prefix(3))
            switch atom.type {
                case .number, .variable,. unaryOperator:
                    // These should never appear as they should have been removed by preprocessing
                    assertionFailure("These types should never show here as they are removed by preprocessing.")
                    
                case .boundary:
                    assertionFailure("A boundary atom should never be inside a mathlist.")
                    
                case .space:
                    // stash the existing layout
                    if currentLine.length > 0 {
                        self.addDisplayLine()
                    }
                    guard let space = atom as? MTMathSpace,
                          let mathTable = styleFont.mathTable else {
                        continue
                    }
                    // add the desired space
                    currentPosition.x += space.space * mathTable.muUnit;
                    // Since this is extra space, the desired interelement space between the prevAtom
                    // and the next node is still preserved. To avoid resetting the prevAtom and lastType
                    // we skip to the next node.
                    continue
                    
                case .style:
                    // stash the existing layout
                    if currentLine.length > 0 {
                        self.addDisplayLine()
                    }
                    guard let styleAtom = atom as? MTMathStyle else {
                        continue
                    }
                    self.style = styleAtom.style
                    // We need to preserve the prevNode for any interelement space changes.
                    // so we skip to the next node.
                    continue
                    
                case .color:
                    // Create the colored display first (pass maxWidth for inner breaking)
                    guard let colorAtom = atom as? MTMathColor,
                          let display = MTTypesetter.createLineForMathList(colorAtom.innerList, font: font, style: style, maxWidth: maxWidth) else {
                        continue
                    }
                    display.localTextColor = MTColor(fromHexString: colorAtom.colorString)

                    // Check if we need to break before adding this colored content
                    let shouldBreak = shouldBreakBeforeDisplay(display, prevNode: prevNode, displayType: .ordinary)

                    // Flush current line to convert accumulated text to displays
                    if currentLine.length > 0 {
                        self.addDisplayLine()
                    }

                    // Perform line break if needed
                    if shouldBreak {
                        performLineBreak()
                    } else {
                        self.addInterElementSpace(prevNode, currentType:.ordinary)
                    }

                    display.position = currentPosition
                    currentPosition.x += display.width
                    displayAtoms.append(display)

                case .textcolor:
                    // Create the text colored display first (pass maxWidth for inner breaking)
                    guard let colorAtom = atom as? MTMathTextColor,
                          let display = MTTypesetter.createLineForMathList(colorAtom.innerList, font: font, style: style, maxWidth: maxWidth) else {
                        continue
                    }
                    display.localTextColor = MTColor(fromHexString: colorAtom.colorString)

                    // Check if we need to break before adding this colored content
                    let shouldBreak = shouldBreakBeforeDisplay(display, prevNode: prevNode, displayType: .ordinary)

                    // Flush current line to convert accumulated text to displays
                    if currentLine.length > 0 {
                        self.addDisplayLine()
                    }

                    // Perform line break if needed
                    if shouldBreak {
                        performLineBreak()
                    } else if let prevNode = prevNode, display.subDisplays.count > 0 {
                        // Handle inter-element spacing if not breaking
                        if let subDisplay = display.subDisplays.first,
                           let ctLineDisplay = subDisplay as? MTCTLineDisplay,
                           !ctLineDisplay.atoms.isEmpty {
                            let subDisplayAtom = ctLineDisplay.atoms[0]
                            let interElementSpace = self.getInterElementSpace(prevNode.type, right:subDisplayAtom.type)
                            // Since we already flushed currentLine, it's empty now, so use x positioning
                            currentPosition.x += interElementSpace
                        }
                    }

                    display.position = currentPosition
                    currentPosition.x += display.width
                    displayAtoms.append(display)

                case .colorBox:
                    // Create the colorbox display first (pass maxWidth for inner breaking)
                    guard let colorboxAtom = atom as? MTMathColorbox,
                          let display = MTTypesetter.createLineForMathList(colorboxAtom.innerList, font:font, style:style, maxWidth: maxWidth) else {
                        continue
                    }

                    display.localBackgroundColor = MTColor(fromHexString: colorboxAtom.colorString)

                    // Check if we need to break before adding this colorbox
                    let shouldBreak = shouldBreakBeforeDisplay(display, prevNode: prevNode, displayType: .ordinary)

                    // Flush current line to convert accumulated text to displays
                    if currentLine.length > 0 {
                        self.addDisplayLine()
                    }

                    // Perform line break if needed
                    if shouldBreak {
                        performLineBreak()
                    } else {
                        self.addInterElementSpace(prevNode, currentType:.ordinary)
                    }

                    display.position = currentPosition
                    currentPosition.x += display.width
                    displayAtoms.append(display)
                    
                case .radical:
                    // Delegate to RadicalRenderer
                    let context = MTRenderContext(
                        font: font,
                        styleFont: styleFont,
                        style: style,
                        cramped: cramped,
                        spaced: spaced,
                        maxWidth: maxWidth,
                        position: currentPosition
                    )
                    
                    guard let displayRad = radicalRenderer.render(atom, context: context, typesetter: self) else {
                        continue
                    }

                    // Check if we need to break before adding this radical
                    // Radicals are considered as Ord in rule 16.
                    let shouldBreak = shouldBreakBeforeDisplay(displayRad, prevNode: prevNode, displayType: .ordinary)

                    // Flush current line to convert accumulated text to displays
                    if currentLine.length > 0 {
                        self.addDisplayLine()
                    }

                    // Perform line break if needed
                    if shouldBreak {
                        performLineBreak()
                    } else {
                        self.addInterElementSpace(prevNode, currentType:.ordinary)
                    }

                    // Position and add the radical display
                    displayRad.position = currentPosition
                    displayAtoms.append(displayRad)
                    currentPosition.x += displayRad.width

                    // add super scripts || subscripts
                    if atom.subScript != nil || atom.superScript != nil {
                        let rad = atom as! MTRadical
                        let scriptContext = MTRenderContext(
                            font: font,
                            styleFont: styleFont,
                            style: style,
                            cramped: cramped,
                            spaced: spaced,
                            maxWidth: maxWidth,
                            position: currentPosition
                        )
                        scriptRenderer.makeScripts(atom, display: displayRad, index: UInt(rad.indexRange.location), delta: 0, context: scriptContext, typesetter: self)
                    }
                    
                case .fraction:
                    // Delegate to FractionRenderer
                    let context = MTRenderContext(
                        font: font,
                        styleFont: styleFont,
                        style: style,
                        cramped: cramped,
                        spaced: spaced,
                        maxWidth: maxWidth,
                        position: currentPosition
                    )
                    
                    guard let display = fractionRenderer.render(atom, context: context, typesetter: self) else {
                        continue
                    }

                    // Check if we need to break before adding this fraction
                    let shouldBreak = shouldBreakBeforeDisplay(display, prevNode: prevNode, displayType: atom.type)

                    // Flush current line to convert accumulated text to displays
                    if currentLine.length > 0 {
                        self.addDisplayLine()
                    }

                    // Perform line break if needed
                    if shouldBreak {
                        performLineBreak()
                    } else {
                        self.addInterElementSpace(prevNode, currentType:atom.type)
                    }

                    // Position and add the fraction display
                    display.position = currentPosition
                    displayAtoms.append(display)
                    currentPosition.x += display.width

                    // add super scripts || subscripts
                    if atom.subScript != nil || atom.superScript != nil {
                        let frac = atom as! MTFraction
                        let scriptContext = MTRenderContext(
                            font: font,
                            styleFont: styleFont,
                            style: style,
                            cramped: cramped,
                            spaced: spaced,
                            maxWidth: maxWidth,
                            position: currentPosition
                        )
                        scriptRenderer.makeScripts(atom, display: display, index: UInt(frac.indexRange.location), delta: 0, context: scriptContext, typesetter: self)
                    }
                    
                case .largeOperator:
                    // Flush current line to convert accumulated text to displays
                    if currentLine.length > 0 {
                        self.addDisplayLine()
                    }

                    // Add inter-element spacing before operator
                    self.addInterElementSpace(prevNode, currentType:atom.type)

                    // Create and position the large operator display
                    // makeLargeOp sets position, advances currentPosition.x, and adds scripts
                    let op = atom as! MTLargeOperator?
                    let display = self.makeLargeOp(op)
                    displayAtoms.append(display!)
                    
                case .inner:
                    // Create the inner display first
                    guard let inner = atom as? MTInner else {
                        continue
                    }
                    
                    let display: MTDisplay?
                    if inner.leftBoundary != nil || inner.rightBoundary != nil {
                        // Pass maxWidth to delimited content so it can also break
                        display = self.makeLeftRight(inner, maxWidth:maxWidth)
                    } else {
                        // Pass maxWidth to inner content so it can also break
                        display = MTTypesetter.createLineForMathList(inner.innerList, font:font, style:style, cramped:cramped, maxWidth:maxWidth)
                    }
                    
                    guard let innerDisplay = display else {
                        continue
                    }

                    // Check if we need to break before adding this inner content
                    let shouldBreak = shouldBreakBeforeDisplay(innerDisplay, prevNode: prevNode, displayType: .inner)

                    // Flush current line to convert accumulated text to displays
                    if currentLine.length > 0 {
                        self.addDisplayLine()
                    }

                    // Perform line break if needed
                    if shouldBreak {
                        performLineBreak()
                    } else {
                        self.addInterElementSpace(prevNode, currentType:atom.type)
                    }

                    // Position and add the inner display
                    innerDisplay.position = currentPosition
                    currentPosition.x += innerDisplay.width
                    displayAtoms.append(innerDisplay)

                    // add super scripts || subscripts
                    if atom.subScript != nil || atom.superScript != nil {
                        let scriptContext = MTRenderContext(
                            font: font,
                            styleFont: styleFont,
                            style: style,
                            cramped: cramped,
                            spaced: spaced,
                            maxWidth: maxWidth,
                            position: currentPosition
                        )
                        scriptRenderer.makeScripts(atom, display: innerDisplay, index: UInt(atom.indexRange.location), delta: 0, context: scriptContext, typesetter: self)
                    }
                    
                case .underline:
                    // stash the existing layout
                    if currentLine.length > 0 {
                        self.addDisplayLine()
                    }
                    // Underline is considered as Ord in rule 16.
                    self.addInterElementSpace(prevNode, currentType:.ordinary)
                    atom.type = .ordinary;
                    
                    guard let under = atom as? MTUnderLine,
                          let display = self.makeUnderline(under) else {
                        continue
                    }
                    displayAtoms.append(display)
                    currentPosition.x += display.width;
                    // add super scripts || subscripts
                    if atom.subScript != nil || atom.superScript != nil {
                        let scriptContext = MTRenderContext(
                            font: font,
                            styleFont: styleFont,
                            style: style,
                            cramped: cramped,
                            spaced: spaced,
                            maxWidth: maxWidth,
                            position: currentPosition
                        )
                        scriptRenderer.makeScripts(atom, display: display, index: UInt(atom.indexRange.location), delta: 0, context: scriptContext, typesetter: self)
                    }
                    
                case .overline:
                    // stash the existing layout
                    if currentLine.length > 0 {
                        self.addDisplayLine()
                    }
                    // Overline is considered as Ord in rule 16.
                    self.addInterElementSpace(prevNode, currentType:.ordinary)
                    atom.type = .ordinary;
                    
                    guard let over = atom as? MTOverLine,
                          let display = self.makeOverline(over) else {
                        continue
                    }
                    displayAtoms.append(display)
                    currentPosition.x += display.width;
                    // add super scripts || subscripts
                    if atom.subScript != nil || atom.superScript != nil {
                        let scriptContext = MTRenderContext(
                            font: font,
                            styleFont: styleFont,
                            style: style,
                            cramped: cramped,
                            spaced: spaced,
                            maxWidth: maxWidth,
                            position: currentPosition
                        )
                        scriptRenderer.makeScripts(atom, display: display, index: UInt(atom.indexRange.location), delta: 0, context: scriptContext, typesetter: self)
                    }
                    
                case .accent:
                    if maxWidth > 0 {
                        // When line wrapping is enabled, render the accent properly but inline
                        // to avoid premature line flushing

                        let accent = atom as! MTAccent

                        // Get the base character from innerList
                        var baseChar = ""
                        if let innerList = accent.innerList, !innerList.atoms.isEmpty {
                            // Convert innerList to string
                            baseChar = MTMathListBuilder.mathListToString(innerList)
                        }

                        // Combine base character with accent to create proper composed character
                        let accentChar = atom.nucleus
                        let composedString = baseChar + accentChar

                        // Normalize to composed form (NFC) to get proper accented character
                        let normalizedString = composedString.precomposedStringWithCanonicalMapping

                        // Add inter-element spacing
                        if let prevNode = prevNode {
                            let interElementSpace = self.getInterElementSpace(prevNode.type, right:.ordinary)
                            if currentLine.length > 0 {
                                if interElementSpace > 0 {
                                    currentLine.addAttribute(kCTKernAttributeName as NSAttributedString.Key,
                                                           value:NSNumber(floatLiteral: interElementSpace),
                                                           range:currentLine.mutableString.rangeOfComposedCharacterSequence(at: currentLine.length-1))
                                }
                            } else {
                                currentPosition.x += interElementSpace
                            }
                        }

                        // Add the properly composed accented character
                        let current = NSAttributedString(string:normalizedString)
                        currentLine.append(current)

                        // Don't check for line breaks here - accented characters are part of words
                        // and breaking after each one would split words like "équivaut" into "é" + "quivaut"
                        // Line breaking is handled in the regular .ordinary case below

                        // Add to atom list
                        if currentLineIndexRange.location == NSNotFound {
                            currentLineIndexRange = atom.indexRange
                        } else {
                            currentLineIndexRange.length += atom.indexRange.length
                        }
                        currentAtoms.append(atom)

                        // Treat accent as ordinary for spacing purposes
                        atom.type = .ordinary
                    } else {
                        // Original behavior when no width constraint
                        // Check if we need to break the line due to width constraints
                        self.checkAndBreakLine()
                        // stash the existing layout
                        if currentLine.length > 0 {
                            self.addDisplayLine()
                        }
                        // Accent is considered as Ord in rule 16.
                        self.addInterElementSpace(prevNode, currentType:.ordinary)
                        atom.type = .ordinary;

                        let accent = atom as! MTAccent?
                        let display = self.makeAccent(accent)
                        
                        // Only add if display was successfully created
                        if let accentDisplay = display {
                            displayAtoms.append(accentDisplay)
                            currentPosition.x += accentDisplay.width;

                            // add super scripts || subscripts
                            if atom.subScript != nil || atom.superScript != nil {
                                let scriptContext = MTRenderContext(
                                    font: font,
                                    styleFont: styleFont,
                                    style: style,
                                    cramped: cramped,
                                    spaced: spaced,
                                    maxWidth: maxWidth,
                                    position: currentPosition
                                )
                                scriptRenderer.makeScripts(atom, display: accentDisplay, index: UInt(atom.indexRange.location), delta: 0, context: scriptContext, typesetter: self)
                            }
                        }
                    }
                    
                case .table:
                    // Create the table display first
                    guard let table = atom as? MTMathTable,
                          let display = self.makeTable(table) else {
                        continue
                    }

                    // Check if we need to break before adding this table
                    // We will consider tables as inner
                    let shouldBreak = shouldBreakBeforeDisplay(display, prevNode: prevNode, displayType: .inner)

                    // Flush current line to convert accumulated text to displays
                    if currentLine.length > 0 {
                        self.addDisplayLine()
                    }

                    // Perform line break if needed
                    if shouldBreak {
                        performLineBreak()
                    } else {
                        self.addInterElementSpace(prevNode, currentType:.inner)
                    }
                    atom.type = .inner

                    display.position = currentPosition
                    displayAtoms.append(display)
                    currentPosition.x += display.width
                    // A table doesn't have subscripts or superscripts
                    
                case .ordinary, .binaryOperator, .relation, .open, .close, .placeholder, .punctuation:
                    // the rendering for all the rest is pretty similar
                    // All we need is render the character and set the interelement space.

                    // INTERATOM LINE BREAKING: Check if we need to break before adding this atom
                    // Pass nextAtoms for look-ahead to find better break points
                    checkAndPerformInteratomLineBreak(atom, prevNode: prevNode, nextAtoms: nextAtoms)

                    if let prevNode = prevNode {
                        let interElementSpace = self.getInterElementSpace(prevNode.type, right:atom.type)
                        if currentLine.length > 0 {
                            if interElementSpace > 0 {
                                // add a kerning of that space to the previous character
                                currentLine.addAttribute(kCTKernAttributeName as NSAttributedString.Key,
                                                         value:NSNumber(floatLiteral: interElementSpace),
                                                         range:currentLine.mutableString.rangeOfComposedCharacterSequence(at: currentLine.length-1))
                            }
                        } else {
                            // increase the space
                            currentPosition.x += interElementSpace
                        }
                    }
                    var current:NSAttributedString? = nil
                    if atom.type == .placeholder {
                        let color = MTTypesetter.placeholderColor
                        current = NSAttributedString(string:atom.nucleus,
                                                     attributes:[kCTForegroundColorAttributeName as NSAttributedString.Key : color.cgColor])
                    } else {
                        current = NSAttributedString(string:atom.nucleus)
                    }

                    currentLine.append(current!)

                    // Universal line breaking: only for simple atoms (no scripts)
                    // This works for text, mixed text+math, and simple equations
                    let isSimpleAtom = (atom.subScript == nil && atom.superScript == nil)

                    if isSimpleAtom && maxWidth > 0 {
                        // Measure the current line width
                        let attrString = currentLine.mutableCopy() as! NSMutableAttributedString
                        attrString.addAttribute(kCTFontAttributeName as NSAttributedString.Key, value:styleFont.ctFont as Any, range:NSMakeRange(0, attrString.length))
                        let ctLine = CTLineCreateWithAttributedString(attrString)
                        let segmentWidth = CGFloat(CTLineGetTypographicBounds(ctLine, nil, nil, nil))

                        // IMPORTANT: Account for currentPosition.x to get the true visual line width
                        // After superscripts/subscripts, currentPosition.x > 0 because previous segments
                        // have been rendered and flushed
                        let visualLineWidth = currentPosition.x + segmentWidth

                        if visualLineWidth > maxWidth {
                            // Line is too wide - need to find a break point
                            let currentText = currentLine.string

                            // Use Unicode-aware line breaking with number protection
                            // IMPORTANT: Use remaining width, not full maxWidth, because currentPosition.x
                            // may be > 0 if we've already rendered segments on this visual line
                            let remainingWidth = max(0, maxWidth - currentPosition.x)
                            if let breakIndex = findBestBreakPoint(in: currentText, font: styleFont.ctFont, maxWidth: remainingWidth) {
                                // Split the line at the suggested break point
                                let breakOffset = currentText.distance(from: currentText.startIndex, to: breakIndex)

                                // Create attributed string for the first line
                                let firstLine = NSMutableAttributedString(string: String(currentText.prefix(breakOffset)))
                                firstLine.addAttribute(kCTFontAttributeName as NSAttributedString.Key, value:styleFont.ctFont as Any, range:NSMakeRange(0, firstLine.length))

                                // Check if first line still exceeds remaining width - need to find earlier break point
                                let firstLineCT = CTLineCreateWithAttributedString(firstLine)
                                let firstLineWidth = CGFloat(CTLineGetTypographicBounds(firstLineCT, nil, nil, nil))

                                if firstLineWidth > remainingWidth {
                                    // Need to break earlier - find previous break point
                                    let firstLineText = firstLine.string
                                    if let earlierBreakIndex = findBestBreakPoint(in: firstLineText, font: styleFont.ctFont, maxWidth: remainingWidth) {
                                        let earlierOffset = firstLineText.distance(from: firstLineText.startIndex, to: earlierBreakIndex)
                                        let earlierLine = NSMutableAttributedString(string: String(firstLineText.prefix(earlierOffset)))
                                        earlierLine.addAttribute(kCTFontAttributeName as NSAttributedString.Key, value:styleFont.ctFont as Any, range:NSMakeRange(0, earlierLine.length))

                                        // Flush the earlier line
                                        currentLine = earlierLine
                                        currentAtoms = []  // Approximate - we're splitting
                                        self.addDisplayLine()

                                        // Reset optimization flag after line break
                                        remainingContentFits = false

                                        // Calculate dynamic line height and move down for new line
                                        let lineHeight = calculateCurrentLineHeight()
                                        currentPosition.y -= lineHeight
                                        currentPosition.x = 0
                                        currentLineStartIndex = displayAtoms.count

                                        // Remaining text includes everything after the earlier break
                                        let remainingText = String(firstLineText.suffix(from: earlierBreakIndex)) +
                                                          String(currentText.suffix(from: breakIndex))
                                        currentLine = NSMutableAttributedString(string: remainingText)
                                        currentAtoms = []
                                        currentLineIndexRange = NSMakeRange(NSNotFound, NSNotFound)
                                    }
                                } else {
                                    // First line fits - proceed with normal wrapping
                                    // Keep track of atoms that belong to the first line
                                    let firstLineAtoms = currentAtoms

                                    // Flush the first line
                                    currentLine = firstLine
                                    currentAtoms = firstLineAtoms
                                    self.addDisplayLine()

                                    // Reset optimization flag after line break
                                    remainingContentFits = false

                                    // Calculate dynamic line height and move down for new line
                                    let lineHeight = calculateCurrentLineHeight()
                                    currentPosition.y -= lineHeight
                                    currentPosition.x = 0
                                    currentLineStartIndex = displayAtoms.count

                                    // Start the new line with the content after the break
                                    let remainingText = String(currentText.suffix(from: breakIndex))
                                    currentLine = NSMutableAttributedString(string: remainingText)

                                    // Reset atom list for new line
                                    currentAtoms = []
                                    currentLineIndexRange = NSMakeRange(NSNotFound, NSNotFound)
                                }
                            }
                            // If no break point found, let it overflow (better than breaking mid-word)
                        }
                    }

                    // Check if atom with scripts would exceed width constraint (improved script handling)
                    if maxWidth > 0 && (atom.subScript != nil || atom.superScript != nil) && currentLine.length > 0 {
                        // Estimate width including scripts
                        let atomWidthWithScripts = estimateAtomWidthWithScripts(atom)
                        let interElementSpace = self.getInterElementSpace(prevNode?.type ?? .ordinary, right: atom.type)
                        let currentWidth = getCurrentLineWidth()
                        let projectedWidth = currentWidth + interElementSpace + atomWidthWithScripts

                        // If adding this scripted atom would exceed width, break line first
                        if projectedWidth > maxWidth {
                            self.addDisplayLine()
                            let lineHeight = calculateCurrentLineHeight()
                            currentPosition.y -= lineHeight
                            currentPosition.x = 0
                            currentLineStartIndex = displayAtoms.count
                        }
                    }

                    // add the atom to the current range
                    if currentLineIndexRange.location == NSNotFound {
                        currentLineIndexRange = atom.indexRange
                    } else {
                        currentLineIndexRange.length += atom.indexRange.length
                    }
                    // add the fused atoms
                    if !atom.fusedAtoms.isEmpty {
                        currentAtoms.append(contentsOf: atom.fusedAtoms)  //.addObjectsFromArray:atom.fusedAtoms)
                    } else {
                        currentAtoms.append(atom)
                    }

                    // add super scripts || subscripts
                    if atom.subScript != nil || atom.superScript != nil {
                        // stash the existing line
                        // We don't check currentLine.length here since we want to allow empty lines with super/sub scripts.
                        let line = self.addDisplayLine()
                        var delta = CGFloat(0)
                        if !atom.nucleus.isEmpty,
                           let mathTable = styleFont.mathTable {
                            // Use the italic correction of the last character.
                            let index = atom.nucleus.index(before: atom.nucleus.endIndex)
                            let glyph = self.findGlyphForCharacterAtIndex(index, inString:atom.nucleus)
                            delta = mathTable.getItalicCorrection(glyph)
                        }
                        if delta > 0 && atom.subScript == nil {
                            // Add a kern of delta
                            currentPosition.x += delta;
                        }
                        let scriptContext = MTRenderContext(
                            font: font,
                            styleFont: styleFont,
                            style: style,
                            cramped: cramped,
                            spaced: spaced,
                            maxWidth: maxWidth,
                            position: currentPosition
                        )
                        scriptRenderer.makeScripts(atom, display: line, index: UInt(NSMaxRange(atom.indexRange) - 1), delta: delta, context: scriptContext, typesetter: self)
                    }
            } // switch
            lastType = atom.type
            prevNode = atom
        } // node loop
        if currentLine.length > 0 {
            self.addDisplayLine()
        }
        if spaced && lastType != nil {
            // If spaced then add an interelement space between the last type and close
            let display = displayAtoms.last
            let interElementSpace = self.getInterElementSpace(lastType, right:.close)
            display?.width += interElementSpace
        }
    }

    // MARK: - Unicode-aware Line Breaking

    /// Find the best break point using Core Text, with conservative number protection
    func findBestBreakPoint(in text: String, font: CTFont, maxWidth: CGFloat) -> String.Index? {
        let attributes: [NSAttributedString.Key: Any] = [kCTFontAttributeName as NSAttributedString.Key: font]
        let attrString = NSAttributedString(string: text, attributes: attributes)
        let typesetter = CTTypesetterCreateWithAttributedString(attrString as CFAttributedString)
        let suggestedBreak = CTTypesetterSuggestLineBreak(typesetter, 0, Double(maxWidth))

        guard suggestedBreak > 0 else {
            return nil
        }

        // IMPORTANT: CTTypesetterSuggestLineBreak returns a UTF-16 code unit offset,
        // but Swift String.Index works with Unicode extended grapheme clusters.
        // We must convert from UTF-16 space to String.Index properly to avoid
        // breaking in the middle of Unicode characters (like "é" in "équivaut").

        // Convert UTF-16 offset to String.Index
        guard let utf16Index = text.utf16.index(text.utf16.startIndex, offsetBy: suggestedBreak, limitedBy: text.utf16.endIndex),
              let breakIndex = String.Index(utf16Index, within: text) else {
            return nil
        }

        // Conservative check: verify we're not breaking within a number
        if isBreakingSafeForNumbers(text: text, breakIndex: breakIndex) {
            return breakIndex
        }

        // If the suggested break would split a number, find the previous safe break point
        return findPreviousSafeBreak(in: text, before: breakIndex)
    }

    /// Check if breaking at this index would split a number
    func isBreakingSafeForNumbers(text: String, breakIndex: String.Index) -> Bool {
        guard breakIndex > text.startIndex && breakIndex < text.endIndex else {
            return true
        }

        // Check a small window around the break point
        let beforeIndex = text.index(before: breakIndex)
        let charBefore = text[beforeIndex]
        let charAfter = text[breakIndex]

        // Number separators in various locales
        let numberSeparators: Set<Character> = [
            ".", ",",           // Decimal/thousands (EN/FR)
            "'",                // Thousands (CH)
            "\u{00A0}",        // Non-breaking space (FR thousands)
            "\u{2009}",        // Thin space (sometimes used)
            "\u{202F}"         // Narrow no-break space (FR)
        ]

        // Pattern 1: digit + separator + digit (e.g., "3.14" or "3,14")
        if charBefore.isNumber && numberSeparators.contains(charAfter) {
            // Check if there's a digit after the separator
            let nextIndex = text.index(after: breakIndex)
            if nextIndex < text.endIndex && text[nextIndex].isNumber {
                return false  // Don't break: this looks like "3.|14"
            }
        }

        // Pattern 2: separator + digit, check if previous is digit
        if numberSeparators.contains(charBefore) && charAfter.isNumber {
            // Check if there's a digit before the separator
            if beforeIndex > text.startIndex {
                let prevIndex = text.index(before: beforeIndex)
                if text[prevIndex].isNumber {
                    return false  // Don't break: this looks like "3,|14"
                }
            }
        }

        // Pattern 3: digit + digit (shouldn't happen with CTTypesetter, but be safe)
        if charBefore.isNumber && charAfter.isNumber {
            return false  // Don't break within consecutive digits
        }

        // Pattern 4: digit + space + digit (French: "1 000 000")
        if charBefore.isNumber && charAfter.isWhitespace {
            let nextIndex = text.index(after: breakIndex)
            if nextIndex < text.endIndex && text[nextIndex].isNumber {
                return false  // Don't break: this looks like "1 |000"
            }
        }

        return true  // Safe to break
    }

    /// Find previous safe break point before the given index
    func findPreviousSafeBreak(in text: String, before breakIndex: String.Index) -> String.Index? {
        var currentIndex = breakIndex

        // Walk backwards to find a space or safe break
        while currentIndex > text.startIndex {
            currentIndex = text.index(before: currentIndex)

            // Prefer breaking at whitespace (safest option)
            if text[currentIndex].isWhitespace {
                return text.index(after: currentIndex)  // Break after the space
            }

            // Check if this would be safe
            if isBreakingSafeForNumbers(text: text, breakIndex: currentIndex) {
                return currentIndex
            }
        }

        return nil
    }

    /// Check if the current line exceeds maxWidth and break if needed
    func checkAndBreakLine() {
        guard maxWidth > 0 && currentLine.length > 0 else { return }

        // Measure the current line width
        let attrString = currentLine.mutableCopy() as! NSMutableAttributedString
        attrString.addAttribute(kCTFontAttributeName as NSAttributedString.Key, value:styleFont.ctFont as Any, range:NSMakeRange(0, attrString.length))
        let ctLine = CTLineCreateWithAttributedString(attrString)
        let lineWidth = CGFloat(CTLineGetTypographicBounds(ctLine, nil, nil, nil))

        guard lineWidth > maxWidth else { return }

        // Line is too wide - need to find a break point
        let currentText = currentLine.string

        // Use Unicode-aware line breaking with number protection
        if let breakIndex = findBestBreakPoint(in: currentText, font: styleFont.ctFont, maxWidth: maxWidth) {
            // Split the line at the suggested break point
            let breakOffset = currentText.distance(from: currentText.startIndex, to: breakIndex)

            // Create attributed string for the first line
            let firstLine = NSMutableAttributedString(string: String(currentText.prefix(breakOffset)))
            firstLine.addAttribute(kCTFontAttributeName as NSAttributedString.Key, value:styleFont.ctFont as Any, range:NSMakeRange(0, firstLine.length))

            // Check if first line still exceeds maxWidth - need to find earlier break point
            let firstLineCT = CTLineCreateWithAttributedString(firstLine)
            let firstLineWidth = CGFloat(CTLineGetTypographicBounds(firstLineCT, nil, nil, nil))

            if firstLineWidth > maxWidth {
                // Need to break earlier - find previous break point
                let firstLineText = firstLine.string
                if let earlierBreakIndex = findBestBreakPoint(in: firstLineText, font: styleFont.ctFont, maxWidth: maxWidth) {
                    let earlierOffset = firstLineText.distance(from: firstLineText.startIndex, to: earlierBreakIndex)
                    let earlierLine = NSMutableAttributedString(string: String(firstLineText.prefix(earlierOffset)))
                    earlierLine.addAttribute(kCTFontAttributeName as NSAttributedString.Key, value:styleFont.ctFont as Any, range:NSMakeRange(0, earlierLine.length))

                    // Flush the earlier line
                    currentLine = earlierLine
                    currentAtoms = []
                    self.addDisplayLine()

                    // Calculate dynamic line height and move down for new line
                    let lineHeight = calculateCurrentLineHeight()
                    currentPosition.y -= lineHeight
                    currentPosition.x = 0
                    currentLineStartIndex = displayAtoms.count

                    // Remaining text includes everything after the earlier break
                    let remainingText = String(firstLineText.suffix(from: earlierBreakIndex)) +
                                      String(currentText.suffix(from: breakIndex))
                    currentLine = NSMutableAttributedString(string: remainingText)
                    currentAtoms = []
                    currentLineIndexRange = NSMakeRange(NSNotFound, NSNotFound)
                    return
                }
            }

            // Keep track of atoms that belong to the first line
            let firstLineAtoms = currentAtoms

            // Flush the first line
            currentLine = firstLine
            currentAtoms = firstLineAtoms
            self.addDisplayLine()

            // Calculate dynamic line height and move down for new line
            let lineHeight = calculateCurrentLineHeight()
            currentPosition.y -= lineHeight
            currentPosition.x = 0
            currentLineStartIndex = displayAtoms.count

            // Start the new line with the content after the break
            let remainingText = String(currentText.suffix(from: breakIndex))
            currentLine = NSMutableAttributedString(string: remainingText)

            // Reset atom list for new line
            currentAtoms = []
            currentLineIndexRange = NSMakeRange(NSNotFound, NSNotFound)
        }
    }

    @discardableResult
    func addDisplayLine() -> MTCTLineDisplay? {
        // add the font
        currentLine.addAttribute(kCTFontAttributeName as NSAttributedString.Key, value:styleFont.ctFont as Any, range:NSMakeRange(0, currentLine.length))
        /*assert(currentLineIndexRange.length == numCodePoints(currentLine.string),
         "The length of the current line: %@ does not match the length of the range (%d, %d)",
         currentLine, currentLineIndexRange.location, currentLineIndexRange.length);*/
        
        let displayAtom = MTCTLineDisplay(withString:currentLine, position:currentPosition, range:currentLineIndexRange, font:styleFont, atoms:currentAtoms)
        self.displayAtoms.append(displayAtom)
        // update the position
        currentPosition.x += displayAtom.width;
        // clear the string and the range
        currentLine = NSMutableAttributedString()
        currentAtoms = [MTMathAtom]()
        currentLineIndexRange = NSMakeRange(NSNotFound, NSNotFound)
        return displayAtom
    }
    
    // MARK: - Spacing
    
    // Returned in units of mu = 1/18 em.
    func getSpacingInMu(_ type: InterElementSpaceType) -> Int {
        // let valid = [MTLineStyle.display, .text]
        switch type {
            case .invalid:  return -1
            case .none:     return 0
            case .thin:     return 3
            case .nsThin:   return style.isNotScript ? 3 : 0;
            case .nsMedium: return style.isNotScript ? 4 : 0;
            case .nsThick:  return style.isNotScript ? 5 : 0;
        }
    }
    
    func getInterElementSpace(_ left: MTMathAtomType, right:MTMathAtomType) -> CGFloat {
        let leftIndex = getInterElementSpaceArrayIndexForType(left, row: true)
        let rightIndex = getInterElementSpaceArrayIndexForType(right, row: false)
        let spaceArray = getInterElementSpaces()[Int(leftIndex)]
        let spaceTypeObj = spaceArray[Int(rightIndex)]
        let spaceType = spaceTypeObj
        assert(spaceType != .invalid, "Invalid space between \(left) and \(right)")
        
        let spaceMultipler = self.getSpacingInMu(spaceType)
        if spaceMultipler > 0, let mathTable = styleFont.mathTable {
            // 1 em = size of font in pt. space multipler is in multiples mu or 1/18 em
            return CGFloat(spaceMultipler) * mathTable.muUnit
        }
        return 0
    }
    
    // MARK: - Subscript/Superscript
    // NOTE: Main script rendering logic has been extracted to MTScriptRenderer
    // Helper methods remain here for use in other parts of the typesetter
    
    func scriptStyle() -> MTLineStyle {
        switch style {
            case .display, .text:          return .script
            case .script, .scriptOfScript: return .scriptOfScript
        }
    }
    
    // subscript is always cramped
    func subscriptCramped() -> Bool { true }
    
    // superscript is cramped only if the current style is cramped
    func superScriptCramped() -> Bool { cramped }
    
    // MARK: - Fractions
    
    func numeratorShiftUp(_ hasRule:Bool) -> CGFloat {
        guard let mathTable = styleFont.mathTable else { return 0 }
        if hasRule {
            if style == .display {
                return mathTable.fractionNumeratorDisplayStyleShiftUp
            } else {
                return mathTable.fractionNumeratorShiftUp
            }
        } else {
            if style == .display {
                return mathTable.stackTopDisplayStyleShiftUp
            } else {
                return mathTable.stackTopShiftUp
            }
        }
    }
    
    func numeratorGapMin() -> CGFloat {
        guard let mathTable = styleFont.mathTable else { return 0 }
        if style == .display {
            return mathTable.fractionNumeratorDisplayStyleGapMin;
        } else {
            return mathTable.fractionNumeratorGapMin;
        }
    }
    
    func denominatorShiftDown(_ hasRule:Bool) -> CGFloat {
        guard let mathTable = styleFont.mathTable else { return 0 }
        if hasRule {
            if style == .display {
                return mathTable.fractionDenominatorDisplayStyleShiftDown;
            } else {
                return mathTable.fractionDenominatorShiftDown;
            }
        } else {
            if style == .display {
                return mathTable.stackBottomDisplayStyleShiftDown;
            } else {
                return mathTable.stackBottomShiftDown;
            }
        }
    }
    
    func denominatorGapMin() -> CGFloat {
        guard let mathTable = styleFont.mathTable else { return 0 }
        if style == .display {
            return mathTable.fractionDenominatorDisplayStyleGapMin;
        } else {
            return mathTable.fractionDenominatorGapMin;
        }
    }
    
    func stackGapMin() -> CGFloat {
        guard let mathTable = styleFont.mathTable else { return 0 }
        if style == .display {
            return mathTable.stackDisplayStyleGapMin;
        } else {
            return mathTable.stackGapMin;
        }
    }
    
    func fractionDelimiterHeight()-> CGFloat {
        guard let mathTable = styleFont.mathTable else { return 0 }
        if style == .display {
            return mathTable.fractionDelimiterDisplayStyleSize;
        } else {
            return mathTable.fractionDelimiterSize;
        }
    }
    
    func fractionStyle() -> MTLineStyle {
        // Keep fractions at the same style level instead of incrementing.
        // This ensures that fraction numerators/denominators have the same
        // font size as regular text, preventing them from appearing too small
        // in inline mode or when nested.
        return style
    }
    
    func makeFraction(_ frac:MTFraction?) -> MTDisplay? {
        guard let frac = frac else { return nil }
        
        // lay out the parts of the fraction
        let numeratorStyle: MTLineStyle
        let denominatorStyle: MTLineStyle

        if frac.isContinuedFraction {
            // Continued fractions always use display style
            numeratorStyle = .display
            denominatorStyle = .display
        } else {
            // Regular fractions use adaptive style
            let fractionStyle = self.fractionStyle;
            numeratorStyle = fractionStyle()
            denominatorStyle = fractionStyle()
        }

        guard let numeratorDisplay = MTTypesetter.createLineForMathList(frac.numerator, font:font, style:numeratorStyle, cramped:false),
              let denominatorDisplay = MTTypesetter.createLineForMathList(frac.denominator, font:font, style:denominatorStyle, cramped:true),
              let mathTable = styleFont.mathTable else {
            return nil
        }
        
        // determine the location of the numerator
        var numeratorShiftUp = self.numeratorShiftUp(frac.hasRule)
        var denominatorShiftDown = self.denominatorShiftDown(frac.hasRule)
        let barLocation = mathTable.axisHeight
        let barThickness = frac.hasRule ? mathTable.fractionRuleThickness : 0
        
        if frac.hasRule {
            // This is the difference between the lowest edge of the numerator and the top edge of the fraction bar
            let distanceFromNumeratorToBar = (numeratorShiftUp - numeratorDisplay.descent) - (barLocation + barThickness/2);
            // The distance should at least be displayGap
            let minNumeratorGap = self.numeratorGapMin;
            if distanceFromNumeratorToBar < minNumeratorGap() {
                // This makes the distance between the bottom of the numerator and the top edge of the fraction bar
                // at least minNumeratorGap.
                numeratorShiftUp += (minNumeratorGap() - distanceFromNumeratorToBar);
            }
            
            // Do the same for the denominator
            // This is the difference between the top edge of the denominator and the bottom edge of the fraction bar
            let distanceFromDenominatorToBar = (barLocation - barThickness/2) - (denominatorDisplay.ascent - denominatorShiftDown);
            // The distance should at least be denominator gap
            let minDenominatorGap = self.denominatorGapMin;
            if distanceFromDenominatorToBar < minDenominatorGap() {
                // This makes the distance between the top of the denominator and the bottom of the fraction bar to be exactly
                // minDenominatorGap
                denominatorShiftDown += (minDenominatorGap() - distanceFromDenominatorToBar);
            }
        } else {
            // This is the distance between the numerator and the denominator
            let clearance = (numeratorShiftUp - numeratorDisplay.descent) - (denominatorDisplay.ascent - denominatorShiftDown);
            // This is the minimum clearance between the numerator and denominator.
            let minGap = self.stackGapMin()
            if clearance < minGap {
                numeratorShiftUp += (minGap - clearance)/2;
                denominatorShiftDown += (minGap - clearance)/2;
            }
        }
        
        let display = MTFractionDisplay(withNumerator: numeratorDisplay, denominator: denominatorDisplay, position: currentPosition, range: frac.indexRange)
        
        display.numeratorUp = numeratorShiftUp;
        display.denominatorDown = denominatorShiftDown;
        display.lineThickness = barThickness;
        display.linePosition = barLocation;
        if frac.leftDelimiter.isEmpty && frac.rightDelimiter.isEmpty {
            return display
        } else {
            return self.addDelimitersToFractionDisplay(display, forFraction:frac)
        }
    }
    
    func addDelimitersToFractionDisplay(_ display:MTFractionDisplay?, forFraction frac:MTFraction?) -> MTDisplay? {
        guard let frac = frac, let display = display else { return nil }
        assert(!frac.leftDelimiter.isEmpty || !frac.rightDelimiter.isEmpty, "Fraction should have a delimiters to call this function");
        
        var innerElements = [MTDisplay]()
        let glyphHeight = self.fractionDelimiterHeight
        var position = CGPoint.zero
        if !frac.leftDelimiter.isEmpty {
            guard let leftGlyph = self.findGlyphForBoundary(frac.leftDelimiter, withHeight:glyphHeight()) else {
                return nil
            }
            leftGlyph.position = position
            position.x += leftGlyph.width
            innerElements.append(leftGlyph)
        }
        
        display.position = position
        position.x += display.width
        innerElements.append(display)
        
        if !frac.rightDelimiter.isEmpty {
            guard let rightGlyph = self.findGlyphForBoundary(frac.rightDelimiter, withHeight:glyphHeight()) else {
                return nil
            }
            rightGlyph.position = position
            position.x += rightGlyph.width
            innerElements.append(rightGlyph)
        }
        let innerDisplay = MTMathListDisplay(withDisplays: innerElements, range: frac.indexRange)
        innerDisplay.position = currentPosition
        return innerDisplay
    }
    
    // MARK: - Radicals
    
    /// Returns vertical gap above radicand according to TeX Appendix G, Rule 11.
    ///
    /// ## TeX Rule 11: Radical Construction
    /// "The radical sign √ is constructed to cover its contents with appropriate
    /// vertical clearance above and rule thickness."
    ///
    /// ### TeX Parameters:
    /// - Display style: Uses `radicalDisplayStyleVerticalGap` (larger gap)
    /// - Other styles: Uses `radicalVerticalGap` (smaller gap)
    ///
    /// This ensures proper spacing between radical symbol and content.
    ///
    /// - Returns: Vertical gap in points
    func radicalVerticalGap() -> CGFloat {
        guard let mathTable = styleFont.mathTable else { return 0 }
        
        if style == .display {
            return mathTable.radicalDisplayStyleVerticalGap
        } else {
            return mathTable.radicalVerticalGap
        }
    }
    
    /// Constructs a radical glyph of specified height using TeX Rule 11.
    ///
    /// ## TeX Rule 11 (continued): Glyph Selection
    /// 1. **Find base glyph**: Start with U+221A (SQUARE ROOT)
    /// 2. **Check variants**: Try progressively larger pre-composed glyphs
    /// 3. **Construct if needed**: If no single glyph is large enough,
    ///    assemble from extender pieces
    ///
    /// ### Glyph Assembly:
    /// - Uses OpenType MATH GlyphAssembly table
    /// - Combines: top piece + extenders + bottom piece
    /// - Adjusts connector overlaps for seamless appearance
    ///
    /// - Parameter radicalHeight: Target height in points
    /// - Returns: Glyph display of appropriate size or nil
    func getRadicalGlyphWithHeight(_ radicalHeight:CGFloat) -> MTDisplayDS? {
        var glyphAscent=CGFloat(0), glyphDescent=CGFloat(0), glyphWidth=CGFloat(0)
        
        let radicalGlyph = self.findGlyphForCharacterAtIndex("\u{221A}".startIndex, inString:"\u{221A}")
        let glyph = self.findGlyph(radicalGlyph, withHeight:radicalHeight, glyphAscent:&glyphAscent, glyphDescent:&glyphDescent, glyphWidth:&glyphWidth)
        
        var glyphDisplay:MTDisplayDS?
        if glyphAscent + glyphDescent < radicalHeight {
            // the glyphs is not as large as required. A glyph needs to be constructed using the extenders.
            glyphDisplay = self.constructGlyph(radicalGlyph, withHeight:radicalHeight)
        }
        
        if glyphDisplay == nil {
            // No constructed display so use the glyph we got.
            glyphDisplay = MTGlyphDisplay(withGlpyh: glyph, range: NSMakeRange(NSNotFound, 0), font:styleFont)
            if let display = glyphDisplay {
                display.ascent = glyphAscent;
                display.descent = glyphDescent;
                display.width = glyphWidth;
            }
        }
        return glyphDisplay;
    }
    
    func makeRadical(_ radicand:MTMathList?, range:NSRange) -> MTRadicalDisplay? {
        guard let mathTable = styleFont.mathTable,
              let innerDisplay = MTTypesetter.createLineForMathList(radicand, font:font, style:style, cramped:true),
              let glyph = self.getRadicalGlyphWithHeight(innerDisplay.ascent + innerDisplay.descent + self.radicalVerticalGap() + mathTable.radicalRuleThickness) else {
            return nil
        }
        
        var clearance = self.radicalVerticalGap()
        let radicalRuleThickness = mathTable.radicalRuleThickness
        
        // Note this is a departure from Latex. Latex assumes that glyphAscent == thickness.
        // Open type math makes no such assumption, and ascent and descent are independent of the thickness.
        // Latex computes delta as descent - (h(inner) + d(inner) + clearance)
        // but since we may not have ascent == thickness, we modify the delta calculation slightly.
        // If the font designer followes Latex conventions, it will be identical.
        let delta = (glyph.descent + glyph.ascent) - (innerDisplay.ascent + innerDisplay.descent + clearance + radicalRuleThickness)
        if delta > 0 {
            clearance += delta/2  // increase the clearance to center the radicand inside the sign.
        }
        
        // we need to shift the radical glyph up, to coincide with the baseline of inner.
        // The new ascent of the radical glyph should be thickness + adjusted clearance + h(inner)
        let radicalAscent = radicalRuleThickness + clearance + innerDisplay.ascent
        let shiftUp = radicalAscent - glyph.ascent  // Note: if the font designer followed latex conventions, this is the same as glyphAscent == thickness.
        glyph.shiftDown = -shiftUp
        
        let radical = MTRadicalDisplay(withRadicand: innerDisplay, glyph: glyph, position: currentPosition, range: range)
        radical.ascent = radicalAscent + mathTable.radicalExtraAscender
        radical.topKern = mathTable.radicalExtraAscender
        radical.lineThickness = radicalRuleThickness
        // Note: Until we have radical construction from parts, it is possible that glyphAscent+glyphDescent is less
        // than the requested height of the glyph (i.e. radicalHeight), so in the case the innerDisplay has a larger
        // descent we use the innerDisplay's descent.
        radical.descent = max(glyph.ascent + glyph.descent - radicalAscent, innerDisplay.descent)
        radical.width = glyph.width + innerDisplay.width
        return radical
    }
    
    // MARK: - Glyphs
    
    func findGlyph(_ glyph:CGGlyph, withHeight height:CGFloat, glyphAscent:inout CGFloat, glyphDescent:inout CGFloat, glyphWidth:inout CGFloat) -> CGGlyph {
        guard let mathTable = styleFont.mathTable else {
            // Fallback: return original glyph with default metrics
            glyphAscent = 0
            glyphDescent = 0
            glyphWidth = 0
            return glyph
        }
        
        let variants = mathTable.getVerticalVariantsForGlyph(glyph)
        let numVariants = variants.count;
        var glyphs = [CGGlyph]()// numVariants)
        glyphs.reserveCapacity(numVariants)
        for i in 0 ..< numVariants {
            guard let variant = variants[i] else { continue }
            let glyph = variant.uint16Value
            glyphs.append(glyph)
        }
        
        var bboxes = [CGRect](repeating: CGRect.zero, count: numVariants)
        var advances = [CGSize](repeating: CGSize.zero, count: numVariants)
        
        // Get the bounds for these glyphs
        CTFontGetBoundingRectsForGlyphs(styleFont.ctFont, .horizontal, glyphs, &bboxes, numVariants)
        CTFontGetAdvancesForGlyphs(styleFont.ctFont, .horizontal, glyphs, &advances, numVariants);
        var ascent=CGFloat(0), descent=CGFloat(0), width=CGFloat(0)
        for i in 0..<numVariants {
            let bounds = bboxes[i]
            width = advances[i].width;
            getBboxDetails(bounds, ascent: &ascent, descent: &descent);
            
            if (ascent + descent >= height) {
                glyphAscent = ascent;
                glyphDescent = descent;
                glyphWidth = width;
                return glyphs[i]
            }
        }
        glyphAscent = ascent;
        glyphDescent = descent;
        glyphWidth = width;
        return glyphs[numVariants - 1]
    }
    
    func constructGlyph(_ glyph:CGGlyph, withHeight glyphHeight:CGFloat) -> MTGlyphConstructionDisplay? {
        guard let mathTable = styleFont.mathTable else {
            return nil
        }
        
        let parts = mathTable.getVerticalGlyphAssembly(forGlyph: glyph)
        if parts.count == 0 {
            return nil
        }
        var glyphs = [NSNumber](), offsets = [NSNumber]()
        var height:CGFloat=0
        self.constructGlyphWithParts(parts, glyphHeight:glyphHeight, glyphs:&glyphs, offsets:&offsets, height:&height)
        var first = glyphs[0].uint16Value
        let width = CTFontGetAdvancesForGlyphs(styleFont.ctFont, .horizontal, &first, nil, 1);
        let display = MTGlyphConstructionDisplay(withGlyphs: glyphs, offsets: offsets, font: styleFont)
        display.width = width;
        display.ascent = height;
        display.descent = 0;   // it's upto the rendering to adjust the display up or down.
        return display;
    }
    
    func constructGlyphWithParts(_ parts:[GlyphPart], glyphHeight:CGFloat, glyphs:inout [NSNumber], offsets:inout [NSNumber], height:inout CGFloat) {
        guard let mathTable = styleFont.mathTable else {
            // Fallback: set height to 0 and return
            height = 0
            return
        }
        
        // Loop forever until the glyph height is valid
        for numExtenders in 0..<Int.max {
            var glyphsRv = [NSNumber]()
            var offsetsRv = [NSNumber]()
            
            var prev:GlyphPart? = nil;
            let minDistance = mathTable.minConnectorOverlap;
            var minOffset = CGFloat(0)
            var maxDelta = CGFloat.greatestFiniteMagnitude  // the maximum amount we can increase the offsets by
            
            for part in parts {
                var repeats = 1;
                if part.isExtender {
                    repeats = numExtenders;
                }
                // add the extender num extender times
                for _ in 0 ..< repeats {
                    glyphsRv.append(NSNumber(value: part.glyph)) // addObject:[NSNumber numberWithShort:part.glyph])
                    if let prev = prev {
                        let maxOverlap = min(prev.endConnectorLength, part.startConnectorLength);
                        // the minimum amount we can add to the offset
                        let minOffsetDelta = prev.fullAdvance - maxOverlap;
                        // The maximum amount we can add to the offset.
                        let maxOffsetDelta = prev.fullAdvance - minDistance;
                        // we can increase the offsets by at most max - min.
                        maxDelta = min(maxDelta, maxOffsetDelta - minOffsetDelta);
                        minOffset = minOffset + minOffsetDelta;
                    }
                    offsetsRv.append(NSNumber(floatLiteral: minOffset))  // addObject:[NSNumber numberWithFloat:minOffset])
                    prev = part
                }
            }
            
            assert(glyphsRv.count == offsetsRv.count, "Offsets should match the glyphs");
            guard let prev = prev else {
                continue;   // maybe only extenders
            }
            let minHeight = minOffset + prev.fullAdvance
            let maxHeight = minHeight + maxDelta * CGFloat(glyphsRv.count - 1)
            if (minHeight >= glyphHeight) {
                // we are done
                glyphs = glyphsRv;
                offsets = offsetsRv;
                height = minHeight;
                return;
            } else if (glyphHeight <= maxHeight) {
                // spread the delta equally between all the connectors
                let delta = glyphHeight - minHeight;
                let deltaIncrease = Float(delta) / Float(glyphsRv.count - 1)
                var lastOffset = CGFloat(0)
                for i in 0..<offsetsRv.count {
                    let offset = offsetsRv[i].floatValue + Float(i)*deltaIncrease;
                    offsetsRv[i] = NSNumber(value:offset)
                    lastOffset = CGFloat(offset)
                }
                // we are done
                glyphs = glyphsRv
                offsets = offsetsRv
                height = lastOffset + prev.fullAdvance;
                return;
            }
        }
    }
    
    func findGlyphForCharacterAtIndex(_ index:String.Index, inString str:String) -> CGGlyph {
        // Get the character at index taking into account UTF-32 characters
        var chars = Array(str[index].utf16)

        // Get the glyph from the font
        var glyph = [CGGlyph](repeating: CGGlyph.zero, count: chars.count)
        let found = CTFontGetGlyphsForCharacters(styleFont.ctFont, &chars, &glyph, chars.count)
        if !found {
            // Try fallback font if available
            if let fallbackFont = styleFont.fallbackFont {
                let fallbackFound = CTFontGetGlyphsForCharacters(fallbackFont, &chars, &glyph, chars.count)
                if fallbackFound {
                    return glyph[0]
                }
            }
            // the font did not contain a glyph for our character, so we just return 0 (notdef)
            return 0
        }
        return glyph[0]
    }
    
    // MARK: - Large Operators
    
    /// Creates display for large operator according to TeX Appendix G, Rule 13.
    ///
    /// ## TeX Rule 13: Large Operators
    /// "Large operators (like ∑, ∏, ∫) are treated specially:"
    ///
    /// ### TeX Algorithm:
    /// 1. **Display style**: Use enlarged glyph variant
    /// 2. **Other styles**: Use normal size
    /// 3. **Vertical centering**: Position relative to axis height
    /// 4. **Limits handling**:
    ///    - Display/text mode: Limits go above/below (if `limits = true`)
    ///    - Script mode: Limits go as superscript/subscript
    /// 5. **Italic correction**: Apply to superscript positioning
    ///
    /// ### OpenType Math Parameters Used:
    /// - `getLargerGlyph()`: Finds display-size variant
    /// - `getItalicCorrection()`: Adjusts superscript position
    /// - `axisHeight`: Centers operator vertically
    /// - `upperLimitGapMin`, `lowerLimitGapMin`: Spacing for limits
    ///
    /// ### Examples:
    /// - "∑": Sum with limits above/below in display mode
    /// - "∫": Integral (limits=false, so uses scripts)
    /// - "∏": Product with limits
    ///
    /// - Parameter op: The large operator atom
    /// - Returns: Operator display with optional limits/scripts
    func makeLargeOp(_ op:MTLargeOperator!) -> MTDisplay?  {
        // Show limits above/below in both display and text (inline) modes
        // Only show limits to the side in script modes to keep them compact
        let limits = op.limits && (style == .display || style == .text)
        var delta = CGFloat(0)
        if op.nucleus.count == 1 {
            guard let mathTable = styleFont.mathTable else { return nil }
            
            var glyph = self.findGlyphForCharacterAtIndex(op.nucleus.startIndex, inString:op.nucleus)
            if style == .display && glyph != 0 {
                // Enlarge the character in display style.
                glyph = mathTable.getLargerGlyph(glyph)
            }
            // This is be the italic correction of the character.
            delta = mathTable.getItalicCorrection(glyph)

            // vertically center
            let bbox = CTFontGetBoundingRectsForGlyphs(styleFont.ctFont, .horizontal, &glyph, nil, 1);
            let width = CTFontGetAdvancesForGlyphs(styleFont.ctFont, .horizontal, &glyph, nil, 1);
            var ascent=CGFloat(0), descent=CGFloat(0)
            getBboxDetails(bbox, ascent: &ascent, descent: &descent)
            let shiftDown = 0.5*(ascent - descent) - mathTable.axisHeight;
            let glyphDisplay = MTGlyphDisplay(withGlpyh: glyph, range: op.indexRange, font: styleFont)
            glyphDisplay.ascent = ascent;
            glyphDisplay.descent = descent;
            glyphDisplay.width = width;
            if (op.subScript != nil) && !limits {
                // Remove italic correction from the width of the glyph if
                // there is a subscript and limits is not set.
                glyphDisplay.width -= delta;
            }
            glyphDisplay.shiftDown = shiftDown;
            glyphDisplay.position = currentPosition;
            return self.addLimitsToDisplay(glyphDisplay, forOperator:op, delta:delta)
        } else {
            // Create a regular node
            let line = NSMutableAttributedString(string: op.nucleus)
            // add the font
            line.addAttribute(kCTFontAttributeName as NSAttributedString.Key, value:styleFont.ctFont as Any, range:NSMakeRange(0, line.length))
            let displayAtom = MTCTLineDisplay(withString: line, position: currentPosition, range: op.indexRange, font: styleFont, atoms: [op])
            return self.addLimitsToDisplay(displayAtom, forOperator:op, delta:0)
        }
    }
    
    func addLimitsToDisplay(_ display:MTDisplay?, forOperator op:MTLargeOperator, delta:CGFloat) -> MTDisplay? {
        guard let display = display else { return nil }
        
        // If there is no subscript or superscript, just return the current display
        if op.subScript == nil && op.superScript == nil {
            currentPosition.x += display.width
            return display;
        }
        // Show limits above/below in both display and text (inline) modes
        if op.limits && (style == .display || style == .text) {
            // make limits
            var superScript:MTMathListDisplay? = nil, subScript:MTMathListDisplay? = nil
            if op.superScript != nil {
                superScript = MTTypesetter.createLineForMathList(op.superScript, font:font, style:self.scriptStyle(), cramped:self.superScriptCramped())
            }
            if op.subScript != nil {
                subScript = MTTypesetter.createLineForMathList(op.subScript, font:font, style:self.scriptStyle(), cramped:self.subscriptCramped())
            }
            assert((superScript != nil) || (subScript != nil), "At least one of superscript or subscript should have been present.");
            
            guard let mathTable = styleFont.mathTable else {
                // Fallback without proper gap calculations
                currentPosition.x += display.width
                return display
            }
            
            let opsDisplay = MTLargeOpLimitsDisplay(withNucleus:display, upperLimit:superScript, lowerLimit:subScript, limitShift:delta/2, extraPadding:0)
            if let superScript = superScript {
                let upperLimitGap = max(mathTable.upperLimitGapMin, mathTable.upperLimitBaselineRiseMin - superScript.descent);
                opsDisplay.upperLimitGap = upperLimitGap;
            }
            if let subScript = subScript {
                let lowerLimitGap = max(mathTable.lowerLimitGapMin, mathTable.lowerLimitBaselineDropMin - subScript.ascent);
                opsDisplay.lowerLimitGap = lowerLimitGap;
            }
            opsDisplay.position = currentPosition;
            opsDisplay.range = op.indexRange;
            currentPosition.x += opsDisplay.width;
            return opsDisplay;
        } else {
            currentPosition.x += display.width;
            let scriptContext = MTRenderContext(
                font: font,
                styleFont: styleFont,
                style: style,
                cramped: cramped,
                spaced: spaced,
                maxWidth: maxWidth,
                position: currentPosition
            )
            scriptRenderer.makeScripts(op, display: display, index: UInt(op.indexRange.location), delta: delta, context: scriptContext, typesetter: self)
            return display;
        }
    }
    
    // MARK: - Large delimiters
    
    /// TeX Appendix G, Rules 19-20: Variable-size delimiters.
    ///
    /// ## TeX Rules for Delimiters:
    ///
    /// **Rule 19 (Delimiter selection):**
    /// "Choose delimiter size to cover at least a certain fraction of the formula."
    /// - Formula: `height ≥ max(f × δ/500, 2δ - σ)` where:
    ///   - `f` = delimiter factor (901 in plain.tex)
    ///   - `δ` = maximum distance from axis
    ///   - `σ` = delimiter shortfall (5pt in plain.tex)
    ///
    /// **Rule 20 (Glyph construction):**
    /// "If no single glyph is large enough, construct from pieces."
    /// - Use GlyphAssembly table from OpenType MATH
    /// - Stack extender pieces to reach target height
    ///
    /// ### Implementation Constants:
    /// - `kDelimiterFactor = 901`: Requires delimiter to cover 90.1% of content
    /// - `kDelimiterShortfallPoints = 5`: Allow up to 5pt shortfall
    ///
    /// These match plain.tex values for TeX compatibility.
    
    // Delimiter shortfall from plain.tex
    static let kDelimiterFactor = CGFloat(901)
    static let kDelimiterShortfallPoints = CGFloat(5)
    
    /// Creates display for left/right delimiters (e.g., parentheses, brackets).
    ///
    /// Implements TeX Rules 19-20 for variable-size delimiter selection.
    ///
    /// ## Algorithm:
    /// 1. **Calculate content height**: `δ = max(ascent - axis, descent + axis)`
    /// 2. **Determine target size**: Using delimiter factor and shortfall
    /// 3. **Find/construct glyphs**: Left and right delimiters
    /// 4. **Position elements**: Delimiters around content
    ///
    /// ### Examples:
    /// - `\left( \frac{a}{b} \right)`: Large parentheses around fraction
    /// - `\left\{ x \right.`: Left brace only (right is empty)
    /// - `\left[ \sum \right]`: Brackets around large operator
    ///
    /// - Parameters:
    ///   - inner: The MTInner atom containing content and boundary specs
    ///   - maxWidth: Maximum width for line breaking (0 = no limit)
    /// - Returns: Display with delimiters positioned around content
    func makeLeftRight(_ inner: MTInner?, maxWidth: CGFloat = 0) -> MTDisplay? {
        guard let inner = inner,
              let innerListDisplay = MTTypesetter.createLineForMathList(inner.innerList, font:font, style:style, cramped:cramped, spaced:true, maxWidth:maxWidth),
              let mathTable = styleFont.mathTable else {
            return nil
        }
        
        assert(inner.leftBoundary != nil || inner.rightBoundary != nil, "Inner should have a boundary to call this function");

        let axisHeight = mathTable.axisHeight
        // delta is the max distance from the axis
        let delta = max(innerListDisplay.ascent - axisHeight, innerListDisplay.descent + axisHeight);
        let d1 = (delta / 500) * MTTypesetter.kDelimiterFactor;  // This represents atleast 90% of the formula
        let d2 = 2 * delta - MTTypesetter.kDelimiterShortfallPoints;  // This represents a shortfall of 5pt
        // The size of the delimiter glyph should cover at least 90% of the formula or
        // be at most 5pt short.
        let glyphHeight = max(d1, d2);
        
        var innerElements = [MTDisplay]()
        var position = CGPoint.zero
        if let leftBoundary = inner.leftBoundary, !leftBoundary.nucleus.isEmpty {
            guard let leftGlyph = self.findGlyphForBoundary(leftBoundary.nucleus, withHeight:glyphHeight) else {
                return nil
            }
            leftGlyph.position = position
            position.x += leftGlyph.width
            innerElements.append(leftGlyph)
        }
        
        innerListDisplay.position = position;
        position.x += innerListDisplay.width;
        innerElements.append(innerListDisplay)
        
        if let rightBoundary = inner.rightBoundary, !rightBoundary.nucleus.isEmpty {
            guard let rightGlyph = self.findGlyphForBoundary(rightBoundary.nucleus, withHeight:glyphHeight) else {
                return nil
            }
            rightGlyph.position = position;
            position.x += rightGlyph.width;
            innerElements.append(rightGlyph)
        }
        let innerDisplay = MTMathListDisplay(withDisplays: innerElements, range: inner.indexRange)
        return innerDisplay
    }
    
    func findGlyphForBoundary(_ delimiter:String, withHeight glyphHeight:CGFloat) -> MTDisplay? {
        var glyphAscent=CGFloat(0), glyphDescent=CGFloat(0), glyphWidth=CGFloat(0)
        let leftGlyph = self.findGlyphForCharacterAtIndex(delimiter.startIndex, inString:delimiter)
        let glyph = self.findGlyph(leftGlyph, withHeight:glyphHeight, glyphAscent:&glyphAscent, glyphDescent:&glyphDescent, glyphWidth:&glyphWidth)
        
        var glyphDisplay:MTDisplayDS?
        if (glyphAscent + glyphDescent < glyphHeight) {
            // we didn't find a pre-built glyph that is large enough
            glyphDisplay = self.constructGlyph(leftGlyph, withHeight:glyphHeight)
        }
        
        if glyphDisplay == nil {
            // Create a glyph display
            glyphDisplay = MTGlyphDisplay(withGlpyh: glyph, range: NSMakeRange(NSNotFound, 0), font:styleFont)
            glyphDisplay?.ascent = glyphAscent;
            glyphDisplay?.descent = glyphDescent;
            glyphDisplay?.width = glyphWidth;
        }
        
        guard let display = glyphDisplay,
              let mathTable = styleFont.mathTable else {
            return glyphDisplay
        }
        
        // Center the glyph on the axis
        let shiftDown = 0.5*(display.ascent - display.descent) - mathTable.axisHeight;
        display.shiftDown = shiftDown;
        return display;
    }
    
    // MARK: - Underline/Overline
    
    func makeUnderline(_ under:MTUnderLine?) -> MTDisplay? {
        guard let under = under,
              let innerListDisplay = MTTypesetter.createLineForMathList(under.innerList, font:font, style:style, cramped:cramped),
              let mathTable = styleFont.mathTable else {
            return nil
        }
        
        let underDisplay = MTLineDisplay(withInner: innerListDisplay, position: currentPosition, range: under.indexRange)
        // Move the line down by the vertical gap.
        underDisplay.lineShiftUp = -(innerListDisplay.descent + mathTable.underbarVerticalGap);
        underDisplay.lineThickness = mathTable.underbarRuleThickness;
        underDisplay.ascent = innerListDisplay.ascent
        underDisplay.descent = innerListDisplay.descent + mathTable.underbarVerticalGap + mathTable.underbarRuleThickness + mathTable.underbarExtraDescender;
        underDisplay.width = innerListDisplay.width;
        return underDisplay;
    }
    
    func makeOverline(_ over:MTOverLine?) -> MTDisplay? {
        guard let over = over,
              let innerListDisplay = MTTypesetter.createLineForMathList(over.innerList, font:font, style:style, cramped:true),
              let mathTable = styleFont.mathTable else {
            return nil
        }
        
        let overDisplay = MTLineDisplay(withInner:innerListDisplay, position:currentPosition, range:over.indexRange)
        overDisplay.lineShiftUp = innerListDisplay.ascent + mathTable.overbarVerticalGap;
        overDisplay.lineThickness = mathTable.underbarRuleThickness;
        overDisplay.ascent = innerListDisplay.ascent + mathTable.overbarVerticalGap + mathTable.overbarRuleThickness + mathTable.overbarExtraAscender;
        overDisplay.descent = innerListDisplay.descent;
        overDisplay.width = innerListDisplay.width;
        return overDisplay;
    }
    
    // MARK: - Accents
    
    /// Checks if the accentee is a single character (for special handling).
    ///
    /// ## TeX Rule 12: Accents
    /// Single-character accentees get special positioning using the character's
    /// top accent attachment point from the math table.
    ///
    /// Multi-character accentees use geometric centering instead.
    ///
    /// - Parameter accent: The accent atom to check
    /// - Returns: true if accentee is a single character without scripts
    func isSingleCharAccentee(_ accent:MTAccent?) -> Bool {
        guard let accent = accent, let innerList = accent.innerList else { return false }
        if innerList.atoms.count != 1 {
            // Not a single char list.
            return false
        }
        let innerAtom = innerList.atoms[0]
        if innerAtom.nucleus.count != 1 {
            // A complex atom, not a simple char.
            return false
        }
        if innerAtom.subScript != nil || innerAtom.superScript != nil {
            return false
        }
        return true
    }
    
    // The distance the accent must be moved from the beginning.
    func getSkew(_ accent: MTAccent?, accenteeWidth width:CGFloat, accentGlyph:CGGlyph) -> CGFloat {
        guard let accent = accent, let mathTable = styleFont.mathTable else { return 0 }
        if accent.nucleus.isEmpty {
            // No accent
            return 0
        }
        let accentAdjustment = mathTable.getTopAccentAdjustment(accentGlyph)
        var accenteeAdjustment = CGFloat(0)
        if !self.isSingleCharAccentee(accent) {
            // use the center of the accentee
            accenteeAdjustment = width/2
        } else {
            guard let innerList = accent.innerList else { return 0 }
            let innerAtom = innerList.atoms[0]
            let accenteeGlyph = self.findGlyphForCharacterAtIndex(innerAtom.nucleus.index(innerAtom.nucleus.endIndex, offsetBy:-1), inString:innerAtom.nucleus)
            accenteeAdjustment = mathTable.getTopAccentAdjustment(accenteeGlyph)
        }
        // The adjustments need to aligned, so skew is just the difference.
        return (accenteeAdjustment - accentAdjustment)
    }
    
    // Find the largest horizontal variant if exists, with width less than max width.
    func findVariantGlyph(_ glyph:CGGlyph, withMaxWidth maxWidth:CGFloat, maxWidth glyphAscent:inout CGFloat, glyphDescent:inout CGFloat, glyphWidth:inout CGFloat) -> CGGlyph {
        guard let mathTable = styleFont.mathTable else { return glyph }
        
        let variants = mathTable.getHorizontalVariantsForGlyph(glyph)
        let numVariants = variants.count
        assert(numVariants > 0, "A glyph is always it's own variant, so number of variants should be > 0");
        var glyphs = [CGGlyph]() // [numVariants)
        glyphs.reserveCapacity(numVariants)
        for i in 0 ..< numVariants {
            guard let variant = variants[i] else { continue }
            let glyph = variant.uint16Value
            glyphs.append(glyph)
        }

        var curGlyph = glyphs[0]  // if no other glyph is found, we'll return the first one.
        var bboxes = [CGRect](repeating: CGRect.zero, count: numVariants) // [numVariants)
        var advances = [CGSize](repeating: CGSize.zero, count:numVariants)
        // Get the bounds for these glyphs
        CTFontGetBoundingRectsForGlyphs(styleFont.ctFont, .horizontal, &glyphs, &bboxes, numVariants);
        CTFontGetAdvancesForGlyphs(styleFont.ctFont, .horizontal, &glyphs, &advances, numVariants);
        for i in 0..<numVariants {
            let bounds = bboxes[i]
            var ascent=CGFloat(0), descent=CGFloat(0)
            let width = CGRectGetMaxX(bounds);
            getBboxDetails(bounds, ascent: &ascent, descent: &descent);

            if (width > maxWidth) {
                if (i == 0) {
                    // glyph dimensions are not yet set
                    glyphWidth = advances[i].width;
                    glyphAscent = ascent;
                    glyphDescent = descent;
                }
                return curGlyph;
            } else {
                curGlyph = glyphs[i]
                glyphWidth = advances[i].width;
                glyphAscent = ascent;
                glyphDescent = descent;
            }
        }
        // We exhausted all the variants and none was larger than the width, so we return the largest
        return curGlyph;
    }
    
    /// Creates accent display according to TeX Appendix G, Rule 12.
    ///
    /// ## TeX Rule 12: Accent Construction
    /// "Accents are positioned above their base using the following algorithm:"
    ///
    /// ### TeX Algorithm:
    /// 1. **Set accentee**: Typeset base in cramped style
    /// 2. **Select accent glyph**: Find variant that fits accentee width
    /// 3. **Calculate horizontal position**:
    ///    - Single char: Use `topAccentAttachment` from math table (skew)
    ///    - Multiple chars: Center geometrically
    /// 4. **Calculate vertical position**:
    ///    - Base: `min(accentee.ascent, accentBaseHeight)`
    ///    - Height: `accentee.ascent - base`
    ///
    /// ### OpenType Math Parameters:
    /// - `topAccentAttachment`: Horizontal position on base character
    /// - `accentBaseHeight`: Typical height for positioning
    /// - Horizontal variants: Width-appropriate accent glyphs
    ///
    /// ### Special Cases:
    /// 1. **Empty accent**: Returns accentee unchanged
    /// 2. **Single char with scripts**: Attaches scripts to base (not accent)
    ///    - Example: â² → base=(a with scripts), accent=hat
    ///
    /// ### Examples:
    /// - \hat{x}: x̂
    /// - \tilde{abc}: ãbc (centered)
    /// - \vec{v}^2: v⃗² (superscript on base)
    ///
    /// - Parameter accent: The accent atom to render
    /// - Returns: Accent display or nil on error
    func makeAccent(_ accent:MTAccent?) -> MTDisplay? {
        // Guard against nil accent or nil innerList
        guard let accent = accent, let innerList = accent.innerList else {
            return nil
        }
        
        let accentee = MTTypesetter.createLineForMathList(innerList, font:font, style:style, cramped:true)
        if accent.nucleus.isEmpty {
            // no accent!
            return accentee
        }
        
        guard let accentee = accentee, let mathTable = styleFont.mathTable else {
            return nil
        }
        
        let end = accent.nucleus.index(before: accent.nucleus.endIndex)
        var accentGlyph = self.findGlyphForCharacterAtIndex(end, inString:accent.nucleus)
        let accenteeWidth = accentee.width;
        var glyphAscent=CGFloat(0), glyphDescent=CGFloat(0), glyphWidth=CGFloat(0)
        accentGlyph = self.findVariantGlyph(accentGlyph, withMaxWidth:accenteeWidth, maxWidth:&glyphAscent, glyphDescent:&glyphDescent, glyphWidth:&glyphWidth)
        let delta = min(accentee.ascent, mathTable.accentBaseHeight);
        let skew = self.getSkew(accent, accenteeWidth:accenteeWidth, accentGlyph:accentGlyph)
        let height = accentee.ascent - delta;  // This is always positive since delta <= height.
        let accentPosition = CGPointMake(skew, height);
        let accentGlyphDisplay = MTGlyphDisplay(withGlpyh: accentGlyph, range: accent.indexRange, font: styleFont)
        accentGlyphDisplay.ascent = glyphAscent;
        accentGlyphDisplay.descent = glyphDescent;
        accentGlyphDisplay.width = glyphWidth;
        accentGlyphDisplay.position = accentPosition;

        var finalAccentee = accentee
        if self.isSingleCharAccentee(accent) && (accent.subScript != nil || accent.superScript != nil) {
            // Attach the super/subscripts to the accentee instead of the accent.
            let innerAtom = innerList.atoms[0]
            innerAtom.superScript = accent.superScript;
            innerAtom.subScript = accent.subScript;
            accent.superScript = nil;
            accent.subScript = nil;
            // Remake the accentee (now with sub/superscripts)
            // Note: Latex adjusts the heights in case the height of the char is different in non-cramped mode. However this shouldn't be the case since cramping
            // only affects fractions and superscripts. We skip adjusting the heights.
            if let newAccentee = MTTypesetter.createLineForMathList(innerList, font:font, style:style, cramped:cramped) {
                finalAccentee = newAccentee
            }
        }

        let display = MTAccentDisplay(withAccent:accentGlyphDisplay, accentee:finalAccentee, range:accent.indexRange)
        display.width = finalAccentee.width;
        display.descent = finalAccentee.descent;
        let ascent = finalAccentee.ascent - delta + glyphAscent;
        display.ascent = max(finalAccentee.ascent, ascent);
        display.position = currentPosition;

        return display;
    }
    
    // MARK: - Table
    
    /// TeX table layout parameters (not directly from Appendix G).
    ///
    /// ## TeX \halign Implementation
    /// Tables/matrices use TeX's \halign primitive for alignment.
    /// This implementation adapts those concepts to modern typography.
    ///
    /// ### Spacing Parameters:
    /// - `kBaseLineSkipMultiplier = 1.2`: Default baseline-to-baseline (12pt for 10pt font)
    /// - `kLineSkipMultiplier = 0.1`: Additional space between rows (1pt for 10pt)
    /// - `kLineSkipLimitMultiplier = 0`: Minimum row separation
    /// - `kJotMultiplier = 0.3`: Small vertical unit (3pt for 10pt font, "jot" in TeX)
    ///
    /// ### Row Positioning Algorithm:
    /// 1. Position first row at y=0
    /// 2. For each subsequent row:
    ///    - Default skip: `baselineSkip`
    ///    - If rows too close: Use `lineSkip` instead
    ///    - Apply `openup` (jot-based additional spacing)
    /// 3. Center entire table vertically around axis
    ///
    /// ### Column Alignment:
    /// - `.left`: Align to left edge (default)
    /// - `.center`: Center in column
    /// - `.right`: Align to right edge
    ///
    /// Similar to LaTeX's `{lcr}` column specifications.
    
    let kBaseLineSkipMultiplier = CGFloat(1.2)  // default base line stretch is 12 pt for 10pt font.
    let kLineSkipMultiplier = CGFloat(0.1)  // default is 1pt for 10pt font.
    let kLineSkipLimitMultiplier = CGFloat(0)
    let kJotMultiplier = CGFloat(0.3) // A jot is 3pt for a 10pt font.
    
    /// Creates table/matrix display using TeX \halign-style layout.
    ///
    /// ## Implementation:
    /// 1. **Typeset cells**: Process all cells, calculate column widths
    /// 2. **Position columns**: Apply alignment within each column
    /// 3. **Position rows**: Stack rows with appropriate spacing
    /// 4. **Center vertically**: Align table around axis height
    ///
    /// ### Examples:
    /// - `\begin{matrix} a & b \\ c & d \end{matrix}`: 2×2 matrix
    /// - `\begin{pmatrix}...\end{pmatrix}`: Matrix with parentheses
    /// - Column alignment: `{lcr}` = left, center, right
    ///
    /// - Parameter table: The MTMathTable atom containing cells and alignment
    /// - Returns: Positioned table display or nil if empty
    func makeTable(_ table:MTMathTable?) -> MTDisplay? {
        guard let table = table else { return nil }
        
        let numColumns = table.numColumns;
        if numColumns == 0 || table.numRows == 0 {
            // Empty table
            return MTMathListDisplay(withDisplays: [MTDisplay](), range: table.indexRange)
        }

        var columnWidths = [CGFloat](repeating: 0, count: numColumns)
        let displays = self.typesetCells(table, columnWidths:&columnWidths)

        // Position all the columns in each row
        var rowDisplays = [MTDisplay]()
        for row in displays {
            let rowDisplay = self.makeRowWithColumns(row, forTable:table, columnWidths:columnWidths)
            rowDisplays.append(rowDisplay!)
        }

        // Position all the rows
        self.positionRows(rowDisplays, forTable:table)
        let tableDisplay = MTMathListDisplay(withDisplays: rowDisplays, range: table.indexRange)
        tableDisplay.position = currentPosition;
        return tableDisplay;
    }
    
    // Typeset every cell in the table. As a side-effect calculate the max column width of each column.
    func typesetCells(_ table:MTMathTable?, columnWidths: inout [CGFloat]) -> [[MTDisplay]] {
        guard let table = table else { return [[MTDisplay]]() }
        
        var displays = [[MTDisplay]]()
        for row in table.cells {
            var colDisplays = [MTDisplay]()
            for i in 0..<row.count {
                guard let disp = MTTypesetter.createLineForMathList(row[i], font:font, style:style) else {
                    continue
                }
                columnWidths[i] = max(disp.width, columnWidths[i])
                colDisplays.append(disp)
            }
            displays.append(colDisplays)
        }
        return displays
    }
    
    func makeRowWithColumns(_ cols:[MTDisplay], forTable table:MTMathTable?, columnWidths:[CGFloat]) -> MTMathListDisplay? {
        guard let table = table, let mathTable = styleFont.mathTable else {
            return nil
        }
        
        var columnStart = CGFloat(0)
        var rowRange = NSMakeRange(NSNotFound, 0);
        for i in 0..<cols.count {
            let col = cols[i]
            let colWidth = columnWidths[i]
            let alignment = table.get(alignmentForColumn: i)
            var cellPos = columnStart;
            switch alignment {
                case .right:
                    cellPos += colWidth - col.width
                case .center:
                    cellPos += (colWidth - col.width) / 2;
                case .left:
                    // No changes if left aligned
                    cellPos += 0  // no op
            }
            if (rowRange.location != NSNotFound) {
                rowRange = NSUnionRange(rowRange, col.range);
            } else {
                rowRange = col.range;
            }

            col.position = CGPointMake(cellPos, 0);
            columnStart += colWidth + table.interColumnSpacing * mathTable.muUnit;
        }
        // Create a display for the row
        let rowDisplay = MTMathListDisplay(withDisplays: cols, range:rowRange)
        return rowDisplay
    }
    
    func positionRows(_ rows:[MTDisplay], forTable table:MTMathTable?) {
        guard let table = table, let mathTable = styleFont.mathTable else { return }
        
        // Position the rows
        // We will first position the rows starting from 0 and then in the second pass center the whole table vertically.
        var currPos = CGFloat(0)
        let openup = table.interRowAdditionalSpacing * kJotMultiplier * styleFont.fontSize;
        let baselineSkip = openup + kBaseLineSkipMultiplier * styleFont.fontSize;
        let lineSkip = openup + kLineSkipMultiplier * styleFont.fontSize;
        let lineSkipLimit = openup + kLineSkipLimitMultiplier * styleFont.fontSize;
        var prevRowDescent = CGFloat(0)
        var ascent = CGFloat(0)
        var first = true
        for row in rows {
            if first {
                row.position = CGPointZero;
                ascent += row.ascent;
                first = false;
            } else {
                var skip = baselineSkip;
                if (skip - (prevRowDescent + row.ascent) < lineSkipLimit) {
                    // rows are too close to each other. Space them apart further
                    skip = prevRowDescent + row.ascent + lineSkip;
                }
                // We are going down so we decrease the y value.
                currPos -= skip;
                row.position = CGPointMake(0, currPos);
            }
            prevRowDescent = row.descent;
        }

        // Vertically center the whole structure around the axis
        // The descent of the structure is the position of the last row
        // plus the descent of the last row.
        let descent =  -currPos + prevRowDescent;
        let shiftDown = 0.5*(ascent - descent) - mathTable.axisHeight;

        for row in rows {
            row.position = CGPointMake(row.position.x, row.position.y - shiftDown);
        }
    }
}
