import Foundation
import Testing
@testable import RecallCore

@Suite struct ShortcutTests {
    @Test func defaultIsCommandShiftV() {
        #expect(Shortcut.default.keyCode == 9)
        #expect(Shortcut.default.modifiers == [.command, .shift])
        #expect(Shortcut.default.isValid)
    }

    @Test func optionAloneIsInvalid() {
        #expect(!Shortcut(keyCode: 38, modifiers: .option).isValid)
    }

    @Test func optionShiftIsInvalid() {
        #expect(!Shortcut(keyCode: 38, modifiers: [.option, .shift]).isValid)
    }

    @Test func noModifiersIsInvalid() {
        #expect(!Shortcut(keyCode: 38, modifiers: []).isValid)
    }

    @Test func controlIsValid() {
        #expect(Shortcut(keyCode: 38, modifiers: [.control, .option]).isValid)
    }

    @Test func carbonModifiersForDefault() {
        #expect(Shortcut.default.carbonModifiers == 0x0300)
    }

    @Test func carbonModifiersForAllFour() {
        let all = Shortcut(keyCode: 0, modifiers: [.command, .shift, .option, .control])
        #expect(all.carbonModifiers == 0x1B00)
    }

    @Test func symbolsAreInAppleOrder() {
        let all = Shortcut(keyCode: 0, modifiers: [.command, .shift, .option, .control])
        #expect(all.modifierSymbols == "⌃⌥⇧⌘")
        #expect(Shortcut.default.modifierSymbols == "⇧⌘")
    }

    @Test func codableRoundTrip() throws {
        let shortcut = Shortcut(keyCode: 49, modifiers: [.control, .option])
        let data = try JSONEncoder().encode(shortcut)
        #expect(try JSONDecoder().decode(Shortcut.self, from: data) == shortcut)
    }
}

@Suite struct PreferencesTests {
    let suiteName = "recall-tests-\(UUID().uuidString)"
    var defaults: UserDefaults { UserDefaults(suiteName: suiteName)! }
    var preferences: Preferences { Preferences(defaults: defaults) }

    @Test func shortcutDefaultsToCommandShiftV() {
        defer { defaults.removePersistentDomain(forName: suiteName) }
        #expect(preferences.shortcut == .default)
    }

    @Test func shortcutPersists() {
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let chosen = Shortcut(keyCode: 49, modifiers: [.control, .option])
        preferences.shortcut = chosen
        #expect(Preferences(defaults: defaults).shortcut == chosen)
    }

    @Test func garbageShortcutFallsBackToDefault() {
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(Data("not json".utf8), forKey: "shortcut")
        #expect(preferences.shortcut == .default)
        defaults.set("a string", forKey: "shortcut")
        #expect(preferences.shortcut == .default)
    }

    @Test func invalidStoredShortcutFallsBackToDefault() throws {
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let optionOnly = try JSONEncoder().encode(Shortcut(keyCode: 38, modifiers: .option))
        defaults.set(optionOnly, forKey: "shortcut")
        #expect(preferences.shortcut == .default)
    }

    @Test func flagsDefaultToFalseAndPersist() {
        defer { defaults.removePersistentDomain(forName: suiteName) }
        #expect(!preferences.didAutoEnableLoginItem)
        #expect(!preferences.hasShownWelcome)
        preferences.didAutoEnableLoginItem = true
        preferences.hasShownWelcome = true
        #expect(Preferences(defaults: defaults).didAutoEnableLoginItem)
        #expect(Preferences(defaults: defaults).hasShownWelcome)
    }

    @Test func pausedDefaultsToFalseAndPersists() {
        defer { defaults.removePersistentDomain(forName: suiteName) }
        #expect(!preferences.isPaused)
        preferences.isPaused = true
        #expect(Preferences(defaults: defaults).isPaused)
    }

    @Test func limitsDefaultToFiveHundredClipsAndThirtyDays() {
        defer { defaults.removePersistentDomain(forName: suiteName) }
        #expect(preferences.limits == Limits(maxCount: 500, maxAgeDays: 30))
        #expect(preferences.limits == .default)
    }

    @Test func limitsPersist() {
        defer { defaults.removePersistentDomain(forName: suiteName) }
        preferences.limits = Limits(maxCount: 100, maxAgeDays: 7)
        #expect(Preferences(defaults: defaults).limits == Limits(maxCount: 100, maxAgeDays: 7))
    }

    @Test func keepingForeverPersists() {
        defer { defaults.removePersistentDomain(forName: suiteName) }
        preferences.limits = Limits(maxCount: 1000, maxAgeDays: nil)
        #expect(Preferences(defaults: defaults).limits == Limits(maxCount: 1000, maxAgeDays: nil))
    }

    @Test func storedLimitsThatAreNotAmongTheChoicesFallBackToTheDefault() {
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(7, forKey: "maxCount")
        defaults.set(-3, forKey: "maxAgeDays")
        #expect(preferences.limits == .default)
        defaults.set("many", forKey: "maxCount")
        defaults.set(12, forKey: "maxAgeDays")
        #expect(preferences.limits == .default)
    }

    @Test func everyChoiceOfferedInSettingsCanBeStored() {
        defer { defaults.removePersistentDomain(forName: suiteName) }
        for count in Limits.countChoices {
            for days in Limits.ageChoices {
                preferences.limits = Limits(maxCount: count, maxAgeDays: days)
                #expect(preferences.limits == Limits(maxCount: count, maxAgeDays: days))
            }
        }
    }
}
