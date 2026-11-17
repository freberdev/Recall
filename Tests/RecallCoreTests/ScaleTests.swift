import Foundation
import Testing
@testable import RecallCore

/// Recall keeps the whole history in memory and searches by scanning. These tests hold that
/// design to account at the largest history the settings allow, and at the largest clip.
@MainActor @Suite(.serialized) struct ScaleTests {
    let temp = TempDirectory()
    let limits = Limits(maxCount: 1000, maxAgeDays: nil)

    func elapsed(_ work: () throws -> Void) rethrows -> Duration {
        let clock = ContinuousClock()
        return try clock.measure(work)
    }

    @Test func aFullHistoryLoadsAndSearchesQuickly() throws {
        let words = ["offert", "möte", "brew", "postgres", "idé", "portkod", "ring", "följ upp"]
        let files = temp.files()
        for index in 0..<1000 {
            let text = "\(words[index % words.count]) nummer \(index)\n"
                + String(repeating: "andra raden med lite mer text att söka i ", count: 40)
            try files.write(makeClip(text, at: TimeInterval(index)))
        }
        let store = HistoryStore(files: files, limits: limits)

        let loading = elapsed { store.load(now: date(2000)) }
        #expect(store.clips.count == 1000)
        #expect(loading < .seconds(1), "loading took \(loading)")

        var hits = 0
        let searching = elapsed {
            hits = ClipSearch.filter(store.clips, query: "portkod 9", locale: Locale(identifier: "sv_SE")).count
        }
        #expect(hits > 0)
        #expect(searching < .milliseconds(50), "searching took \(searching)")
    }

    @Test func recordingIntoAFullHistoryIsQuick() throws {
        let store = HistoryStore(files: temp.files(), limits: limits)
        for index in 0..<1000 { store.record("clip number \(index)", now: date(TimeInterval(index))) }

        let recording = elapsed { store.record("one more", now: date(5000)) }

        #expect(store.clips.count == 1000)
        #expect(store.clips.first?.text == "one more")
        #expect(recording < .milliseconds(50), "recording took \(recording)")
    }

    @Test func theLargestClipIsRecordedQuicklyAndComesBackWhole() throws {
        let store = HistoryStore(files: temp.files(), limits: limits)
        let text = String(repeating: "x", count: CaptureRule.maxBytes)
        #expect(CaptureRule.text(from: text) != nil)

        let recording = elapsed { store.record(text, now: date(1)) }
        #expect(recording < .milliseconds(200), "recording took \(recording)")
        #expect(!store.saveFailed)

        let later = HistoryStore(files: temp.files(), limits: limits)
        later.load(now: date(2))
        #expect(later.clips.first?.text.utf8.count == CaptureRule.maxBytes)
    }

    @Test func aScreenSizedImageIsCapturedAndStoredQuickly() throws {
        let store = HistoryStore(files: temp.files(), limits: limits)
        // The size of a large laptop screen, as the uncompressed TIFF some apps put on the clipboard.
        let tiff = makeImageData(width: 3456, height: 2234, type: "public.tiff")
        #expect(tiff.count > 20_000_000)

        var captured: CapturedImage?
        let capturing = elapsed { captured = ImageCodec.capture(tiff, maxBytes: limits.maxImageBytes) }
        let image = try #require(captured)
        #expect(capturing < .seconds(1), "capturing took \(capturing)")

        let recording = elapsed { store.record(image: image, now: date(1)) }
        #expect(recording < .milliseconds(200), "recording took \(recording)")
        #expect(store.clips.first?.image?.width == 3456)
    }

    @Test func theLargestImageIsStoredAndReadBackQuickly() throws {
        let store = HistoryStore(files: temp.files(), limits: limits)
        // Noise does not compress, so the PNG is close to the ten megabyte limit.
        let png = makeNoiseImageData(side: 1800)
        #expect(png.count > 9_000_000 && png.count < limits.maxImageBytes)
        let image = try #require(ImageCodec.capture(png, maxBytes: limits.maxImageBytes))

        var clip: Clip?
        let recording = elapsed { clip = store.record(image: image, now: date(1)) }
        #expect(recording < .milliseconds(300), "recording took \(recording)")

        var data: Data?
        let reading = elapsed { data = store.imageData(for: try! #require(clip).id) }
        #expect(reading < .milliseconds(300), "reading took \(reading)")
        #expect(data == png)
    }
}
