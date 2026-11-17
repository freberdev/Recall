import Testing
@testable import RecallCore

@Suite struct KeyRouterTests {
    // Virtual key codes (ANSI layout positions).
    static let escape: UInt16 = 53, returnKey: UInt16 = 36, enter: UInt16 = 76
    static let up: UInt16 = 126, down: UInt16 = 125, delete: UInt16 = 51
    static let c: UInt16 = 8, q: UInt16 = 12, w: UInt16 = 13, comma: UInt16 = 43
    static let a: UInt16 = 0, v: UInt16 = 9, z: UInt16 = 6

    /// The character each of these keys produces on a US keyboard.
    static let usCharacters: [UInt16: String] = [
        c: "c", q: "q", w: "w", comma: ",", a: "a", v: "v", z: "z",
    ]

    static func press(_ key: UInt16, _ modifiers: KeyModifiers = []) -> KeyPress {
        KeyPress(keyCode: key, modifiers: modifiers, character: usCharacters[key])
    }

    func route(_ key: UInt16, _ modifiers: KeyModifiers = [], focus: HistoryList.Focus) -> KeyCommand? {
        KeyRouter.command(for: Self.press(key, modifiers), focus: focus)
    }

    @Test(arguments: [HistoryList.Focus.search, .list])
    func keysThatDoTheSameWhereverFocusIs(_ focus: HistoryList.Focus) {
        #expect(route(Self.escape, focus: focus) == .close)
        #expect(route(Self.w, .command, focus: focus) == .close)
        #expect(route(Self.q, .command, focus: focus) == .close)
        #expect(route(Self.down, focus: focus) == .moveDown)
        #expect(route(Self.up, focus: focus) == .moveUp)
        #expect(route(Self.returnKey, focus: focus) == .copySelected)
        #expect(route(Self.enter, focus: focus) == .copySelected)
        #expect(route(Self.comma, .command, focus: focus) == .settings)
    }

    @Test func commandDeleteRemovesAClipOnlyWhenTheListHasFocus() {
        #expect(route(Self.delete, .command, focus: .list) == .deleteSelected)
        #expect(route(Self.delete, .command, focus: .search) == nil)
    }

    @Test func commandCCopiesAClipOnlyWhenTheListHasFocus() {
        #expect(route(Self.c, .command, focus: .list) == .copySelected)
        #expect(route(Self.c, .command, focus: .search) == nil)
    }

    @Test(arguments: [HistoryList.Focus.search, .list])
    func ordinaryEditingKeysAreLeftToTheSearchField(_ focus: HistoryList.Focus) {
        #expect(route(Self.a, focus: focus) == nil)
        #expect(route(Self.a, .command, focus: focus) == nil)
        #expect(route(Self.v, .command, focus: focus) == nil)
        #expect(route(Self.z, .command, focus: focus) == nil)
        #expect(route(Self.delete, focus: focus) == nil)
        #expect(route(Self.delete, .option, focus: focus) == nil)
        #expect(route(Self.returnKey, .shift, focus: focus) == nil)
        #expect(route(Self.down, .shift, focus: focus) == nil)
        #expect(route(Self.escape, .command, focus: focus) == nil)
    }

    @Test func lettersFollowTheKeyboardLayoutNotTheKeyPosition() {
        // On a French keyboard the key in the US "Q" position types "a", and the reverse.
        let frenchA = KeyPress(keyCode: Self.q, modifiers: .command, character: "a")
        let frenchQ = KeyPress(keyCode: Self.a, modifiers: .command, character: "q")
        #expect(KeyRouter.command(for: frenchA, focus: .search) == nil)
        #expect(KeyRouter.command(for: frenchQ, focus: .search) == .close)
        // The key that types "w" on a French keyboard sits in the US "Z" position.
        let frenchW = KeyPress(keyCode: Self.z, modifiers: .command, character: "w")
        #expect(KeyRouter.command(for: frenchW, focus: .list) == .close)
    }

    @Test func upperCaseCharactersMatchToo() {
        let capsLock = KeyPress(keyCode: Self.w, modifiers: .command, character: "W")
        #expect(KeyRouter.command(for: capsLock, focus: .search) == .close)
    }

    @Test func aKeyWithoutACharacterMatchesNothingByLetter() {
        let unknown = KeyPress(keyCode: Self.w, modifiers: .command, character: nil)
        #expect(KeyRouter.command(for: unknown, focus: .search) == nil)
    }

    @Test func theFallbackCharactersCoverEveryLetterInTheTable() {
        #expect(KeyRouter.usCharacters[Self.c] == "c")
        #expect(KeyRouter.usCharacters[Self.q] == "q")
        #expect(KeyRouter.usCharacters[Self.w] == "w")
        #expect(KeyRouter.usCharacters[Self.comma] == ",")
    }

    @Test func onlyMovingTheSelectionRepeatsWhenAKeyIsHeld() {
        #expect(KeyRouter.repeatsWhenHeld(.moveUp))
        #expect(KeyRouter.repeatsWhenHeld(.moveDown))
        for command in [KeyCommand.close, .copySelected, .deleteSelected, .settings] {
            #expect(!KeyRouter.repeatsWhenHeld(command))
        }
    }

    @Test func aHeldCommandDeleteIsSwallowedWhereverFocusIs() {
        // Deleting the last row moves focus to the search field. The repeats of the same
        // key press must not go on to clear the search text.
        #expect(KeyRouter.swallowsRepeat(Self.press(Self.delete, .command)))
        #expect(!KeyRouter.swallowsRepeat(Self.press(Self.delete)))
        #expect(!KeyRouter.swallowsRepeat(Self.press(Self.a)))
        #expect(!KeyRouter.swallowsRepeat(Self.press(Self.down)))
    }

    @Test func typingWhileTheListHasFocusGoesBackToTheSearchField() {
        #expect(KeyRouter.returnsFocusToSearch(Self.press(Self.a), focus: .list))
        #expect(KeyRouter.returnsFocusToSearch(Self.press(Self.a, .shift), focus: .list))
        #expect(KeyRouter.returnsFocusToSearch(Self.press(Self.delete), focus: .list))
        #expect(KeyRouter.returnsFocusToSearch(Self.press(Self.a, .option), focus: .list))
    }

    @Test func keysInTheTableAndCommandKeysDoNotMoveFocus() {
        #expect(!KeyRouter.returnsFocusToSearch(Self.press(Self.down), focus: .list))
        #expect(!KeyRouter.returnsFocusToSearch(Self.press(Self.delete, .command), focus: .list))
        #expect(!KeyRouter.returnsFocusToSearch(Self.press(Self.a, .command), focus: .list))
        #expect(!KeyRouter.returnsFocusToSearch(Self.press(Self.a, .control), focus: .list))
        #expect(!KeyRouter.returnsFocusToSearch(Self.press(Self.a), focus: .search))
    }
}
