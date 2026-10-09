//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos / Akeeba Ltd
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import AppKit

/// Presents the standard macOS About panel with a credits block naming the license and
/// linking to its full text, in place of the app-wide `.appInfo` command.
enum AboutPanel {
    static func show() {
        let credits = NSMutableAttributedString(
            string: "Licensed under the MIT License.\n",
            attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)]
        )
        credits.append(NSAttributedString(
            string: "View the license text",
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .link: URL(string: "https://github.com/akeeba/mailinspector/blob/main/license.txt")!
            ]
        ))
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        credits.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: credits.length))

        NSApplication.shared.orderFrontStandardAboutPanel(options: [.credits: credits])
    }
}
