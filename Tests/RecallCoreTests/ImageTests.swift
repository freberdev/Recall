import Foundation
import Testing
@testable import RecallCore

@Suite struct ImageCodecTests {
    let roomy = 10_000_000

    @Test func aPNGIsKeptAsItIs() throws {
        let png = makeImageData(width: 40, height: 30, type: "public.png")
        let image = try #require(ImageCodec.capture(png, maxBytes: roomy))
        #expect(image.data == png)
        #expect(image.info.format == .png)
        #expect(image.info.width == 40)
        #expect(image.info.height == 30)
        #expect(image.info.byteCount == png.count)
    }

    @Test func aJPEGIsKeptAsItIs() throws {
        let jpeg = makeImageData(type: "public.jpeg")
        let image = try #require(ImageCodec.capture(jpeg, maxBytes: roomy))
        #expect(image.data == jpeg)
        #expect(image.info.format == .jpeg)
    }

    @Test func aTIFFIsStoredAsPNGOfTheSameSize() throws {
        let tiff = makeImageData(width: 200, height: 120, type: "public.tiff")
        let image = try #require(ImageCodec.capture(tiff, maxBytes: roomy))
        #expect(image.info.format == .png)
        #expect(image.data.starts(with: [0x89, 0x50, 0x4E, 0x47]))
        #expect(image.data.count < tiff.count)
        let size = try #require(pixelSize(of: image.data))
        #expect(size == (200, 120))
        #expect(image.info.width == 200)
        #expect(image.info.height == 120)
    }

    @Test func theSameTIFFAlwaysGivesTheSamePNG() throws {
        let tiff = makeImageData(type: "public.tiff")
        let first = try #require(ImageCodec.capture(tiff, maxBytes: roomy))
        let second = try #require(ImageCodec.capture(tiff, maxBytes: roomy))
        #expect(first.info.digest == second.info.digest)
    }

    @Test func theThumbnailIsASmallPNGWithTheSameProportions() throws {
        let image = try #require(ImageCodec.capture(makeImageData(width: 800, height: 400), maxBytes: roomy))
        let size = try #require(pixelSize(of: image.info.thumbnail))
        #expect(size == (160, 80))
        #expect(image.info.thumbnail.starts(with: [0x89, 0x50, 0x4E, 0x47]))
    }

    @Test func aPictureSmallerThanTheThumbnailIsNotEnlargedBeyondIt() throws {
        let image = try #require(ImageCodec.capture(makeImageData(width: 20, height: 10), maxBytes: roomy))
        let size = try #require(pixelSize(of: image.info.thumbnail))
        #expect(size.width <= ImageCodec.thumbnailSize && size.height <= ImageCodec.thumbnailSize)
    }

    @Test func differentPicturesHaveDifferentFingerprints() throws {
        let first = try #require(ImageCodec.capture(makeImageData(shade: 10), maxBytes: roomy))
        let second = try #require(ImageCodec.capture(makeImageData(shade: 200), maxBytes: roomy))
        #expect(first.info.digest != second.info.digest)
        #expect(first.info.digest.count == 64)
    }

    @Test func anImageLargerThanTheLimitIsNotKept() {
        let png = makeImageData(width: 300, height: 300)
        #expect(ImageCodec.capture(png, maxBytes: png.count) != nil)
        #expect(ImageCodec.capture(png, maxBytes: png.count - 1) == nil)
    }

    @Test func theLimitAppliesToWhatIsStoredNotToWhatWasOnTheClipboard() throws {
        // An uncompressed TIFF is far larger than the PNG it is stored as.
        let tiff = makeImageData(width: 400, height: 400, type: "public.tiff")
        let stored = try #require(ImageCodec.capture(tiff, maxBytes: roomy)).data.count
        #expect(stored < tiff.count / 4)
        #expect(ImageCodec.capture(tiff, maxBytes: stored) != nil)
    }

    @Test func clipboardDataBeyondTheRawLimitIsNotEvenDecoded() {
        let tiff = makeImageData(width: 400, height: 400, type: "public.tiff")
        #expect(ImageCodec.capture(tiff, maxBytes: roomy, maxRawBytes: tiff.count) != nil)
        #expect(ImageCodec.capture(tiff, maxBytes: roomy, maxRawBytes: tiff.count - 1) == nil)
    }

