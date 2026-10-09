//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import Testing
import Foundation
@testable import Mail_Inspector

/// Tests for `AITransportPolicy`: HTTPS is always allowed; plain `http://` is only allowed to a
/// local address (loopback, private-use/LAN, `.local`/`localhost`) — exactly the case a
/// locally-hosted OpenAI-compatible server (LM Studio, Ollama, vLLM, …) needs, and nothing else.
@Suite("AITransportPolicy")
struct AITransportPolicyTests {
    @Test("Always allows HTTPS, regardless of host")
    func allowsHTTPS() throws {
        #expect(throws: Never.self) {
            try AITransportPolicy.validate(try #require(URL(string: "https://api.openai.com/v1/chat/completions")))
        }
    }

    @Test("Allows plain HTTP to localhost")
    func allowsHTTPToLocalhost() throws {
        #expect(throws: Never.self) {
            try AITransportPolicy.validate(try #require(URL(string: "http://localhost:1234/v1/chat/completions")))
        }
    }

    @Test("Allows plain HTTP to a loopback IP literal")
    func allowsHTTPToLoopbackIP() throws {
        #expect(throws: Never.self) {
            try AITransportPolicy.validate(try #require(URL(string: "http://127.0.0.1:1234/v1/chat/completions")))
        }
    }

    @Test("Allows plain HTTP to a private-use LAN address")
    func allowsHTTPToLANAddress() throws {
        #expect(throws: Never.self) {
            try AITransportPolicy.validate(try #require(URL(string: "http://192.168.1.50:11434/v1/chat/completions")))
        }
    }

    @Test("Allows plain HTTP to a .local hostname")
    func allowsHTTPToDotLocalHostname() throws {
        #expect(throws: Never.self) {
            try AITransportPolicy.validate(try #require(URL(string: "http://my-mac.local:1234/v1/chat/completions")))
        }
    }

    @Test("Refuses plain HTTP to a public internet host")
    func refusesHTTPToPublicHost() throws {
        #expect(throws: AITransportPolicy.InsecureEndpointError.self) {
            try AITransportPolicy.validate(try #require(URL(string: "http://example.com/v1/chat/completions")))
        }
    }

    @Test("Refuses plain HTTP to a public IP address")
    func refusesHTTPToPublicIP() throws {
        #expect(throws: AITransportPolicy.InsecureEndpointError.self) {
            try AITransportPolicy.validate(try #require(URL(string: "http://8.8.8.8/v1/chat/completions")))
        }
    }
}
