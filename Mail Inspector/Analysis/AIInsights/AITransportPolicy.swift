//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import Foundation

/// Refuses plain `http://` to anything but a local address, at this app's own HTTP layer —
/// independent of (and a clearer error than relying solely on) OS-level App Transport Security.
/// Loopback/private-use/link-local addresses and `.local`/`localhost` hostnames are allowed over
/// cleartext specifically because that's exactly what a locally-hosted OpenAI-compatible server
/// (LM Studio, Ollama, vLLM, …) typically is — reusing `IPAddressClassifier`, already proven
/// correct for this exact kind of scope check against `Received:` header IPs.
nonisolated enum AITransportPolicy {
    struct InsecureEndpointError: Error, Sendable {}

    static func validate(_ url: URL) throws {
        guard let scheme = url.scheme?.lowercased() else { throw InsecureEndpointError() }
        if scheme == "https" { return }
        guard scheme == "http", isLocalHost(url.host) else {
            throw InsecureEndpointError()
        }
    }

    static func isLocalHost(_ host: String?) -> Bool {
        guard let host, !host.isEmpty else { return false }
        let lowered = host.lowercased()
        if lowered == "localhost" || lowered.hasSuffix(".local") { return true }
        switch IPAddressClassifier.classify(lowered) {
        case .loopback, .privateUse, .linkLocal, .uniqueLocal, .carrierGradeNAT:
            return true
        case .publicAddress, .documentationOrReserved, nil:
            return false
        }
    }
}
