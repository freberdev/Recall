import Foundation

/// How much history is kept.
public struct Limits: Equatable, Sendable {
    /// The largest number of texts and links. The least recently used go first.
    public var maxCount: Int
    /// Clips unused for more than this many days are removed. Nil keeps them until the count runs out.
    public var maxAgeDays: Int?
    /// The largest number of images, counted apart from texts and links. Zero collects no images.
    public var maxImageCount: Int
    /// Images that would take more room than this on disk are not collected.
    public var maxImageMegabytes: Int

    public init(maxCount: Int, maxAgeDays: Int?, maxImageCount: Int = 10, maxImageMegabytes: Int = 10) {
        self.maxCount = maxCount
        self.maxAgeDays = maxAgeDays
        self.maxImageCount = maxImageCount
        self.maxImageMegabytes = maxImageMegabytes
    }

    public static let `default` = Limits(maxCount: 500, maxAgeDays: 30, maxImageCount: 10, maxImageMegabytes: 10)

    /// The choices offered in settings.
    public static let countChoices = [100, 250, 500, 1000]
    public static let ageChoices: [Int?] = [1, 7, 30, 90, nil]
    public static let imageCountChoices = [0, 5, 10, 25, 50, 100]
    public static let imageMegabyteChoices = [2, 5, 10, 20, 50]

    var maxAge: TimeInterval? {
        maxAgeDays.map { TimeInterval($0) * 86_400 }
    }

    public var collectsImages: Bool { maxImageCount > 0 }

    public var maxImageBytes: Int { maxImageMegabytes * 1_000_000 }
}
