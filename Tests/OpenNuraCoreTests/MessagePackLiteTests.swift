import XCTest
@testable import OpenNuraCore

final class MessagePackLiteTests: XCTestCase {

    func testPrimitiveRoundTrip() {
        let map: [String: Any?] = [
            "int": 42,
            "neg": -7,
            "bool": true,
            "str": "hello",
        ]
        let data = MessagePackLite.serializeMap(map)
        let out = MessagePackLite.deserialize(data) as? [String: Any?]
        XCTAssertEqual(out?["int"] as? Int, 42)
        XCTAssertEqual(out?["neg"] as? Int, -7)
        XCTAssertEqual(out?["bool"] as? Bool, true)
        XCTAssertEqual(out?["str"] as? String, "hello")
    }

    func testNestedMapAndArrayRoundTrip() {
        let map: [String: Any?] = [
            "nested": ["a": 1, "b": "x"] as [String: Any?],
            "list": [1, 2, 3] as [Any?],
        ]
        let data = MessagePackLite.serializeMap(map)
        let out = MessagePackLite.deserialize(data) as? [String: Any?]
        let nested = out?["nested"] as? [String: Any?]
        XCTAssertEqual(nested?["a"] as? Int, 1)
        XCTAssertEqual(nested?["b"] as? String, "x")
        let list = out?["list"] as? [Any?]
        XCTAssertEqual(list?.compactMap { $0 as? Int }, [1, 2, 3])
    }

    /// Regression: a [UInt8] must encode as msgpack BINARY, not as an array of
    /// integers. This was the bug behind the session/start_1 HTTP 500.
    func testByteArrayEncodesAsBinary() {
        let bytes: [UInt8] = [0x68, 0x72, 0x80, 0x04, 0x00]
        let data = MessagePackLite.serializeMap(["b": bytes])
        // The value must round-trip back as [UInt8], which only happens if it
        // was written with a bin marker (0xc4/0xc5/0xc6), not an array marker.
        let out = MessagePackLite.deserialize(data) as? [String: Any?]
        XCTAssertEqual(out?["b"] as? [UInt8], bytes)
        // And the encoded bytes should contain the bin8 marker for a 5-byte blob.
        XCTAssertTrue([UInt8](data).contains(0xc4))
    }

    /// A corrupt/malicious huge length field must not hang or OOM; the decoder
    /// clamps the count to the bytes remaining.
    func testHugeLengthFieldIsClamped() {
        // 0xdd = array32, count = 0xFFFFFFFF, but no elements follow.
        let evil: [UInt8] = [0xdd, 0xFF, 0xFF, 0xFF, 0xFF]
        let value = MessagePackLite.deserialize(Data(evil))
        // Should return promptly (an array), not spin billions of iterations.
        XCTAssertNotNil(value as? [Any?])
    }
}
