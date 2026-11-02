import RDPKitAppKit
import XCTest

/// RDPKit's own suite tests RDPKitAppKit's keyboard mapping, and the mapping tests RDPeek had
/// moved there with the input view. This one stays until RDPKit's suite has a test of
/// `isCharacterKey(uncomposed:)` of its own: it checks the function only through the view.
final class RemoteInputMappingTests: XCTestCase {
    /// A key that types text or nothing on its own is a character key, which a dead key typed
    /// right after a chorded one composes; Return, Left Arrow, Delete, Forward Delete and F1
    /// type control characters, and a key the layout data says nothing about is no such key.
    func testACharacterKeyIsOneThatTypesTextOrNothingOnItsOwn() {
        for uncomposed in ["a", "¬", " ", ""] {
            XCTAssertTrue(RDPMacKeyboardMapping.isCharacterKey(uncomposed: uncomposed), uncomposed)
        }
        for uncomposed: String? in ["\r", "\u{1C}", "\u{08}", "\u{7F}", "\u{10}", nil] {
            XCTAssertFalse(RDPMacKeyboardMapping.isCharacterKey(uncomposed: uncomposed), "\(String(describing: uncomposed))")
        }
    }
}