    @Test func whatIsNotAnImageIsNotKept() {
        #expect(ImageCodec.capture(Data(), maxBytes: roomy) == nil)
        #expect(ImageCodec.capture(Data("not an image at all".utf8), maxBytes: roomy) == nil)
        #expect(ImageCodec.capture(makeImageData().prefix(20), maxBytes: roomy) == nil)
    }
}

@Suite struct ImageFilesTests {
    let temp = TempDirectory()
    var files: ClipFiles { temp.files() }

    func makeImageClip(_ image: CapturedImage = makeCapturedImage(), at seconds: TimeInterval = 0) -> Clip {
        Clip(image: image.info, now: date(seconds))
    }

    @Test func anImageComesBackAsItWasWritten() throws {
        let image = makeCapturedImage()
        let clip = makeImageClip(image)
        try files.writeImage(image.data, id: clip.id)
        try files.write(clip)

        #expect(files.loadAll() == [clip])
        #expect(files.readImage(id: clip.id) == image.data)
        #expect(temp.fileNames() == ["\(clip.id.uuidString).clip", "\(clip.id.uuidString).image"])
    }

    @Test func theImageIsNotReadableOnDisk() throws {
        let image = makeCapturedImage()
        let clip = makeImageClip(image)
        try files.writeImage(image.data, id: clip.id)
        try files.write(clip)

        let raw = try Data(contentsOf: files.imageURL(for: clip.id))
        #expect(raw.starts(with: Data("RCI1".utf8)))
        #expect(raw.range(of: Data([0x89, 0x50, 0x4E, 0x47])) == nil)
        #expect(raw.range(of: image.data.prefix(64)) == nil)
        // The small picture for the list is inside the encrypted clip file, not beside it.
        let clipFile = try Data(contentsOf: files.url(for: clip.id))
        #expect(clipFile.range(of: image.info.thumbnail.prefix(32)) == nil)
    }

    @Test func onlyTheUserCanReadTheImageFile() throws {
        let image = makeCapturedImage()
        let id = UUID()
        try files.writeImage(image.data, id: id)
        let attributes = try FileManager.default.attributesOfItem(atPath: files.imageURL(for: id).path)
        #expect(attributes[.posixPermissions] as? Int == 0o600)
    }

    @Test func anotherKeyCannotOpenTheImage() throws {
        let image = makeCapturedImage()
        let id = UUID()
        try files.writeImage(image.data, id: id)
        #expect(temp.files(key: otherKey).readImage(id: id) == nil)
    }

    @Test func aClipFileCannotPassForAnImageFile() throws {
        let clip = makeClip("some text")
        try files.write(clip)
        try FileManager.default.copyItem(at: files.url(for: clip.id), to: files.imageURL(for: clip.id))
        #expect(files.readImage(id: clip.id) == nil)
    }

    @Test func deletingAnImageClipRemovesBothFiles() throws {
        let image = makeCapturedImage()
        let clip = makeImageClip(image)
        try files.writeImage(image.data, id: clip.id)
        try files.write(clip)
        try files.delete(id: clip.id)
        #expect(temp.fileNames().isEmpty)
    }

    @Test func deleteAllRemovesImagesToo() throws {
        let image = makeCapturedImage()
        let clip = makeImageClip(image)
        try files.writeImage(image.data, id: clip.id)
        try files.write(clip)
        try temp.files(key: otherKey).writeImage(image.data, id: UUID())
        try files.write(makeClip("text"))
        #expect(files.fileCount == 4)

        try files.deleteAll()
        #expect(temp.fileNames().isEmpty)
    }

    @Test func anImageWithoutItsClipIsRemovedOnLoad() throws {
        try files.writeImage(makeCapturedImage().data, id: UUID())
        #expect(temp.fileNames().count == 1)
        _ = files.loadAll()
        #expect(temp.fileNames().isEmpty)
    }

    @Test func anImageClipWithoutItsImageIsSkipped() throws {
        let image = makeCapturedImage()
        let clip = makeImageClip(image)
        try files.write(clip)
        #expect(files.loadAll().isEmpty)

        try files.writeImage(image.data, id: clip.id)
        #expect(files.loadAll() == [clip])
    }

    @Test func leftoverTemporaryImageFilesAreRemovedOnLoad() throws {
        try files.write(makeClip("one"))
        let leftover = temp.history.appendingPathComponent(".\(UUID().uuidString).image.tmp")
        try Data("half".utf8).write(to: leftover)
        _ = files.loadAll()
        #expect(!FileManager.default.fileExists(atPath: leftover.path))
    }

