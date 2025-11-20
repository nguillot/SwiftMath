//
//  Created by Mike Griebling on 2022-12-31.
//  Translated from an Objective-C implementation by Kostub Deshmukh.
//
//  This software may be modified and distributed under the terms of the
//  MIT license. See the LICENSE file for details.
//

import Foundation
import CoreText

/**
 Different display styles supported by the `MTMathUILabel`.
 
 The only significant difference between the two modes is how fractions
 and limits on large operators are displayed.
 */
public enum MTMathUILabelMode {
    /// Display mode. Equivalent to $$ in TeX
    case display
    /// Text mode. Equivalent to $ in TeX.
    case text
}

/**
    Horizontal text alignment for `MTMathUILabel`.
 */
public enum MTTextAlignment : UInt {
    /// Align left.
    case left
    /// Align center.
    case center
    /// Align right.
    case right
}

/** The main view for rendering math.
 
 `MTMathLabel` accepts either a string in LaTeX or an `MTMathList` to display. Use
 `MTMathList` directly only if you are building it programmatically (e.g. using an
 editor), otherwise using LaTeX is the preferable method.
 
 The math display is centered vertically in the label. The default horizontal alignment is
 is left. This can be changed by setting `textAlignment`. The math is default displayed in
 *Display* mode. This can be changed using `labelMode`.
 
 When created it uses `[MTFontManager defaultFont]` as its font. This can be changed using
 the `font` parameter.
 */
@IBDesignable
public class MTMathUILabel : MTView {
        
    /** The `MTMathList` to render. Setting this will remove any
     `latex` that has already been set. If `latex` has been set, this will
     return the parsed `MTMathList` if the `latex` parses successfully. Use this
     setting if the `MTMathList` has been programmatically constructed, otherwise it
     is preferred to use `latex`.
     */
    public var mathList:MTMathList? {
        set {
            _mathList = newValue
            _error = nil
            _latex = MTMathListBuilder.mathListToString(newValue)
            self.invalidateIntrinsicContentSize()
            self.setNeedsLayout()
        }
        get { _mathList }
    }
    private var _mathList:MTMathList?
    
    /** The latex string to be displayed. Setting this will remove any `mathList` that
     has been set. If latex has not been set, this will return the latex output for the
     `mathList` that is set.
     @see error */
    @IBInspectable
    public var latex:String {
        set {
            _latex = newValue
            _error = nil
            var error : NSError? = nil
            _mathList = MTMathListBuilder.build(fromString: newValue, error: &error)
            if error != nil {
                _mathList = nil
                _error = error
                self.errorLabel?.text = error!.localizedDescription
                self.errorLabel?.frame = self.bounds
                self.errorLabel?.isHidden = !self.displayErrorInline
            } else {
                self.errorLabel?.isHidden = true
            }
            self.invalidateIntrinsicContentSize()
            self.setNeedsLayout()
        }
        get { _latex }
    }
    private var _latex = ""
    
    /** This contains any error that occurred when parsing the latex. */
    public var error:NSError? { _error }
    private var _error:NSError?
    
    /** If true, if there is an error it displays the error message inline. Default true. */
    public var displayErrorInline = true
    
    /** The MTFont to use for rendering. */
    public var font:MTFont? {
        set {
            guard newValue != nil else { return }
            _font = newValue
            self.invalidateIntrinsicContentSize()
            self.setNeedsLayout()
        }
        get { _font }
    }
    private var _font:MTFont?
    
    /** Convenience method to just set the size of the font without changing the fontface. */
    @IBInspectable
    public var fontSize:CGFloat {
        set {
            _fontSize = newValue
            let font = font?.copy(withSize: newValue)
            self.font = font  // also forces an update
        }
        get { _fontSize }
    }
    private var _fontSize:CGFloat=0
    
    /** This sets the text color of the rendered math formula. The default color is black. */
    @IBInspectable
    public var textColor:MTColor? {
        set {
            guard newValue != nil else { return }
            _textColor = newValue
            self.displayList?.textColor = newValue
            self.setNeedsDisplay()
        }
        get { _textColor }
    }
    private var _textColor:MTColor?
    
