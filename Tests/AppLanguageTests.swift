import XCTest

final class AppLanguageTests: XCTestCase {
    func testTheMacsLanguageIsUsedUntilOneIsPicked() throws {
        let defaults = try makeIsolatedDefaults()
        XCTAssertEqual(AppLanguage.current(defaults: defaults), .system)
    }

    func testAPickedLanguageIsWhatMacOSReadsAtLaunch() throws {
        let defaults = try makeIsolatedDefaults()
        for language in [AppLanguage.russian, .english] {
            language.store(in: defaults)
            XCTAssertEqual(AppLanguage.current(defaults: defaults), language)
            XCTAssertEqual(
                defaults.stringArray(forKey: AppLanguage.systemLanguagesKey),
                [language.rawValue]
            )
        }
    }

    func testGoingBackToTheMacsLanguageRemovesThePickedOne() throws {
        let defaults = try makeIsolatedDefaults()
        AppLanguage.russian.store(in: defaults)
        AppLanguage.system.store(in: defaults)
        XCTAssertEqual(AppLanguage.current(defaults: defaults), .system)
        // What is left to read is the Mac's own list, from its global domain.
        XCTAssertNotEqual(defaults.stringArray(forKey: AppLanguage.systemLanguagesKey), ["ru"])
        XCTAssertNil(defaults.string(forKey: AppLanguage.defaultsKey))
    }

    func testALanguageSystemSettingsSetForTheAppStays() throws {
        // System Settings writes the same key; only a language the app
        // picked itself is the app's to remove.
        let defaults = try makeIsolatedDefaults()
        defaults.set(["de"], forKey: AppLanguage.systemLanguagesKey)
        AppLanguage.system.store(in: defaults)
        XCTAssertEqual(defaults.stringArray(forKey: AppLanguage.systemLanguagesKey), ["de"])
    }

    func testAStoredValueThatIsNoLanguageCountsAsTheMacs() throws {
        let defaults = try makeIsolatedDefaults()
        defaults.set("tlh", forKey: AppLanguage.defaultsKey)
        XCTAssertEqual(AppLanguage.current(defaults: defaults), .system)
    }

    func testEachLanguageIsNamedInItself() {
        XCTAssertEqual(AppLanguage.english.title, "English")
        XCTAssertEqual(AppLanguage.russian.title, "Русский")
    }

    func testNumbersAreWrittenInTheAppsLanguage() {
        // The test bundle has no catalog, so the app's language is English.
        XCTAssertEqual(AppLanguage.formattingLocale.language.languageCode, .english)
    }
}
