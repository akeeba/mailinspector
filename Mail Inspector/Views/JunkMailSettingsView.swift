//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos / Akeeba Ltd
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import SwiftUI

/// Junk mail preferences: spam-filter header trust and brand-image (BIMI) display.
struct JunkMailSettingsView: View {
    @Environment(InspectorSettings.self) private var settings

    var body: some View {
        Form {
            Section {
                Toggle("Trust server spam headers", isOn: Binding(
                    get: { settings.trustServerSpamHeaders },
                    set: { settings.trustServerSpamHeaders = $0 }
                ))
            } header: {
                Text("Spam Filtering")
            } footer: {
                Text("When on, a message's spam-filter headers (X-Spam-Score, Exchange's Spam Confidence Level, etc.) are shown as a likelihood gauge. Off by default: unlike SPF/DKIM/DMARC these headers follow no standard, their scoring is entirely filter-specific, and the gauge only rescales a number a filter already reported — it's never something this app determined independently.")
                    .font(.caption)
            }

            Section {
                Toggle("Show brand images", isOn: Binding(
                    get: { settings.showBrandImages },
                    set: { settings.showBrandImages = $0 }
                ))
                if settings.showBrandImages {
                    Toggle("Hide brand images for messages without a spam score", isOn: Binding(
                        get: { settings.hideBrandImagesForMessagesWithoutSpamScore },
                        set: { settings.hideBrandImagesForMessagesWithoutSpamScore = $0 }
                    ))
                    Stepper(value: Binding(
                        get: { settings.hideBrandImagesAboveSpamThreshold },
                        set: { settings.hideBrandImagesAboveSpamThreshold = min(100, max(0, $0)) }
                    ), in: 0...100, step: 5) {
                        Text("Hide brand images above spam score: \(Int(settings.hideBrandImagesAboveSpamThreshold))%")
                    }
                }
            } header: {
                Text("Brand Images (BIMI)")
            } footer: {
                Text(settings.showBrandImages
                    ? "Looks up and displays the sender's published brand logo next to their identity, only when DMARC is a trusted pass. Fetching and rendering a remote image — even a logo the sender's own domain publishes — could be used as an attack vector against an unpatched vulnerability in macOS's image-decoding pipeline, the same risk as opening an image attachment from an untrusted sender. Only the logo's own domain is contacted, nothing else. The two options below only apply when a spam score is or isn't available, and are ignored entirely if \"Trust server spam headers\" is off and this message has no score."
                    : "Off by default. Looks up and displays the sender's published brand logo next to their identity, only when DMARC is a trusted pass. Fetching and rendering a remote image — even a logo the sender's own domain publishes — could be used as an attack vector against an unpatched vulnerability in macOS's image-decoding pipeline, the same risk as opening an image attachment from an untrusted sender.")
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
    }
}