    @Test func withoutAKeyNoImageIsReadOrWritten() throws {
        let locked = ClipFiles(directory: temp.history, cipher: nil)
        #expect(throws: ClipFiles.Failure.noKey) { try locked.writeImage(makeCapturedImage().data, id: UUID()) }
        #expect(locked.readImage(id: UUID()) == nil)
    }
}

@MainActor @Suite struct ImageHistoryTests {
    let temp = TempDirectory()

    func makeStore(_ limits: Limits = Limits(maxCount: 100, maxAgeDays: nil, maxImageCount: 10)) -> HistoryStore {
        HistoryStore(files: temp.files(), limits: limits)
    }

    func restarted(_ limits: Limits = Limits(maxCount: 100, maxAgeDays: nil, maxImageCount: 10)) -> HistoryStore {
        let store = makeStore(limits)
        store.load(now: date(1000))
        return store
    }

    @Test func aCopiedImageIsRecordedOnTopWithItsSize() throws {
        let store = makeStore()
        store.record("some text", now: date(1))
        let clip = try #require(store.record(image: makeCapturedImage(width: 64, height: 48), now: date(2)))

        #expect(store.clips.map(\.kind) == [.image, .text])
        #expect(clip.text.isEmpty)
        #expect(clip.image?.width == 64)
        #expect(clip.image?.height == 48)
        #expect(!store.saveFailed)
    }

    @Test func theImageItselfComesBackFromDisk() throws {
        let store = makeStore()
        let image = makeCapturedImage()
        let clip = try #require(store.record(image: image, now: date(1)))
        #expect(store.imageData(for: clip.id) == image.data)
        #expect(store.imageData(for: UUID()) == nil)
    }

    @Test func imagesSurviveARestartWithTheirThumbnails() throws {
        let store = makeStore()
        let image = makeCapturedImage()
        let clip = try #require(store.record(image: image, now: date(1)))
        store.record("after", now: date(2))

        let later = restarted()
        #expect(later.clips == store.clips)
        #expect(later.clips.last?.image?.thumbnail == image.info.thumbnail)
        #expect(later.imageData(for: clip.id) == image.data)
    }

    @Test func theSameImageCopiedAgainMovesToTheTop() throws {
        let store = makeStore()
        let first = try #require(store.record(image: makeCapturedImage(shade: 10), now: date(1)))
        store.record(image: makeCapturedImage(shade: 200), now: date(2))
        let again = try #require(store.record(image: makeCapturedImage(shade: 10), now: date(3)))

        #expect(again.id == first.id)
        #expect(store.clips.count == 2)
        #expect(store.clips.first?.id == first.id)
        #expect(temp.fileNames().count == 4)
    }

    @Test func puttingAnImageBackMovesItToTheTop() throws {
        let store = makeStore()
        let image = try #require(store.record(image: makeCapturedImage(), now: date(1)))
        store.record("newer", now: date(2))
        store.markUsed(id: image.id, now: date(3))
        #expect(store.clips.map(\.kind) == [.image, .text])
        #expect(restarted().clips.map(\.kind) == [.image, .text])
    }

    @Test func theOldestImagesGoFirstWhenTheImageCountRunsOut() throws {
        let store = makeStore(Limits(maxCount: 100, maxAgeDays: nil, maxImageCount: 2))
        let oldest = try #require(store.record(image: makeCapturedImage(shade: 20), now: date(1)))
        store.record(image: makeCapturedImage(shade: 120), now: date(2))
        store.record(image: makeCapturedImage(shade: 220), now: date(3))

        #expect(store.clips.count == 2)
        #expect(!store.clips.contains { $0.id == oldest.id })
        #expect(store.imageData(for: oldest.id) == nil)
        #expect(temp.fileNames().count == 4)
    }

    @Test func imagesAndTextsAreCountedApart() {
        let store = makeStore(Limits(maxCount: 3, maxAgeDays: nil, maxImageCount: 2))
        for index in 1...5 { store.record("text \(index)", now: date(TimeInterval(index))) }
        for index in 1...4 { store.record(image: makeCapturedImage(shade: index * 20), now: date(TimeInterval(10 + index))) }
        for index in 6...7 { store.record("text \(index)", now: date(TimeInterval(20 + index))) }

        #expect(store.clips.filter { $0.kind == .image }.count == 2)
        #expect(store.clips.filter { $0.kind != .image }.map(\.text) == ["text 7", "text 6", "text 5"])
    }

