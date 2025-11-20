//
//  MathView.swift
//  SwiftMath
//
//  SwiftUI wrapper for MTMathUILabel.
//
//  This software may be modified and distributed under the terms of the
//  MIT license. See the LICENSE file for details.
//

#if canImport(SwiftUI)
import SwiftUI

/// A SwiftUI view for rendering LaTeX math expressions.
///
/// `MathView` provides a SwiftUI interface to MTMathUILabel, supporting multi-line
/// layout.
///
/// Example usage with constructor parameters:
/// ```swift
/// MathView(
///     latex: "x = \\frac{-b \\pm \\sqrt{b^2-4ac}}{2a}",
///     fontSize: 20,
///     textColor: .black,
/// )
/// ```
@available(iOS 14.0, macOS 11.0, *)
public struct MathView: View {
    private let latex: String
    private var fontSize: CGFloat
    private var textColor: Color
    private var labelMode: MTMathUILabelMode
    private var textAlignment: MTTextAlignment
    private var contentInsets: MTEdgeInsets
    private var lineLimit: Int

    /// Creates a MathView with the specified parameters.
    /// - Parameters:
    ///   - latex: The LaTeX string to render.
    ///   - fontSize: The font size in points. Default is 20.
    ///   - textColor: The text color. Default is black.
    ///   - labelMode: The label mode (display or text). Default is display.
    ///   - textAlignment: The horizontal text alignment. Default is left.
    ///   - contentInsets: The content insets. Default is nil (zero insets).
    ///   - lineLimit: The maximum number of lines to display. Set to 0 for unlimited (default).
    ///                When content exceeds this limit, the last line will be truncated with an ellipsis (…).
    public init(
        latex: String,
        fontSize: CGFloat = 20,
        textColor: Color = .black,
        labelMode: MTMathUILabelMode = .display,
        textAlignment: MTTextAlignment = .left,
        contentInsets: MTEdgeInsets? = nil,
        lineLimit: Int = 0
    ) {
        self.latex = latex
        self.fontSize = fontSize
        self.textColor = textColor
        self.labelMode = labelMode
        self.textAlignment = textAlignment
        #if os(macOS)
        self.contentInsets = contentInsets ?? NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        #else
        self.contentInsets = contentInsets ?? UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        #endif
        self.lineLimit = max(0, lineLimit)
    }

    public var body: some View {
        MathViewRepresentable(
            latex: latex,
            fontSize: fontSize,
            textColor: textColor,
            labelMode: labelMode,
            textAlignment: textAlignment,
            contentInsets: contentInsets,
            lineLimit: lineLimit
        )
    }
}

@available(iOS 14.0, macOS 11.0, *)
private struct MathViewRepresentable: MTViewRepresentable {
    let latex: String
    let fontSize: CGFloat
    let textColor: Color
    let labelMode: MTMathUILabelMode
    let textAlignment: MTTextAlignment
    let contentInsets: MTEdgeInsets
    let lineLimit: Int
    
    private var mtColor: MTColor {
        #if os(macOS)
        return NSColor(textColor)
        #else
        return UIColor(textColor)
        #endif
    }

    #if os(macOS)
    typealias NSViewType = MTMathUILabel

    func makeNSView(context: Context) -> MTMathUILabel {
        let label = MTMathUILabel()
        updateLabel(label)
        return label
    }

    func updateNSView(_ nsView: MTMathUILabel, context: Context) {
        updateLabel(nsView)
        nsView.needsLayout = true
    }

    @available(macOS 13.0, *)
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: MTMathUILabel, context: Context) -> CGSize? {
        // Use the proposed width to enable line wrapping
        if let width = proposal.width, width.isFinite, width > 0 {
            nsView.preferredMaxLayoutWidth = width
            let size = nsView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
            return size
        }
        // Return intrinsic size if no width constraint
        return nsView.sizeThatFits(.zero)
    }
    #else
    typealias UIViewType = MTMathUILabel

    func makeUIView(context: Context) -> MTMathUILabel {
        let label = MTMathUILabel()
        updateLabel(label)
        return label
    }

    func updateUIView(_ uiView: MTMathUILabel, context: Context) {
        updateLabel(uiView)
        uiView.setNeedsLayout()
        uiView.layoutIfNeeded()
    }

    @available(iOS 16.0, *)
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: MTMathUILabel, context: Context) -> CGSize? {
        // Use the proposed width to enable line wrapping
        if let width = proposal.width, width.isFinite, width > 0 {
            uiView.preferredMaxLayoutWidth = width
            let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
            return size
        }
        // Return intrinsic size if no width constraint
        return uiView.sizeThatFits(.zero)
    }
    #endif

    private func updateLabel(_ label: MTMathUILabel) {
        label.latex = latex
        label.fontSize = fontSize
        label.textColor = mtColor
        label.labelMode = labelMode
        label.textAlignment = textAlignment
        label.contentInsets = contentInsets
        label.lineLimit = lineLimit
        // Note: preferredMaxLayoutWidth is set in sizeThatFits based on SwiftUI's layout proposal
        // But we need to keep it set for the layout phase
    }
}

// MARK: - Platform-specific type aliases

#if os(macOS)
import AppKit
private typealias MTViewRepresentable = NSViewRepresentable
#else
import UIKit
@available(iOS 14.0, *)
private typealias MTViewRepresentable = UIViewRepresentable
#endif

// MARK: - Preview Provider

@available(iOS 14.0, macOS 11.0, *)
struct MathView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            // Using modifiers
            MathView(latex: "x = \\frac{-b \\pm \\sqrt{b^2-4ac}}{2a}")
                .frame(maxWidth: .infinity, alignment: .leading)

            // Using constructor parameters
            MathView(
                latex: "\\int_0^\\infty e^{-x^2} dx = \\frac{\\sqrt{\\pi}}{2}",
                fontSize: 20
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            // Mixed approach
            MathView(latex: "E = mc^2", fontSize: 30)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // Test with white color
            MathView(latex: "E = mc^2", fontSize: 30, textColor: .white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black)
        }
        .padding()
    }
}

#endif
