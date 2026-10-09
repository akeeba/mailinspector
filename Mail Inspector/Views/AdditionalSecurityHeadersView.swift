//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import SwiftUI

/// Section: known mail-filtering/chain-of-custody headers (Received-SPF, ARC-*, X-Spam-*,
/// Microsoft anti-spam headers, …) with a plain-language explanation of each. Values are shown
/// as-is; this never attempts to reimplement any filter's scoring logic.
struct AdditionalSecurityHeadersView: View {
    let headers: [AdditionalSecurityHeader]

    var body: some View {
        if !headers.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Additional Filtering Headers")
                    .font(.headline)
                ForEach(headers) { header in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(header.name)
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.semibold)
                        Text(header.value)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .foregroundStyle(.secondary)
                        Text(header.explanation)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.06)))
                }
            }
        }
    }
}