    @Test func imagesGrowOldLikeEverythingElse() {
        let store = makeStore(Limits(maxCount: 100, maxAgeDays: 7, maxImageCount: 10))
        store.record(image: makeCapturedImage(), now: date(0))
        store.prune(now: date(86_400 * 8))
        #expect(store.clips.isEmpty)
        #expect(temp.fileNames().isEmpty)
    }

    @Test func withTheImageCountAtZeroNoImagesAreRecorded() {
        let store = makeStore(Limits(maxCount: 100, maxAgeDays: nil, maxImageCount: 0))
        #expect(store.record(image: makeCapturedImage(), now: date(1)) == nil)
        #expect(store.clips.isEmpty)
        #expect(temp.fileNames().isEmpty)
    }

    @Test func loweringTheImageCountRemovesImagesAtOnce() {
        let store = makeStore()
        store.record("text stays", now: date(0))
        for index in 1...4 { store.record(image: makeCapturedImage(shade: index * 20), now: date(TimeInterval(index))) }

        store.setLimits(Limits(maxCount: 100, maxAgeDays: nil, maxImageCount: 0), now: date(10))

        #expect(store.clips.map(\.text) == ["text stays"])
        #expect(temp.fileNames().count == 1)
    }

    @Test func deletingAnImageRemovesItFromDisk() throws {
        let store = makeStore()
        let clip = try #require(store.record(image: makeCapturedImage(), now: date(1)))
        try store.delete(id: clip.id)
        #expect(store.clips.isEmpty)
        #expect(temp.fileNames().isEmpty)
    }

    @Test func clearingRemovesImages() throws {
        let store = makeStore()
        store.record(image: makeCapturedImage(), now: date(1))
        store.record("text", now: date(2))
        try store.deleteAll()
        #expect(temp.fileNames().isEmpty)
        #expect(!store.hasAnythingToClear)
    }

    @Test func anImageThatCannotBeWrittenIsNotRecordedAndTheFailureShows() throws {
        let store = makeStore()
        store.record("saved", now: date(1))
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: temp.history.path)

        #expect(store.record(image: makeCapturedImage(), now: date(2)) == nil)
        #expect(store.clips.map(\.text) == ["saved"])
        #expect(store.saveFailed)

        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: temp.history.path)
        #expect(store.record(image: makeCapturedImage(), now: date(3)) != nil)
        #expect(!store.saveFailed)
    }

    @Test func withoutAKeyImagesAreNotRecorded() {
        let store = HistoryStore(files: ClipFiles(directory: temp.history, cipher: nil))
        #expect(store.record(image: makeCapturedImage(), now: date(1)) == nil)
        #expect(store.clips.isEmpty)
    }

    @Test func aTextIsNeverTakenForAnImageWhenCopiedAgain() {
        let store = makeStore()
        store.record(image: makeCapturedImage(), now: date(1))
        store.record("text", now: date(2))
        store.record("text", now: date(3))
        #expect(store.clips.map(\.kind) == [.text, .image])
    }

    @Test func imagesAreShownWithoutAQueryAndHiddenWhileSearching() {
        let store = makeStore()
        store.record(image: makeCapturedImage(), now: date(1))
        store.record("git status", now: date(2))
        let list = HistoryList(store: store)

        #expect(list.results.map(\.kind) == [.text, .image])
        list.query = "git"
        #expect(list.results.map(\.kind) == [.text])
        list.query = "x"
        #expect(list.results.isEmpty)
    }
}

@Suite struct ImageCaptureRuleTests {
    @Test func anImageAloneIsAnImage() {
        #expect(CaptureRule.content(types: ["public.png"], collectsImages: true) == .image)
        #expect(CaptureRule.content(types: ["public.tiff", "com.adobe.pdf"], collectsImages: true) == .image)
        #expect(CaptureRule.content(types: ["public.jpeg"], collectsImages: true) == .image)
        #expect(CaptureRule.content(types: ["public.heic"], collectsImages: true) == .image)
    }

    @Test func textAloneIsText() {
        #expect(CaptureRule.content(types: ["public.utf8-plain-text", "public.html"], collectsImages: true) == .text)
    }

