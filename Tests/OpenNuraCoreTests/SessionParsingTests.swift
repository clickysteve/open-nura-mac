import XCTest
@testable import OpenNuraCore

final class SessionParsingTests: XCTestCase {

    /// A session/start response carries the session id, the next endpoint
    /// (finalEvent), and packets to relay over Bluetooth.
    func testParseSessionStart() throws {
        let body: [String: Any?] = [
            "d": [
                "a": [
                    ["t": "t", "c": "session", "d": 42] as [String: Any?],
                    ["t": "f", "e": "session/start_1"] as [String: Any?],
                    ["t": "u", "p": [
                        ["e": false, "a": false, "m": false, "b": [UInt8]([0x01, 0x02])] as [String: Any?]
                    ] as [Any?]] as [String: Any?],
                ] as [Any?]
            ] as [String: Any?]
        ]
        let details = try XCTUnwrap(NuraSessionStartResponseParser.parse(body))
        XCTAssertEqual(details.sessionId, 42)
        XCTAssertEqual(details.finalEvent, "session/start_1")
        XCTAssertEqual(details.packets.count, 1)
        XCTAssertEqual(details.packets.first?.payloadBytes, [0x01, 0x02])
    }

    /// app_enc.key arrives as a typed action; a binary value is surfaced base64.
    func testExtractAppEncKeyBinary() {
        let raw: [UInt8] = Array(repeating: 0xAB, count: 16)
        let expected = Data(raw).base64EncodedString()
        let body: [String: Any?] = [
            "d": [
                "a": [
                    ["t": "t", "c": "app_enc", "d": ["key": raw] as [String: Any?]] as [String: Any?]
                ] as [Any?]
            ] as [String: Any?]
        ]
        let snap = NuraAuthResponseParser.extract(body)
        XCTAssertEqual(snap.appEncKey, expected)
    }

    func testExtractUserSessionId() {
        let body: [String: Any?] = [
            "d": [
                "a": [
                    ["t": "t", "c": "user_session_status", "d": ["id": 9999] as [String: Any?]] as [String: Any?]
                ] as [Any?]
            ] as [String: Any?]
        ]
        let snap = NuraAuthResponseParser.extract(body)
        XCTAssertEqual(snap.userSessionId, 9999)
    }
}
