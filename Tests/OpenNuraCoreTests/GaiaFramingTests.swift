import XCTest
@testable import OpenNuraCore

final class GaiaFramingTests: XCTestCase {

    func testRfcommRoundTrip() throws {
        let frame = GaiaFrame(commandId: 0x0006, payload: [0x01, 0x02, 0x03])
        let bytes = [UInt8](frame.rfcommData)
        let response = try GaiaResponse.fromRFCOMM(bytes)
        XCTAssertEqual(response.vendorId, gaiaVendor)
        XCTAssertEqual(response.rawCommandId, 0x0006)
        XCTAssertEqual(response.payload, [0x01, 0x02, 0x03])
    }

    func testBleRoundTrip() {
        let frame = GaiaFrame(commandId: 0x000A, payload: [0xAA, 0xBB])
        let response = GaiaResponse.fromBLE(frame.bleData)
        XCTAssertEqual(response?.vendorId, gaiaVendor)
        XCTAssertEqual(response?.rawCommandId, 0x000A)
        XCTAssertEqual(response?.payload, [0xAA, 0xBB])
    }

    /// Payloads > 255 bytes use the 2-byte length-extension header (flags 0x02).
    func testLengthExtensionRoundTrip() throws {
        let payload = [UInt8](repeating: 0x5A, count: 300)
        let frame = GaiaFrame(commandId: 0x1006, payload: payload)
        let bytes = [UInt8](frame.rfcommData)
        XCTAssertEqual(bytes[2] & 0x02, 0x02, "length-extension flag should be set")
        let response = try GaiaResponse.fromRFCOMM(bytes)
        XCTAssertEqual(response.rawCommandId, 0x1006)
        XCTAssertEqual(response.payload.count, 300)
    }

    func testMalformedFramesRejected() {
        XCTAssertThrowsError(try GaiaResponse.fromRFCOMM([0xFF, 0x01]))       // too short
        XCTAssertThrowsError(try GaiaResponse.fromRFCOMM([0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07])) // bad SOF
        XCTAssertNil(GaiaResponse.fromBLE(Data([0x68])))                       // too short for BLE
    }

    func testCommandIdMaskingAndAckBit() {
        // rawCommandId 0x800A -> masked 0x000A, ack bit set.
        let frame = GaiaFrame(commandId: 0x800A, payload: [0x00])
        let response = GaiaResponse.fromBLE(frame.bleData)
        XCTAssertEqual(response?.commandId, 0x000A)
        XCTAssertEqual(response?.isAck, true)
    }
}
