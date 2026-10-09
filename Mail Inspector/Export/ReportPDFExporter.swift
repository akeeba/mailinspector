//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import SwiftUI
import AppKit
import CoreGraphics

/// Renders a message's report to a paginated, printable PDF for export (⌘E) or sharing (⇧⌘E).
///
/// Uses `ImageRenderer`'s PDF-context rendering rather than `NSHostingView.dataWithPDF` —
/// empirically confirmed (via `RunCodeSnippet` against this exact code path) that the latter
/// produces a blank page unless the hosting view is part of a live window, which a background
/// export has no reason to require.
///
/// Pagination works at the granularity of `ReportExportView.blocks` — one delivery hop, one raw
/// header field, one observation, etc. Each block's height is measured individually (via
/// `ImageRenderer`'s `render` closure, which reports the measured size before any drawing
/// happens — no rasterization needed just to measure), then blocks are packed into pages with
/// simple greedy bin-packing that never splits a block across two pages. Each page is rendered
/// from its own small `VStack` of just the blocks assigned to it, so a page's content is already
/// guaranteed to fit — no clip-and-translate slicing of one giant rendering is needed, which is
/// what caused an earlier version of this exporter to cut a line of text in half across a page
/// boundary. Both the packing math and the final rendering were verified with `RunCodeSnippet`
/// (color-coded blocks of known heights) before being trusted here.
@MainActor
enum ReportPDFExporter {
    /// Page margin on all sides. The footer (page number) lives inside the bottom margin, not
    /// inside the content area, so it never collides with report content.
    private static let margin: CGFloat = 36
    private static let footerHeight: CGFloat = 16

    static func renderPDF(for message: EmailMessage, settings: InspectorSettings, pageSize: ReportPageSize, aiInsights: AIInsightsExportSummary? = nil) -> Data? {
        let page = pageSize.pointSize
        let contentWidth = page.width - margin * 2
        let contentHeight = page.height - margin * 2 - footerHeight
        let blockSpacing = ReportExportView.blockSpacing

        let blocks = ReportExportView(message: message, settings: settings, aiInsights: aiInsights).blocks
        guard !blocks.isEmpty else { return nil }

        let heights = blocks.map { measureHeight(of: $0, width: contentWidth) }
        let pages = paginate(heights: heights, pageContentHeight: contentHeight, blockSpacing: blockSpacing)

        let outputData = NSMutableData()
        guard let consumer = CGDataConsumer(data: outputData as CFMutableData) else { return nil }
        var mediaBox = CGRect(origin: .zero, size: page)
        guard let pdfContext = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }

        for (pageIndex, blockIndices) in pages.enumerated() {
            let pageView = VStack(alignment: .leading, spacing: blockSpacing) {
                ForEach(blockIndices, id: \.self) { index in blocks[index] }
            }
            .frame(width: contentWidth, alignment: .leading)

            let pageRenderer = ImageRenderer(content: pageView)
            pageRenderer.render { size, renderFunc in
                pdfContext.beginPDFPage(nil)
                pdfContext.saveGState()
                // Top-aligns this page's content within the printable area, regardless of
                // whether it exactly fills the available height (the last page usually won't).
                let yOffset = (margin + footerHeight + contentHeight) - size.height
                pdfContext.translateBy(x: margin, y: yOffset)
                renderFunc(pdfContext)
                pdfContext.restoreGState()
                drawFooter(in: pdfContext, page: pageIndex + 1, pageCount: pages.count, pageSize: page)
                pdfContext.endPDFPage()
            }
        }
        pdfContext.closePDF()
        return outputData as Data
    }

    /// Measures a view's height at a fixed width without rasterizing it — `ImageRenderer`
    /// reports the measured size as the first argument to its render closure before any drawing
    /// happens, so this never needs to run the (unused) draw function it also provides.
    private static func measureHeight(of view: AnyView, width: CGFloat) -> CGFloat {
        let renderer = ImageRenderer(content: view.frame(width: width, alignment: .leading))
        var measured: CGFloat = 0
        renderer.render { size, _ in measured = size.height }
        return measured
    }

    /// Greedily assigns blocks to pages, never splitting one across two pages. If a single
    /// block is taller than a full page on its own (pathological — e.g. an enormous folded
    /// header), it still gets its own page rather than being merged with neighbors, and may
    /// overflow that page's bottom edge; that's an accepted rare-case limitation, not the
    /// common case this pagination exists to fix.
    private static func paginate(heights: [CGFloat], pageContentHeight: CGFloat, blockSpacing: CGFloat) -> [[Int]] {
        var pages: [[Int]] = [[]]
        var remaining = pageContentHeight
        for (index, height) in heights.enumerated() {
            let isFirstOnPage = pages[pages.count - 1].isEmpty
            let neededHeight = height + (isFirstOnPage ? 0 : blockSpacing)
            if neededHeight > remaining, !isFirstOnPage {
                pages.append([index])
                remaining = pageContentHeight - height
            } else {
                pages[pages.count - 1].append(index)
                remaining -= neededHeight
            }
        }
        return pages
    }

    private static func drawFooter(in context: CGContext, page: Int, pageCount: Int, pageSize: CGSize) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        let text = "Page \(page) of \(pageCount)" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let textSize = text.size(withAttributes: attributes)
        text.draw(
            at: CGPoint(x: (pageSize.width - textSize.width) / 2, y: margin / 2 - textSize.height / 2),
            withAttributes: attributes
        )
        NSGraphicsContext.restoreGraphicsState()
    }

    /// A filesystem-safe default filename for the Save panel / shared temp file.
    static func suggestedFileName(for message: EmailMessage) -> String {
        let base = message.subject?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? message.subject!
            : "Message"
        let invalidCharacters = CharacterSet(charactersIn: "/\\:")
        let sanitized = base.components(separatedBy: invalidCharacters).joined(separator: "-")
        return "Mail Inspector Report - \(sanitized).pdf"
    }
}
