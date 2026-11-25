import Foundation

public struct SessionRecord: Codable, Equatable {
    public var start: Date
    public var maxMinutes: Double
    public var minMinutes: Double
    public var steepness: Double
    public var plannedSeconds: TimeInterval
    public var workedSeconds: TimeInterval
    public var endedBy: String
    public var focusRating: Int?
    public var breakSeconds: TimeInterval
    public var negotiated: Bool

    public init(
        start: Date,
        maxMinutes: Double,
        minMinutes: Double,
        steepness: Double,
        plannedSeconds: TimeInterval,
        workedSeconds: TimeInterval,
        endedBy: String,
        focusRating: Int?,
        breakSeconds: TimeInterval,
        negotiated: Bool
    ) {
        self.start = start
        self.maxMinutes = maxMinutes
        self.minMinutes = minMinutes
        self.steepness = steepness
        self.plannedSeconds = plannedSeconds
        self.workedSeconds = workedSeconds
        self.endedBy = endedBy
        self.focusRating = focusRating
        self.breakSeconds = breakSeconds
        self.negotiated = negotiated
    }
}

public final class SessionLog {
    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func defaultURL() -> URL {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/UncertainPomodoro", isDirectory: true)
        // This API is nonthrowing; append reports any directory creation failure.
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("sessions.jsonl")
    }

    public func append(_ record: SessionRecord) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var data = try encoder.encode(record)
        data.append(0x0A)

        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            try data.write(to: fileURL)
            return
        }
        let handle = try FileHandle(forWritingTo: fileURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    public func readAll() throws -> [SessionRecord] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return data.split(separator: 0x0A).compactMap {
            try? decoder.decode(SessionRecord.self, from: Data($0))
        }
    }
}
