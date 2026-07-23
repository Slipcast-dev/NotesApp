import Foundation

enum DatabaseDateCoding {
    private static let sqliteFormatters: [DateFormatter] = {
        [
            "yyyy-MM-dd HH:mm:ss.SSSSSSS",
            "yyyy-MM-dd HH:mm:ss.SSSSSS",
            "yyyy-MM-dd HH:mm:ss.SSS",
            "yyyy-MM-dd HH:mm:ss"
        ].map { format in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = .current
            formatter.dateFormat = format
            return formatter
        }
    }()

    private static let writer: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSSS"
        return formatter
    }()

    static func string(from date: Date) -> String {
        writer.string(from: date)
    }

    static func date(from value: String) -> Date {
        for formatter in sqliteFormatters {
            if let date = formatter.date(from: value) {
                return date
            }
        }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: value) {
            return date
        }

        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: value) ?? Date(timeIntervalSince1970: 0)
    }
}