    @Test func textBesideAnImageIsBoth() {
        let types = ["public.tiff", "public.html", "public.utf8-plain-text"]
        #expect(CaptureRule.content(types: types, collectsImages: true) == .textAndImage)
    }

    @Test func formattedTextBesideAnImageIsText() {
        for rich in ["public.rtf", "com.apple.flat-rtfd", "com.apple.rtfd"] {
            let types = ["public.utf8-plain-text", rich, "public.tiff"]
            #expect(CaptureRule.content(types: types, collectsImages: true) == .text)
        }
    }

    @Test func whenImagesAreNotCollectedTheyAreNotSeen() {
        #expect(CaptureRule.content(types: ["public.png"], collectsImages: false) == .nothing)
        #expect(CaptureRule.content(types: ["public.png", "public.utf8-plain-text"], collectsImages: false) == .text)
    }

    @Test func aConfidentialOrUnsupportedImageIsNothing() {
        #expect(CaptureRule.content(types: ["public.png", "org.nspasteboard.ConcealedType"], collectsImages: true) == .nothing)
        #expect(CaptureRule.content(types: ["public.png", "public.file-url"], collectsImages: true) == .nothing)
        #expect(CaptureRule.content(types: ["public.tiff", "com.apple.is-remote-clipboard"], collectsImages: true) == .nothing)
    }

    @Test func otherKindsOfDataAreNothing() {
        #expect(CaptureRule.content(types: [], collectsImages: true) == .nothing)
        #expect(CaptureRule.content(types: ["com.adobe.pdf", "public.rtf"], collectsImages: true) == .nothing)
    }

    @Test func theImageWinsOverALoneAddressOrNoText() {
        #expect(CaptureRule.prefersImage(over: "https://example.com/picture.png"))
        #expect(CaptureRule.prefersImage(over: " https://example.com/article/ \n"))
        #expect(CaptureRule.prefersImage(over: nil))
        #expect(CaptureRule.prefersImage(over: "  \n"))
    }

    @Test func theTextWinsWhenItIsMoreThanAnAddress() {
        #expect(!CaptureRule.prefersImage(over: "Q1\t1200\nQ2\t1350"))
        #expect(!CaptureRule.prefersImage(over: "A heading on a slide"))
        #expect(!CaptureRule.prefersImage(over: "see https://example.com"))
    }
}

@MainActor @Suite struct ImageWatcherTests {
    let temp = TempDirectory()
    let clipboard = FakeClipboard()

    func makeStore(imageCount: Int = 10, megabytes: Int = 10) -> HistoryStore {
        HistoryStore(
            files: temp.files(),
            limits: Limits(maxCount: 100, maxAgeDays: nil, maxImageCount: imageCount, maxImageMegabytes: megabytes))
    }

    func makeWatcher(_ store: HistoryStore) -> ClipboardWatcher {
        let watcher = ClipboardWatcher(source: clipboard, store: store, now: { date(1) })
        watcher.start()
        return watcher
    }

    @Test func aCopiedImageIsRecordedOnce() {
        let store = makeStore()
        let watcher = makeWatcher(store)
        clipboard.copyImage(makeImageData(width: 64, height: 48))
        for _ in 0..<10 { watcher.poll() }

        #expect(store.clips.map(\.kind) == [.image])
        #expect(store.clips.first?.image?.width == 64)
        #expect(clipboard.imageReads == 1)
        #expect(clipboard.reads == 0)
    }

    @Test func aTIFFFromAnotherAppIsRecorded() {
        let store = makeStore()
        let watcher = makeWatcher(store)
        clipboard.copyImage(makeImageData(type: "public.tiff"), type: "public.tiff")
        watcher.poll()
        #expect(store.clips.first?.image?.format == .png)
    }

    @Test func anImageCopiedInABrowserIsKeptAsTheImageNotItsAddress() {
        let store = makeStore()
        let watcher = makeWatcher(store)
        clipboard.copyImage(makeImageData(), text: "https://example.com/picture.png", extraTypes: ["public.html"])
        watcher.poll()
        #expect(store.clips.map(\.kind) == [.image])
    }