    /** The minimum distance from the margin of the view to the rendered math. This value is
     `UIEdgeInsetsZero` by default. This is useful if you need some padding between the math and
     the border/background color. sizeThatFits: will have its returned size increased by these insets.
     */
    @IBInspectable
    public var contentInsets:MTEdgeInsets {
        set {
            _contentInsets = newValue
            self.invalidateIntrinsicContentSize()
            self.setNeedsLayout()
        }
        get { _contentInsets }
    }
    private var _contentInsets = MTEdgeInsetsZero
    
    /** The Label mode for the label. The default mode is Display */
    public var labelMode:MTMathUILabelMode {
        set {
            _labelMode = newValue
            self.invalidateIntrinsicContentSize()
            self.setNeedsLayout()
        }
        get { _labelMode }
    }
    private var _labelMode = MTMathUILabelMode.display
    
    /** Horizontal alignment for the text. The default is align left. */
    public var textAlignment:MTTextAlignment {
        set {
            _textAlignment = newValue
            self.invalidateIntrinsicContentSize()
            self.setNeedsLayout()
        }
        get { _textAlignment }
    }
    private var _textAlignment = MTTextAlignment.left
    
    /** The internal display of the MTMathUILabel. This is for advanced use only. */
    public var displayList: MTMathListDisplay? { _displayList }
    private var _displayList:MTMathListDisplay?

    /** The preferred maximum width (in points) for a multiline label.
     Set this property to enable line wrapping based on available width. */
    public var preferredMaxLayoutWidth: CGFloat {
        set {
            _preferredMaxLayoutWidth = newValue
            self.invalidateIntrinsicContentSize()
            self.setNeedsLayout()
        }
        get { _preferredMaxLayoutWidth }
    }
    private var _preferredMaxLayoutWidth: CGFloat = 0

    /** The maximum number of lines to display.
     Set to 0 for unlimited lines (default). When content exceeds this limit,
     the last line will be truncated with an ellipsis (…). */
    public var lineLimit: Int {
        set {
            _lineLimit = max(0, newValue) // Ensure non-negative
            self.invalidateIntrinsicContentSize()
            self.setNeedsLayout()
        }
        get { _lineLimit }
    }
    private var _lineLimit: Int = 0

    public var currentStyle:MTLineStyle {
        switch _labelMode {
            case .display: return .display
            case .text: return .text
        }
    }
    
