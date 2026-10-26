import Foundation

enum PlainLogImport {
    struct Entry: Equatable {
        var date: String
        var description: String
    }

    enum TextError: LocalizedError, Equatable {
        case empty
        case badLine(Int)

        var errorDescription: String? {
            switch self {
            case .empty:
                return "文件里没有事项。"
            case .badLine(let line):
                return "第 \(line) 行不符合格式。日期单独一行，事项缩进写在日期下面。"
            }
        }
    }

    static func parse(_ text: String) -> Result<[Entry], TextError> {
        let normalized = text.replacingOccurrences(of: "\u{feff}", with: "")
        let lines = normalized.components(separatedBy: .newlines)
        var currentDate: String?
        var entries: [Entry] = []
        for (index, raw) in lines.enumerated() {
            if raw.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            let line = index + 1
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if raw.first?.isWhitespace == true {
                guard let date = currentDate else { return .failure(.badLine(line)) }
                entries.append(Entry(date: date, description: trimmed))
                continue
            }
            guard isDay(trimmed) else { return .failure(.badLine(line)) }
            currentDate = trimmed
        }
        guard entries.isEmpty == false else { return .failure(.empty) }
        return .success(entries)
    }

    /// Same day and the same description count as the same item. Later copies are left out.
    static func skippingExisting(_ entries: [Entry], existing: [Entry]) -> (added: [Entry], skipped: Int) {
        var seen = Set(existing.map(identity))
        var added: [Entry] = []
        var skipped = 0
        for entry in entries {
            let key = identity(entry)
            if seen.contains(key) {
                skipped += 1
            } else {
                seen.insert(key)
                added.append(entry)
            }
        }
        return (added, skipped)
    }

    private static func identity(_ entry: Entry) -> String {
        entry.date + "\n" + entry.description.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isDay(_ text: String) -> Bool {
        let parts = text.split(separator: "-")
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let components = DateComponents(year: year, month: month, day: day)
        guard let date = calendar.date(from: components) else { return false }
        let back = calendar.dateComponents([.year, .month, .day], from: date)
        return back.year == year && back.month == month && back.day == day
    }
}
