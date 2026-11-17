import Foundation

/// How much history is kept.
public struct Limits: Equatable, Sendable {
    /// The largest number of clips. The least recently used go first.
    public var maxCount: Int
    /// Clips unused for more than this many days are removed. Nil keeps them until the count runs out.
    public var maxAgeDays: Int?

    public init(maxCount: Int, maxAgeDays: Int?) {
        self.maxCount = maxCount
        self.maxAgeDays = maxAgeDays
    }

    public static let `default` = Limits(maxCount: 500, maxAgeDays: 30)

    /// The choices offered in settings.
    public static let countChoices = [100, 250, 500, 1000]
    public static let ageChoices: [Int?] = [1, 7, 30, 90, nil]

    var maxAge: TimeInterval? {
        maxAgeDays.map { TimeInterval($0) * 86_400 }
    }
}
