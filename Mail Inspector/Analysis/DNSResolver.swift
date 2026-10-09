//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import Foundation
import dnssd

/// Low-level async DNS queries (TXT, A, AAAA, MX) via `dnssd`'s `DNSServiceQueryRecord`, used
/// only by the opt-in, manually-triggered SPF recheck feature. Never called automatically.
nonisolated enum DNSResolver {
    enum DNSRecordType: UInt16 {
        case a = 1
        case mx = 15
        case txt = 16
        case aaaa = 28
    }

    enum DNSError: Error, Sendable {
        case serviceCreateFailed(Int32)
        case timeout
        case queryFailed(Int32)
    }

    /// Returns the raw rdata for every answer received for `name`/`type`, within `timeoutSeconds`.
    static func queryRaw(_ name: String, type: DNSRecordType, timeoutSeconds: Double = 5) async throws -> [Data] {
        try await Task.detached(priority: .userInitiated) {
            try performQuery(name: name, rrtype: type.rawValue, timeoutSeconds: timeoutSeconds)
        }.value
    }

    private final class QueryBox {
        var answers: [Data] = []
        var finished = false
        var errorCode: Int32 = 0
    }

    private static func performQuery(name: String, rrtype: UInt16, timeoutSeconds: Double) throws -> [Data] {
        let box = QueryBox()
        let boxPointer = Unmanaged.passRetained(box).toOpaque()
        defer { Unmanaged<QueryBox>.fromOpaque(boxPointer).release() }

        let callback: DNSServiceQueryRecordReply = { _, flags, _, errorCode, _, _, _, rdlen, rdata, _, context in
            guard let context else { return }
            let box = Unmanaged<QueryBox>.fromOpaque(context).takeUnretainedValue()
            if errorCode == kDNSServiceErr_NoError, let rdata, rdlen > 0 {
                box.answers.append(Data(bytes: rdata, count: Int(rdlen)))
            } else if errorCode != kDNSServiceErr_NoError {
                box.errorCode = errorCode
            }
            if (flags & kDNSServiceFlagsMoreComing) == 0 {
                box.finished = true
            }
        }

        var sdRef: DNSServiceRef?
        let status = DNSServiceQueryRecord(&sdRef, 0, 0, name, rrtype, UInt16(kDNSServiceClass_IN), callback, boxPointer)
        guard status == kDNSServiceErr_NoError, let sdRef else {
            throw DNSError.serviceCreateFailed(status)
        }
        defer { DNSServiceRefDeallocate(sdRef) }

        let fd = DNSServiceRefSockFD(sdRef)
        guard fd >= 0 else { throw DNSError.serviceCreateFailed(-1) }

        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while !box.finished {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { throw DNSError.timeout }

            var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let pollResult = poll(&pfd, 1, Int32(remaining * 1000))
            if pollResult == 0 { throw DNSError.timeout }
            if pollResult < 0 { continue }

            let processStatus = DNSServiceProcessResult(sdRef)
            guard processStatus == kDNSServiceErr_NoError else {
                throw DNSError.queryFailed(processStatus)
            }
        }

        if box.answers.isEmpty, box.errorCode != 0 {
            throw DNSError.queryFailed(box.errorCode)
        }
        return box.answers
    }

    /// Splits a TXT record's rdata into its character-strings (each prefixed with a length
    /// byte) and joins them, per RFC 1035 §3.3.14 — a single logical TXT value is often split
    /// across several of these when it's long (SPF records commonly are).
    static func decodeTXT(_ data: Data) -> String {
        var result = ""
        var index = data.startIndex
        while index < data.endIndex {
            let length = Int(data[index])
            index = data.index(after: index)
            guard index + length <= data.endIndex, length > 0 else { break }
            let chunk = data[index..<data.index(index, offsetBy: length)]
            result += String(decoding: chunk, as: UTF8.self)
            index = data.index(index, offsetBy: length)
        }
        return result
    }
}