    @Test func cellsCopiedInASpreadsheetAreKeptAsTheTextNotThePicture() {
        let store = makeStore()
        let watcher = makeWatcher(store)
        clipboard.copyImage(makeImageData(), type: "public.tiff", text: "Q1\t1200\nQ2\t1350", extraTypes: ["public.rtf"])
        watcher.poll()

        #expect(store.clips.map(\.text) == ["Q1\t1200\nQ2\t1350"])
        #expect(clipboard.imageReads == 0)
    }

    @Test func aLoneAddressCopiedFromASpreadsheetCellIsKeptAsTheAddress() {
        let store = makeStore()
        let watcher = makeWatcher(store)
        clipboard.copyImage(
            makeImageData(), type: "public.tiff", text: "https://example.com/report", extraTypes: ["public.rtf"])
        watcher.poll()

        #expect(store.clips.map(\.kind) == [.link])
        #expect(clipboard.imageReads == 0)
    }

    @Test func aPictureOfTheSelectionWithoutFormattingStillLosesToOrdinaryText() {
        let store = makeStore()
        let watcher = makeWatcher(store)
        clipboard.copyImage(makeImageData(), type: "public.tiff", text: "A heading on a slide")
        watcher.poll()

        #expect(store.clips.map(\.text) == ["A heading on a slide"])
        #expect(clipboard.imageReads == 0)
    }

    @Test func anImageTooLargeToKeepIsLeftOut() {
        let store = makeStore(megabytes: 2)
        let watcher = makeWatcher(store)
        // Noise does not compress, so this stays above two megabytes as a PNG.
        clipboard.copyImage(makeNoiseImageData(side: 1100))
        watcher.poll()
        #expect(store.clips.isEmpty)
        #expect(temp.fileNames().isEmpty)
    }

    @Test func whenTheImageIsTooLargeItsAddressIsKeptInstead() {
        let store = makeStore(megabytes: 2)
        let watcher = makeWatcher(store)
        clipboard.copyImage(makeNoiseImageData(side: 1100), text: "https://example.com/huge.png")
        watcher.poll()
        #expect(store.clips.map(\.text) == ["https://example.com/huge.png"])
        #expect(store.clips.map(\.kind) == [.link])
    }

    @Test func withImagesTurnedOffAnImageIsNeverRead() {
        let store = makeStore(imageCount: 0)
        let watcher = makeWatcher(store)
        clipboard.copyImage(makeImageData())
        watcher.poll()
        clipboard.copyImage(makeImageData(), text: "https://example.com/picture.png")
        watcher.poll()

        #expect(clipboard.imageReads == 0)
        #expect(store.clips.map(\.kind) == [.link])
    }

    @Test func aConfidentialImageIsNeverRead() {
        let store = makeStore()
        let watcher = makeWatcher(store)
        clipboard.copyImage(makeImageData(), extraTypes: ["org.nspasteboard.ConcealedType"])
        watcher.poll()
        #expect(store.clips.isEmpty)
        #expect(clipboard.imageReads == 0)
    }

    @Test func noImageIsReadWhilePaused() {
        let store = makeStore()
        let watcher = makeWatcher(store)
        watcher.isPaused = true
        clipboard.copyImage(makeImageData())
        watcher.poll()
        watcher.isPaused = false
        watcher.poll()
        #expect(store.clips.isEmpty)
        #expect(clipboard.imageReads == 0)
    }

    @Test func anImageThatIsReplacedWhileItIsReadIsNotRecorded() {
        let store = makeStore()
        let watcher = makeWatcher(store)
        clipboard.copyImage(makeImageData())
        clipboard.onRead = { [clipboard] in
            clipboard.onRead = nil
            clipboard.copy("hunter2", extraTypes: ["org.nspasteboard.ConcealedType"])
        }
        watcher.poll()
        watcher.poll()
        #expect(store.clips.isEmpty)
    }

    @Test func dataThatIsNotAnImageIsLeftOut() {
        let store = makeStore()
        let watcher = makeWatcher(store)
        clipboard.copyImage(Data("not really an image".utf8))
        watcher.poll()
        #expect(store.clips.isEmpty)
    }

    @Test func textAndImagesMixInTheHistoryNewestFirst() {
        let store = makeStore()
        let watcher = makeWatcher(store)
        clipboard.copy("first text")
        watcher.poll()
        clipboard.copyImage(makeImageData())
        watcher.poll()
        clipboard.copy("https://example.com")
        watcher.poll()
        #expect(store.clips.map(\.kind) == [.link, .image, .text])
    }
}
