import Foundation
import Testing
@testable import RecallCore

@Suite struct ClipSearchTests {
    let swedish = Locale(identifier: "sv_SE")
    let clips = [
        makeClip("git rebase -i HEAD~3", at: 4),
        makeClip("https://example.com/Offert-2026.pdf", at: 3),
        makeClip("Storgatan 12\n123 45 Tyresö\nportkod 4471", at: 2),
        makeClip("Crème brûlée och RÄKSMÖRGÅS", at: 1),
    ]

    func search(_ query: String) -> [String] {
        ClipSearch.filter(clips, query: query, locale: swedish).map(\.text)
    }

    @Test func anEmptyQueryMatchesEverythingInOrder() {
        #expect(ClipSearch.filter(clips, query: "", locale: swedish) == clips)
        #expect(ClipSearch.filter(clips, query: "  \n ", locale: swedish) == clips)
    }

    @Test func aWordAnywhereInTheTextMatches() {
        #expect(search("rebase") == ["git rebase -i HEAD~3"])
        #expect(search("portkod").count == 1)
        #expect(search("example.com").count == 1)
    }

    @Test func caseDoesNotMatter() {
        #expect(search("OFFERT").count == 1)
        #expect(search("räksmörgås").count == 1)
        #expect(search("head").count == 1)
    }

    @Test func accentsDoNotMatter() {
        #expect(search("creme brulee").count == 1)
        #expect(search("tyreso").count == 1)
        #expect(search("raksmorgas").count == 1)
    }

    @Test func everyWordMustMatchButInAnyOrder() {
        #expect(search("4471 storgatan").count == 1)
        #expect(search("storgatan rebase").isEmpty)
    }

    @Test func wordsMayMatchAcrossLines() {
        #expect(search("12 tyresö portkod").count == 1)
    }

    @Test func partsOfWordsMatch() {
        #expect(search("reb").count == 1)
        #expect(search("xyz").isEmpty)
    }

    @Test func theOrderOfTheHistoryIsKept() {
        #expect(search("e") == clips.map(\.text))
    }

    @Test func charactersWithMeaningInPatternsAreSearchedLiterally() {
        #expect(search("HEAD~3").count == 1)
        #expect(search(".*").isEmpty)
        #expect(search("-i").count == 1)
    }
}

@Suite struct ClipPreviewTests {
    @Test func shortTextIsShownAsItIs() {
        #expect(ClipPreview.line(for: "git status") == "git status")
    }

    @Test func surroundingWhitespaceIsRemoved() {
        #expect(ClipPreview.line(for: "  \n\t padded  \n") == "padded")
    }

    @Test func lineBreaksAndRunsOfWhitespaceBecomeSingleSpaces() {
        #expect(ClipPreview.line(for: "Storgatan 12\n123 45   Tyresö\r\n\r\nportkod\t4471")
            == "Storgatan 12 123 45 Tyresö portkod 4471")
    }

    @Test func longTextIsCutWithAnEllipsis() {
        let line = ClipPreview.line(for: String(repeating: "abcdefghij", count: 50), limit: 20)
        #expect(line.count == 20)
        #expect(line.hasSuffix("…"))
        #expect(line.hasPrefix("abcdefghijabcdefghi"))
    }

    @Test func textExactlyAtTheLimitIsNotCut() {
        let text = String(repeating: "a", count: 20)
        #expect(ClipPreview.line(for: text, limit: 20) == text)
    }

    @Test func emptyAndBlankTextGiveAnEmptyLine() {
        #expect(ClipPreview.line(for: "") == "")
        #expect(ClipPreview.line(for: " \n ") == "")
    }

    @Test func emojiAndCombinedCharactersAreNotSplit() {
        let line = ClipPreview.line(for: "👨‍👩‍👧‍👦👨‍👩‍👧‍👦👨‍👩‍👧‍👦👨‍👩‍👧‍👦", limit: 3)
        #expect(line == "👨‍👩‍👧‍👦👨‍👩‍👧‍👦…")
    }

    @Test func aVeryLargeTextIsOnlyReadAtTheStart() {
        let huge = String(repeating: "word ", count: 400_000)
        let clock = ContinuousClock()
        var line = ""
        let elapsed = clock.measure { line = ClipPreview.line(for: huge) }
        #expect(line.count == 160)
        #expect(elapsed < .milliseconds(20), "took \(elapsed)")
    }

    @Test func aTextThatStartsWithALotOfWhitespaceStillGivesAPreview() {
        let text = String(repeating: "\n", count: 500) + "finally"
        #expect(ClipPreview.line(for: text) == "finally")
    }
}
