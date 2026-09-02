import XCTest
@testable import HandyApp3

/// `Bundle.appPreferred` is what routes `String(localized:)` table lookups through the in-app
/// language override — `locale:` alone only affects interpolation formatting. This only covers
/// the fallback behavior; whether `Bundle.main.path(forResource:ofType:"lproj")` actually
/// resolves to a real per-language bundle can only be checked on device/in Xcode, since this
/// package target has no resource bundle (see CLAUDE.md).
final class BundleAppPreferredTests: XCTestCase {

    override func tearDown() {
        super.tearDown()
        UserDefaults.standard.removeObject(forKey: AppPreference.languageKey)
    }

    func testNoOverrideFallsBackToMainBundle() {
        UserDefaults.standard.removeObject(forKey: AppPreference.languageKey)
        XCTAssertEqual(Bundle.appPreferred, Bundle.main)
    }

    func testUnknownLanguageCodeFallsBackToMainBundle() {
        UserDefaults.standard.set("xx-unknown", forKey: AppPreference.languageKey)
        XCTAssertEqual(Bundle.appPreferred, Bundle.main)
    }

    func testRepeatedLookupsAreStable() {
        UserDefaults.standard.set("es", forKey: AppPreference.languageKey)
        let first = Bundle.appPreferred
        let second = Bundle.appPreferred
        XCTAssertEqual(first, second)
    }
}
