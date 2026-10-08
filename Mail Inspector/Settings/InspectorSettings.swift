import Foundation
import Observation

/// User-configurable settings for the inspector. Holds no message content.
@Observable
@MainActor
final class InspectorSettings {
    static let defaultMaxMessageSizeBytes = 25 * 1024 * 1024
    private static let trustedAuthServIDsKey = "trustedAuthServIDs"
    private static let publicSuffixListUpdateEnabledKey = "publicSuffixListUpdateEnabled"

    var maxMessageSizeBytes: Int = InspectorSettings.defaultMaxMessageSizeBytes

    /// `authserv-id` values (from `Authentication-Results` headers) the user has told the app to
    /// treat as trusted. Matching one of these strings is necessary but not sufficient for an
    /// authentication result to be genuinely trustworthy — see `AttributedAuthResult`'s
    /// documentation for why.
    var trustedAuthServIDs: [String] {
        didSet {
            UserDefaults.standard.set(trustedAuthServIDs, forKey: Self.trustedAuthServIDsKey)
        }
    }

    /// Whether `PublicSuffixList` is allowed to download a fresh copy of the list (at most once
    /// a week) for accurate organizational-domain comparisons. This is the only network request
    /// Mail Inspector ever makes; disabling this keeps the app fully offline, falling back to a
    /// small bundled list that covers common cases less precisely.
    var isPublicSuffixListUpdateEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isPublicSuffixListUpdateEnabled, forKey: Self.publicSuffixListUpdateEnabledKey)
        }
    }

    init() {
        trustedAuthServIDs = UserDefaults.standard.stringArray(forKey: Self.trustedAuthServIDsKey) ?? []
        isPublicSuffixListUpdateEnabled = UserDefaults.standard.object(forKey: Self.publicSuffixListUpdateEnabledKey) as? Bool ?? true
    }
}