    public var errorLabel: MTLabel?
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        self.initCommon()
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.initCommon()
    }
    
    func initCommon() {
#if os(macOS)
        self.layer?.isGeometryFlipped = true
#else
        self.layer.isGeometryFlipped = true
        self.clipsToBounds = true
#endif
        _fontSize = 20
        _contentInsets = MTEdgeInsetsZero
        _labelMode = .display
        let font = MTFontManager.fontManager.defaultFont
        self.font = font
        _textAlignment = .left
        _displayList = nil
        displayErrorInline = true
        self.backgroundColor = MTColor.clear
        
        _textColor = MTColor.black
        let label = MTLabel()
        self.errorLabel = label
#if os(macOS)
        label.layer?.isGeometryFlipped = true
#else
        label.layer.isGeometryFlipped = true
#endif
        label.isHidden = true
        label.textColor = MTColor.red
        self.addSubview(label)
    }
    
    override public func draw(_ dirtyRect: MTRect) {
        super.draw(dirtyRect)
        if self.mathList == nil { return }
        if self.font == nil { return }

        // drawing code
        let context = MTGraphicsGetCurrentContext()!
        context.saveGState()
        displayList!.draw(context)
        context.restoreGState()
    }
    
    func _layoutSubviews() {
        guard _mathList != nil && self.font != nil else {
            _displayList = nil
            errorLabel?.frame = self.bounds
            self.setNeedsDisplay()
            return
        }
        // Ensure we have a valid font before attempting to typeset
        if self.font == nil {
            // No valid font - try to get default font
            if let defaultFont = MTFontManager.fontManager.defaultFont {
                self._font = defaultFont
            } else {
                // Cannot typeset without a font, clear display list
                _displayList = nil
                errorLabel?.frame = self.bounds
                self.setNeedsDisplay()
                return
            }
        }

        // Use the effective width for layout
        let effectiveWidth = _preferredMaxLayoutWidth > 0 ? _preferredMaxLayoutWidth : bounds.size.width
        let availableWidth = effectiveWidth - contentInsets.left - contentInsets.right

        // print("Pre list = \(_mathList!)")
        _displayList = MTTypesetter.createLineForMathList(_mathList, font: self.font, style: currentStyle, maxWidth: availableWidth)
        _displayList!.textColor = textColor
        
        // Apply line limit if specified
        if _lineLimit > 0 {
            _displayList = applyLineLimit(to: _displayList!, maxLines: _lineLimit, maxWidth: availableWidth)
        }
        
        // print("Post list = \(_mathList!)")
        var textX = CGFloat(0)
        switch self.textAlignment {
            case .left:   textX = contentInsets.left
            case .center: textX = (bounds.size.width - contentInsets.left - contentInsets.right - _displayList!.width) / 2 + contentInsets.left
            case .right:  textX = bounds.size.width - _displayList!.width - contentInsets.right
        }
        let availableHeight = bounds.size.height - contentInsets.bottom - contentInsets.top

        // center things vertically
        var height = _displayList!.ascent + _displayList!.descent
        if height < fontSize/2 {
            height = fontSize/2  // set height to half the font size
        }
        let textY = (availableHeight - height) / 2 + _displayList!.descent + contentInsets.bottom
        _displayList!.position = CGPointMake(textX, textY)
        errorLabel?.frame = self.bounds
        self.setNeedsDisplay()
    }
    
    func _sizeThatFits(_ size:CGSize) -> CGSize {
        guard _mathList != nil else {
            // No content - return no-intrinsic-size marker
            return CGSize(width: -1, height: -1)
        }

        // Ensure we have a valid font before attempting to typeset
        if self.font == nil {
            // No valid font - try to get default font
            if let defaultFont = MTFontManager.fontManager.defaultFont {
                self._font = defaultFont
            } else {
                // Cannot typeset without a font
                return CGSize(width: -1, height: -1)
            }
        }

        // Determine the maximum width to use
        var maxWidth: CGFloat = 0
        if _preferredMaxLayoutWidth > 0 {
            maxWidth = _preferredMaxLayoutWidth - contentInsets.left - contentInsets.right
        } else if size.width > 0 {
            maxWidth = size.width - contentInsets.left - contentInsets.right
        }

        var displayList:MTMathListDisplay? = nil
        displayList = MTTypesetter.createLineForMathList(_mathList, font: self.font, style: currentStyle, maxWidth: maxWidth)

        guard displayList != nil else {
            // Failed to create display list
            return CGSize(width: -1, height: -1)
        }
        
        // Apply line limit if specified
        if _lineLimit > 0 {
            displayList = applyLineLimit(to: displayList!, maxLines: _lineLimit, maxWidth: maxWidth)
        }

        var resultWidth = displayList!.width + contentInsets.left + contentInsets.right
        let resultHeight = displayList!.ascent + displayList!.descent + contentInsets.top + contentInsets.bottom

        // Ensure we don't exceed the width constraints
        if _preferredMaxLayoutWidth > 0 && resultWidth > _preferredMaxLayoutWidth {
            resultWidth = _preferredMaxLayoutWidth
        } else if _preferredMaxLayoutWidth == 0 && size.width > 0 && resultWidth > size.width {
            resultWidth = size.width
        }

        return CGSize(width: resultWidth, height: resultHeight)
    }

    #if os(macOS)
    public func sizeThatFits(_ size: CGSize) -> CGSize {
        return _sizeThatFits(size)
    }
    #else
    public override func sizeThatFits(_ size: CGSize) -> CGSize {
        return _sizeThatFits(size)
    }
    #endif

    #if os(macOS)
    func setNeedsDisplay() { self.needsDisplay = true }
    func setNeedsLayout() { self.needsLayout = true }
    public override var fittingSize: CGSize { _sizeThatFits(CGSizeZero) }
    public override var intrinsicContentSize: CGSize { _sizeThatFits(CGSizeZero) }
    override public var isFlipped: Bool { false }
    override public func layout() {
        self._layoutSubviews()
        super.layout()
    }
#else
    public override var intrinsicContentSize: CGSize { _sizeThatFits(CGSizeZero) }
    override public func layoutSubviews() { _layoutSubviews() }
