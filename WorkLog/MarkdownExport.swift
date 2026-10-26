import Foundation

enum ExportScope: Equatable {
    case custom(start: String, end: String)
    case month(String)
    case quarter(year: Int, quarter: Int)

    var title: String {
        switch normalized {
        case .custom(let start, let end):
            return "\(start) – \(end)"
        case .month(let month):
            return month
        case .quarter(let year, let quarter):
            return "\(year)-Q\(quarter)"
        }
    }

    var months: [String] {
        switch normalized {
        case .custom(let start, let end):
            return WorkCalendar.months(from: WorkCalendar.monthKey(fromDay: start), through: WorkCalendar.monthKey(fromDay: end))
        case .month(let month):
            return [month]
        case .quarter(let year, let quarter):
            let first = (quarter - 1) * 3 + 1
            return (0..<3).map { String(format: "%04d-%02d", year, first + $0) }
        }
    }

    func contains(_ day: String) -> Bool {
        switch normalized {
        case .custom(let start, let end):
            return day >= start && day <= end
        case .month(let month):
            return WorkCalendar.monthKey(fromDay: day) == month
        case .quarter(let year, let quarter):
            let parts = day.split(separator: "-")
            guard parts.count == 3, let itemYear = Int(parts[0]), let month = Int(parts[1]) else { return false }
            let itemQuarter = (month - 1) / 3 + 1
            return itemYear == year && itemQuarter == quarter
        }
    }

    private var normalized: ExportScope {
        if case .custom(let start, let end) = self, start > end {
            return .custom(start: end, end: start)
        }
        return self
    }
}

enum MarkdownExport {
    static func document(scope: ExportScope, items: [WorkItem], types: [WorkType]) -> String? {
        let days = Array(Set(items.map(\.date).filter(scope.contains))).sorted()
        guard !days.isEmpty else { return nil }
        var lines = ["# \(scope.title)", ""]
        for day in days {
            lines.append("## \(day) \(WorkCalendar.weekdayName(of: day))")
            lines.append("")
            let dayItems = items.filter { $0.date == day }.sorted { $0.order < $1.order }
            for item in dayItems {
                lines.append(contentsOf: fields(day: day, item: item, types: types))
                lines.append("")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func fields(day: String, item: WorkItem, types: [WorkType]) -> [String] {
        let rows = [
            ("日期", day),
            ("一级类型", TypeNames.parentName(typeID: item.typeId, types: types)),
            ("二级类型", TypeNames.childName(typeID: item.typeId, subTypeID: item.subTypeId, types: types)),
            ("事项描述", item.description),
            ("备注", item.note)
        ]
        return rows.enumerated().map { index, row in
            labeled(row.0, row.1, first: index == 0, escape: index != 0)
        }
    }

    private static func labeled(_ name: String, _ value: String, first: Bool, escape: Bool) -> String {
        let head = first ? "- " : "  "
        let text = escape ? escapeField(value) : value
        return "\(head)\(name)：\(text)"
    }

    /// One field stays on one line. `\` is the escape character: a real line break is `\n`,
    /// a backslash already in the text is `\\`, so a written `\n` stays `\\n`.
    private static func escapeField(_ value: String) -> String {
        var result = ""
        var index = value.startIndex
        while index < value.endIndex {
            let character = value[index]
            if character == "\r" {
                result.append("\\n")
                let next = value.index(after: index)
                if next < value.endIndex, value[next] == "\n" {
                    index = next
                }
            } else if character == "\n" {
                result.append("\\n")
            } else if "\\*_`[]()<>|~#!+-".contains(character) {
                result.append("\\")
                result.append(character)
            } else {
                result.append(character)
            }
            index = value.index(after: index)
        }
        return result
    }
}
