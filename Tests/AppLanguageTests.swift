import XCTest

final class AppLanguageTests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        // A run launched with -AppleLanguages, such as a scheme set to
        // another language, answers every read of that key with its own.
        try XCTSkipIf(
            UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)[AppLanguage.systemLanguagesKey] != nil,
            "The test run was launched with -AppleLanguages."
        )
    }

    func testTheMacsLanguageIsUsedUntilOneIsPicked() throws {
        let defaults = try makeIsolatedDefaults()
        XCTAssertEqual(AppLanguage.current(defaults: defaults), .system)
    }

    func testAPickedLanguageIsWhatMacOSReadsAtLaunch() throws {
        let suite = try makeIsolatedSuite()
        for language in [AppLanguage.russian, .english] {
            language.store(in: suite.defaults)
            XCTAssertEqual(AppLanguage.current(defaults: suite.defaults), language)
            XCTAssertEqual(storedLanguages(in: suite), [language.rawValue])
        }
    }

    func testGoingBackToTheMacsLanguageRemovesThePickedOne() throws {
        let suite = try makeIsolatedSuite()
        AppLanguage.russian.store(in: suite.defaults)
        AppLanguage.system.store(in: suite.defaults)
        XCTAssertEqual(AppLanguage.current(defaults: suite.defaults), .system)
        // What is left to read is the Mac's own list, from its global domain.
        XCTAssertNil(storedLanguages(in: suite))
        XCTAssertNil(suite.defaults.string(forKey: AppLanguage.defaultsKey))
    }

    func testALanguageSystemSettingsSetForTheAppStays() throws {
        // System Settings writes the same key; only a language the app
        // picked itself is the app's to remove.
        let suite = try makeIsolatedSuite()
        suite.defaults.set(["de"], forKey: AppLanguage.systemLanguagesKey)
        AppLanguage.system.store(in: suite.defaults)
        XCTAssertEqual(storedLanguages(in: suite), ["de"])
    }

    func testALanguageSystemSettingsSetsLaterReplacesThePickedOne() throws {
        // Picked in RDPeek, then changed for the app in System Settings: the
        // picker says System, and picking System leaves that choice alone.
        let suite = try makeIsolatedSuite()
        AppLanguage.russian.store(in: suite.defaults)
        suite.defaults.set(["de"], forKey: AppLanguage.systemLanguagesKey)
        XCTAssertEqual(AppLanguage.current(defaults: suite.defaults), .system)
        AppLanguage.system.store(in: suite.defaults)
        XCTAssertEqual(storedLanguages(in: suite), ["de"])
    }

    // MARK: - The language RDPeek would start in

    func testAPickedLanguageIsTheOneRDPeekStartsIn() throws {
        let defaults = try makeIsolatedDefaults()
        for language in [AppLanguage.russian, .english] {
            language.store(in: defaults)
            XCTAssertEqual(launchLocalization(defaults), language.rawValue)
        }
    }

    func testRDPeekStartsInTheFirstOfTheLanguagesItHas() throws {
        // A language macOS lists in a region's form, or one RDPeek lacks
        // ahead of one it has.
        let defaults = try makeIsolatedDefaults()
        defaults.set(["ru-RU", "en-US"], forKey: AppLanguage.systemLanguagesKey)
        XCTAssertEqual(launchLocalization(defaults), "ru")
        defaults.set(["de-DE", "en-US"], forKey: AppLanguage.systemLanguagesKey)
        XCTAssertEqual(launchLocalization(defaults), "en")
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

    // MARK: - Helpers

    /// The languages the suite itself holds, not read through to the Mac's.
    private func storedLanguages(in suite: (defaults: UserDefaults, name: String)) -> [String]? {
        suite.defaults.persistentDomain(forName: suite.name)?[AppLanguage.systemLanguagesKey] as? [String]
    }

    /// The localization RDPeek, which has English and Russian, would start in.
    private func launchLocalization(_ defaults: UserDefaults) -> String? {
        AppLanguage.launchLocalization(defaults: defaults, localizations: ["en", "ru"])
    }
}