#endif
    
    // MARK: - Line Limit Support
    
    /// Applies line limit to the display list, truncating content beyond the specified number of lines
    /// and adding an ellipsis to the last visible line.
    /// - Parameters:
    ///   - displayList: The display list to truncate
    ///   - maxLines: The maximum number of lines to display
    ///   - maxWidth: The maximum width available for each line
    /// - Returns: A new display list with truncation applied
    private func applyLineLimit(to displayList: MTMathListDisplay, maxLines: Int, maxWidth: CGFloat) -> MTMathListDisplay {
        guard maxLines > 0 else { return displayList }
        
        // Safety check: if no width constraint or empty display list, return as-is
        guard maxWidth > 0, !displayList.subDisplays.isEmpty else { return displayList }
        
        // Sort displays by Y position (descending, since Y goes negative downward)
        // This groups displays that are visually on the same horizontal line
        let sortedDisplays = displayList.subDisplays.sorted { $0.position.y > $1.position.y }
        
        // Group displays by visual lines based on Y position clusters
        // Displays with similar Y positions are on the same visual line
        var lineGroups: [(displays: [MTDisplay], baselineY: CGFloat, minY: CGFloat, maxY: CGFloat)] = []
        let yTolerance: CGFloat = 10.0  // Y positions within this range are considered same line
        
        for display in sortedDisplays {
            let displayY = display.position.y
            
            // Find which line group this display belongs to based on Y position
            var foundLine = false
            
            for i in 0..<lineGroups.count {
                if abs(displayY - lineGroups[i].baselineY) < yTolerance {
                    // Similar Y position - add to this line
                    lineGroups[i].displays.append(display)
                    lineGroups[i].minY = min(lineGroups[i].minY, displayY)
                    lineGroups[i].maxY = max(lineGroups[i].maxY, displayY)
                    foundLine = true
                    break
                }
            }
            
            if !foundLine {
                // New line with this Y as baseline
                lineGroups.append((displays: [display], baselineY: displayY, minY: displayY, maxY: displayY))
            }
        }
        
        // Sort each line's displays by X position for correct left-to-right order
        for i in 0..<lineGroups.count {
            lineGroups[i].displays.sort { $0.position.x < $1.position.x }
        }
        
        // If we have fewer lines than the limit, no truncation needed
        if lineGroups.count <= maxLines {
            return displayList
        }
        
        // Create ellipsis once
        let ellipsis = createEllipsisDisplay()
        let ellipsisWidth = measureDisplayWidth(ellipsis)
        
        // Determine which line will have the ellipsis (the last visible line)
        let ellipsisLineIndex = maxLines - 1
        
        // Build result with truncation
        var newDisplays: [MTDisplay] = []
        
        for lineIndex in 0..<maxLines {
            let line = lineGroups[lineIndex]
            let isEllipsisLine = (lineIndex == ellipsisLineIndex)
            
            if !isEllipsisLine {
                // Lines before the ellipsis line: add completely
                newDisplays.append(contentsOf: line.displays)
            } else {
                // This is the line that gets truncated with ellipsis
                let lineYPos = line.minY
                var accumulatedWidth: CGFloat = 0
                var lineDisplays: [MTDisplay] = []
                
                for (_, display) in line.displays.enumerated() {
                    // For CTLineDisplay (text), we may need to truncate it to fit
                    if let lineDisplay = display as? MTCTLineDisplay,
                       let attrString = lineDisplay.attributedString {
                        let displayWidth = measureDisplayWidth(display)
                        let displayStartX = display.position.x
                        let displayEndX = displayStartX + displayWidth
                        let requiredWidth = displayEndX + ellipsisWidth
                        
                        if requiredWidth <= maxWidth {
                            // Fits completely
                            lineDisplays.append(display)
                            accumulatedWidth = displayEndX
                        } else if displayStartX + ellipsisWidth <= maxWidth {
                            // Need to truncate this text display to fit ellipsis
                            let availableWidthForText = maxWidth - displayStartX - ellipsisWidth
                            
                            // Binary search to find how many characters fit in the available width
                            var low = 0
                            var high = attrString.length
                            var bestFitLength = 0
                            
                            while low <= high {
                                let mid = (low + high) / 2
                                let testString = attrString.attributedSubstring(from: NSRange(location: 0, length: mid))
                                let testLine = CTLineCreateWithAttributedString(testString)
                                let testWidth = CGFloat(CTLineGetTypographicBounds(testLine, nil, nil, nil))
                                
                                if testWidth <= availableWidthForText {
                                    bestFitLength = mid
                                    low = mid + 1
                                } else {
                                    high = mid - 1
                                }
                            }
                            
                            if bestFitLength > 0 {
                                // Create truncated attributed string with only the characters that fit
                                let truncatedAttrString = attrString.attributedSubstring(from: NSRange(location: 0, length: bestFitLength))
                                let truncatedLine = CTLineCreateWithAttributedString(truncatedAttrString)
                                let truncatedWidth = CGFloat(CTLineGetTypographicBounds(truncatedLine, nil, nil, nil))
                                
                                let truncatedDisplay = MTCTLineDisplay(
                                    withString: truncatedAttrString as! NSMutableAttributedString,
                                    position: display.position,
                                    range: NSRange(location: lineDisplay.range.location, length: bestFitLength),
                                    font: self.font,
                                    atoms: lineDisplay.atoms
                                )
                                truncatedDisplay.textColor = lineDisplay.textColor
                                lineDisplays.append(truncatedDisplay)
                                accumulatedWidth = displayStartX + truncatedWidth
                            } else {
                                break
                            }
                        } else {
                            break
                        }
                    } else {
                        // Non-text display (fraction, radical, etc.)
                        let displayWidth = measureDisplayWidth(display)
                        let displayStartX = display.position.x
                        let displayEndX = displayStartX + displayWidth
                        let requiredWidth = displayEndX + ellipsisWidth
                        
                        if requiredWidth <= maxWidth {
                            lineDisplays.append(display)
                            accumulatedWidth = displayEndX
                        } else {
                            break
                        }
                    }
                }
                
                newDisplays.append(contentsOf: lineDisplays)
                
                // Position ellipsis at the end of accumulated displays
                ellipsis.position = CGPoint(x: accumulatedWidth, y: lineYPos)
                ellipsis.textColor = textColor
                newDisplays.append(ellipsis)
            }
        }
        
        // Create new display list with truncated content
        let truncatedDisplay = MTMathListDisplay(withDisplays: newDisplays, range: displayList.range)
        truncatedDisplay.textColor = displayList.textColor
        
        return truncatedDisplay
    }
    
    /// Measures the actual width of a display using CTLineGetTypographicBounds
    private func measureDisplayWidth(_ display: MTDisplay) -> CGFloat {
        // For CTLineDisplay, use CTLineGetTypographicBounds for accurate measurement
        if let lineDisplay = display as? MTCTLineDisplay,
           let attrString = lineDisplay.attributedString {
            let ctLine = CTLineCreateWithAttributedString(attrString)
            return CGFloat(CTLineGetTypographicBounds(ctLine, nil, nil, nil))
        }
        // For other displays, use the width property
        return display.width
    }
    
    /// Creates a display for the ellipsis character
    private func createEllipsisDisplay() -> MTCTLineDisplay {
        let ellipsisString = NSMutableAttributedString(string: "\u{2026}") // Unicode ellipsis
        
        // Use the current font for the ellipsis
        let currentFont = self.font ?? MTFontManager.fontManager.defaultFont
        
        guard let fontToUse = currentFont else {
            // Last resort: create a minimal display if even default font is nil
            // This shouldn't happen in practice
            let emptyDisplay = MTCTLineDisplay(
                withString: NSMutableAttributedString(string: ""),
                position: CGPoint.zero,
                range: NSMakeRange(NSNotFound, 0),
                font: nil,
                atoms: []
            )
            return emptyDisplay
        }
        
        ellipsisString.addAttribute(.font, value: fontToUse.ctFont as Any, range: NSMakeRange(0, 1))
        
        let ellipsisDisplay = MTCTLineDisplay(
            withString: ellipsisString,
            position: CGPoint.zero,
            range: NSMakeRange(NSNotFound, 0),
            font: fontToUse,
            atoms: []
        )
        
        return ellipsisDisplay
    }
    
}
