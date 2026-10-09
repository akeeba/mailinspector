import Foundation

/// A thread-safe, process-wide cache of the Mozilla/ICANN Public Suffix List
/// (https://publicsuffix.org), used to compute the organizational-domain boundary for alignment
/// comparisons. A short hardcoded list of common suffixes cannot correctly handle less common
/// multi-label suffixes (e.g. `gov.gr`, `gov.cy`) — the real list has several thousand entries
/// and changes over time, so this downloads and caches it instead of guessing.
///
/// **This is one of only two network requests Mail Inspector ever makes** (the other being the
/// manually-triggered SPF recheck in `SPFEvaluator`), and only when enabled in Settings
/// (`InspectorSettings.isPublicSuffixListUpdateEnabled`, on by default). The request is a single
/// `GET` to a fixed, well-known URL — no message content, addresses, or any other data is ever
/// sent. The list is cached to disk and refreshed at most once a week; `refreshIfNeeded`
/// is safe to call on every launch, since it does nothing at all (no network access) while the
/// cache is still fresh. When offline, disabled, or before the first successful download, a
/// small bundled fallback list covers the most common cases so domain alignment still works
/// offline, just less precisely for less common suffixes.
nonisolated final class PublicSuffixList: @unchecked Sendable {
    static let shared = PublicSuffixList()

    private let lock = NSLock()
    private var suffixes: Set<String>

    private init() {
        suffixes = Self.loadCachedSuffixes() ?? Self.bundledFallbackSuffixes
    }

    /// The organizational (registrable) domain for `domain` — one label below the longest
    /// matching public suffix, e.g. `mail.ministry.gov.gr` → `ministry.gov.gr` because `gov.gr`
    /// is a listed suffix, not `gov.gr` itself or a naive last-two-labels guess.
    func organizationalDomain(of domain: String) -> String {
        let labels = domain.lowercased().split(separator: ".").map(String.init)
        guard labels.count >= 2 else { return domain.lowercased() }

        let knownSuffixes = snapshot()
        var matchedSuffixLength = 1
        for length in 1..<labels.count {
            let candidate = labels.suffix(length).joined(separator: ".")
            if knownSuffixes.contains(candidate) {
                matchedSuffixLength = length
            }
        }
        let organizationalLength = min(matchedSuffixLength + 1, labels.count)
        return labels.suffix(organizationalLength).joined(separator: ".")
    }

    var lastUpdated: Date? { Self.cachedFileDate() }

    private func snapshot() -> Set<String> {
        lock.lock(); defer { lock.unlock() }
        return suffixes
    }

    private func replaceSuffixes(_ newSuffixes: Set<String>) {
        lock.lock()
        suffixes = newSuffixes
        lock.unlock()
    }

    // MARK: - Refresh

    private static let cacheFileURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("MailInspector", isDirectory: true)
            .appendingPathComponent("public_suffix_list.dat")
    }()
    private static let cacheMaxAge: TimeInterval = 7 * 24 * 60 * 60
    /// Tried in order; the second is a mirror on GitHub, used only if the first is unreachable.
    private static let sourceURLs: [URL] = [
        URL(string: "https://publicsuffix.org/list/public_suffix_list.dat")!,
        URL(string: "https://raw.githubusercontent.com/publicsuffix/list/refs/heads/main/public_suffix_list.dat")!
    ]

    /// Downloads a fresh copy of the list if the cache is missing or older than a week.
    /// Never throws: any network or parsing failure just leaves the existing cached or bundled
    /// list in place.
    func refreshIfNeeded() async {
        if let cacheDate = Self.cachedFileDate(), Date().timeIntervalSince(cacheDate) < Self.cacheMaxAge {
            return
        }
        for url in Self.sourceURLs {
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
                  let text = String(data: data, encoding: .utf8) else {
                continue
            }
            let parsedSuffixes = Self.parse(text)
            guard !parsedSuffixes.isEmpty else { continue }
            replaceSuffixes(parsedSuffixes)
            Self.writeCache(data)
            return
        }
    }

    /// Parses the `.dat` format: one rule per line, `//`-prefixed comments, blank lines ignored.
    /// Wildcard (`*.example`) and exception (`!excluded.example`) rules are both skipped rather
    /// than handled per their full semantics — those affect only a small fraction of entries,
    /// and this app's use (a plain "is this suffix known" lookup for alignment comparisons) does
    /// not need full PSL-algorithm fidelity to be useful.
    private static func parse(_ text: String) -> Set<String> {
        var result: Set<String> = []
        for rawLine in text.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("//"), !line.hasPrefix("*"), !line.hasPrefix("!") else { continue }
            result.insert(line.lowercased())
        }
        return result
    }

    private static func cachedFileDate() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: cacheFileURL.path)[.modificationDate]) as? Date
    }

    private static func loadCachedSuffixes() -> Set<String>? {
        guard let data = try? Data(contentsOf: cacheFileURL), let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        let parsedSuffixes = parse(text)
        return parsedSuffixes.isEmpty ? nil : parsedSuffixes
    }

    private static func writeCache(_ data: Data) {
        try? FileManager.default.createDirectory(at: cacheFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: cacheFileURL, options: .atomic)
    }

    /// Covers the most common cases when offline, disabled, or before the first successful
    /// download — not a substitute for the real list (e.g. it has no Greek, Cypriot, or most
    /// other government/academic multi-label suffixes beyond the two explicitly listed here).
    private static let bundledFallbackSuffixes: Set<String> = [
        "com", "org", "net", "edu", "gov", "mil", "int",
        "co.uk", "org.uk", "ac.uk", "gov.uk", "me.uk", "net.uk", "ltd.uk", "plc.uk",
        "co.jp", "or.jp", "ne.jp", "ac.jp", "go.jp",
        "com.au", "net.au", "org.au", "edu.au", "gov.au",
        "co.nz", "org.nz", "net.nz",
        "co.za", "org.za",
        "com.br", "net.br", "org.br",
        "com.cn", "net.cn", "org.cn",
        "co.in", "net.in", "org.in",
        "com.mx", "com.ar", "com.sg", "com.hk",
        "gov.gr", "gov.cy"
    ]
}
