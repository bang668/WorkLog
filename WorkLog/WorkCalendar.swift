import Foundation

enum WorkCalendar {
    static let weekdaySymbols = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]

    static func gregorian(timeZone: TimeZone = .current) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "zh_CN")
        calendar.timeZone = timeZone
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    static func dayKey(_ date: Date, calendar: Calendar = gregorian()) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func monthKey(fromDay key: String) -> String {
        String(key.prefix(7))
    }

    static func monthKey(_ date: Date, calendar: Calendar = gregorian()) -> String {
        monthKey(fromDay: dayKey(date, calendar: calendar))
    }

    static func date(fromDay key: String, calendar: Calendar = gregorian()) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        return calendar.date(from: components)
    }

    static func addingDays(_ days: Int, to key: String, calendar: Calendar = gregorian()) -> String? {
        guard let date = date(fromDay: key, calendar: calendar),
              let next = calendar.date(byAdding: .day, value: days, to: date) else { return nil }
        return dayKey(next, calendar: calendar)
    }

    static func isoWeekday(of key: String, calendar: Calendar = gregorian()) -> Int? {
        guard let date = date(fromDay: key, calendar: calendar) else { return nil }
        let weekday = calendar.component(.weekday, from: date)
        return weekday == 1 ? 7 : weekday - 1
    }

    static func weekdayIndexMondayFirst(of key: String, calendar: Calendar = gregorian()) -> Int? {
        guard let iso = isoWeekday(of: key, calendar: calendar) else { return nil }
        return iso - 1
    }

    static func weekdayName(of key: String, calendar: Calendar = gregorian()) -> String {
        guard let index = weekdayIndexMondayFirst(of: key, calendar: calendar) else { return "" }
        return weekdaySymbols[index]
    }

    static func startOfWeek(containing key: String, calendar: Calendar = gregorian()) -> String? {
        guard let iso = isoWeekday(of: key, calendar: calendar) else { return nil }
        return addingDays(1 - iso, to: key, calendar: calendar)
    }

    static func weekDays(containing key: String, calendar: Calendar = gregorian()) -> [String] {
        guard let start = startOfWeek(containing: key, calendar: calendar) else { return [] }
        return (0..<7).compactMap { addingDays($0, to: start, calendar: calendar) }
    }

    static func isoWeek(of key: String, calendar: Calendar = gregorian()) -> Int? {
        guard let thursday = thursday(of: key, calendar: calendar) else { return nil }
        let year = calendar.component(.year, from: thursday)
        guard let weekOneThursday = thursdayOfISOWeekOne(year: year, calendar: calendar) else { return nil }
        let days = calendar.dateComponents([.day], from: weekOneThursday, to: thursday).day ?? 0
        return days / 7 + 1
    }

    static func isoWeekYear(of key: String, calendar: Calendar = gregorian()) -> Int? {
        guard let thursday = thursday(of: key, calendar: calendar) else { return nil }
        return calendar.component(.year, from: thursday)
    }

    static func mondayOfISOWeek(_ week: Int, year: Int, calendar: Calendar = gregorian()) -> String? {
        guard (1...53).contains(week),
              let weekOneThursday = thursdayOfISOWeekOne(year: year, calendar: calendar),
              let thursday = calendar.date(byAdding: .day, value: (week - 1) * 7, to: weekOneThursday) else { return nil }
        let thursdayKey = dayKey(thursday, calendar: calendar)
        return addingDays(-3, to: thursdayKey, calendar: calendar)
    }

    static func monthDayHyphen(_ key: String) -> String {
        String(key.dropFirst(5))
    }

    static func chineseMonthDay(_ key: String) -> String {
        let parts = key.split(separator: "-")
        guard parts.count == 3, let month = Int(parts[1]), let day = Int(parts[2]) else { return key }
        return String(format: "%02d月%02d日", month, day)
    }

    static func chineseYearMonthDay(_ key: String) -> String {
        let parts = key.split(separator: "-")
        guard parts.count == 3, let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else { return key }
        return String(format: "%d年%02d月%02d日", year, month, day)
    }

    static func chineseYearMonth(_ month: String) -> String {
        let parts = month.split(separator: "-")
        guard parts.count == 2, let year = Int(parts[0]), let value = Int(parts[1]) else { return month }
        return String(format: "%d年%02d月", year, value)
    }

    static func weekRangeLabel(days: [String]) -> String {
        guard let start = days.first, let end = days.last else { return "" }
        let startYear = start.prefix(4)
        let endYear = end.prefix(4)
        if startYear == endYear {
            return "\(startYear)年\(chineseMonthDay(start)) – \(chineseMonthDay(end))"
        }
        return "\(startYear)年\(chineseMonthDay(start)) – \(endYear)年\(chineseMonthDay(end))"
    }

    static func weeks(inMonth month: String, calendar: Calendar = gregorian()) -> [[String]] {
        let parts = month.split(separator: "-")
        guard parts.count == 2, let year = Int(parts[0]), let mon = Int(parts[1]) else { return [] }
        var components = DateComponents()
        components.year = year
        components.month = mon
        components.day = 1
        guard let first = calendar.date(from: components),
              let dayRange = calendar.range(of: .day, in: .month, for: first) else { return [] }
        let firstKey = dayKey(first, calendar: calendar)
        guard let gridStart = startOfWeek(containing: firstKey, calendar: calendar) else { return [] }
        components.day = dayRange.count
        guard let lastDate = calendar.date(from: components) else { return [] }
        let lastKey = dayKey(lastDate, calendar: calendar)
        var weeks: [[String]] = []
        var cursor = gridStart
        while true {
            let week = (0..<7).compactMap { addingDays($0, to: cursor, calendar: calendar) }
            guard week.count == 7 else { break }
            weeks.append(week)
            if week.contains(lastKey) || weeks.count == 6 { break }
            guard let next = addingDays(7, to: cursor, calendar: calendar) else { break }
            cursor = next
        }
        return weeks
    }

    static func months(from start: String, through end: String) -> [String] {
        guard start <= end else { return [] }
        var result: [String] = []
        var cursor = start
        while cursor <= end && result.count < 240 {
            result.append(cursor)
            guard let next = shiftingMonth(cursor, by: 1) else { break }
            cursor = next
        }
        return result
    }

    static func shiftingMonth(_ month: String, by delta: Int) -> String? {
        let parts = month.split(separator: "-")
        guard parts.count == 2, let year = Int(parts[0]), let mon = Int(parts[1]) else { return nil }
        let index = year * 12 + (mon - 1) + delta
        let nextYear = index / 12
        let nextMonth = index % 12 + 1
        guard nextMonth > 0 else { return nil }
        return String(format: "%04d-%02d", nextYear, nextMonth)
    }

    static func shiftingDay(_ key: String, by days: Int, calendar: Calendar = gregorian()) -> String? {
        addingDays(days, to: key, calendar: calendar)
    }

    static func dayClamped(in month: String, day: Int, calendar: Calendar = gregorian()) -> String {
        let parts = month.split(separator: "-")
        guard parts.count == 2, let year = Int(parts[0]), let mon = Int(parts[1]) else { return month + "-01" }
        var components = DateComponents()
        components.year = year
        components.month = mon
        components.day = 1
        let length = calendar.date(from: components).flatMap { calendar.range(of: .day, in: .month, for: $0)?.count } ?? 28
        return String(format: "%04d-%02d-%02d", year, mon, min(max(day, 1), length))
    }

    private static func thursday(of key: String, calendar: Calendar) -> Date? {
        guard let iso = isoWeekday(of: key, calendar: calendar),
              let thursdayKey = addingDays(4 - iso, to: key, calendar: calendar) else { return nil }
        return date(fromDay: thursdayKey, calendar: calendar)
    }

    private static func thursdayOfISOWeekOne(year: Int, calendar: Calendar) -> Date? {
        var components = DateComponents()
        components.year = year
        components.month = 1
        components.day = 4
        guard let januaryFourth = calendar.date(from: components) else { return nil }
        let key = dayKey(januaryFourth, calendar: calendar)
        guard let iso = isoWeekday(of: key, calendar: calendar) else { return nil }
        return calendar.date(byAdding: .day, value: 4 - iso, to: januaryFourth)
    }
}

enum MonthTree {
    static func visibleMonths(startMonth: String, todayMonth: String, monthsWithItems: [String]) -> [String] {
        let span = startMonth <= todayMonth
            ? WorkCalendar.months(from: startMonth, through: todayMonth)
            : [startMonth]
        let spanEnd = span.last ?? startMonth
        let outside = monthsWithItems.filter { $0 < startMonth || $0 > spanEnd }
        return Array(Set(span + outside)).sorted()
    }

    static func nearestMonth(in months: [String], to todayMonth: String) -> String? {
        months.min { abs(order($0) - order(todayMonth)) < abs(order($1) - order(todayMonth)) }
    }

    private static func order(_ month: String) -> Int {
        let parts = month.split(separator: "-")
        guard parts.count == 2, let year = Int(parts[0]), let monthValue = Int(parts[1]) else { return 0 }
        return year * 12 + monthValue
    }
}

enum ColumnLayout {
    static func weekIsSlim(index: Int, itemCount: Int) -> Bool {
        index >= 5 && itemCount == 0
    }

    static func monthSlimColumns(weeks: [[String]], viewMonth: String, itemsOn: (String) -> Int) -> (saturday: Bool, sunday: Bool) {
        func empty(_ index: Int) -> Bool {
            !weeks.contains { week in
                guard week.count > index else { return false }
                return WorkCalendar.monthKey(fromDay: week[index]) == viewMonth && itemsOn(week[index]) > 0
            }
        }
        return (empty(5), empty(6))
    }
}
