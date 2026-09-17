//
//  CronSchedule.swift
//  轻量 cron 解析器：只做一件事 —— 估算「下次执行时间」。
//  支持标准 5 段表达式、6 段（带秒，按分钟粒度估算）、以及 @daily 这类宏。
//

import Foundation

struct CronSchedule {

    private let minutes: Set<Int>
    private let hours: Set<Int>
    private let daysOfMonth: Set<Int>
    private let months: Set<Int>
    private let daysOfWeek: Set<Int>
    private let dayOfMonthRestricted: Bool
    private let dayOfWeekRestricted: Bool

    private static let monthNames: [String: Int] = [
        "jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
        "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12,
    ]

    private static let weekNames: [String: Int] = [
        "sun": 0, "mon": 1, "tue": 2, "wed": 3, "thu": 4, "fri": 5, "sat": 6,
    ]

    // MARK: 解析

    init?(_ expression: String) {
        var text = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        // 宏先展开成标准表达式，再统一解析
        if text.hasPrefix("@") {
            guard let expanded = CronSchedule.expandMacro(text) else { return nil }
            text = expanded
        }

        var fields = text.split(separator: " ").map(String.init).filter { !$0.isEmpty }
        // 6 段表达式带秒字段，这里忽略秒，做分钟级估算
        if fields.count == 6 { fields.removeFirst() }
        guard fields.count == 5 else { return nil }

        guard let minuteField = CronSchedule.parseField(fields[0], range: 0...59),
              let hourField = CronSchedule.parseField(fields[1], range: 0...23),
              let dayField = CronSchedule.parseField(fields[2], range: 1...31),
              let monthField = CronSchedule.parseField(fields[3], range: 1...12, names: monthNames),
              let weekField = CronSchedule.parseField(fields[4], range: 0...6, names: weekNames)
        else { return nil }

        minutes = minuteField.values
        hours = hourField.values
        daysOfMonth = dayField.values
        months = monthField.values
        daysOfWeek = Set(weekField.values.map { $0 % 7 })
        dayOfMonthRestricted = dayField.restricted
        dayOfWeekRestricted = weekField.restricted
    }

    private static func expandMacro(_ text: String) -> String? {
        let lower = text.lowercased()
        if lower.hasPrefix("@every") { return nil }          // 间隔型表达式不做估算
        switch lower {
        case "@yearly", "@annually": return "0 0 1 1 *"
        case "@monthly": return "0 0 1 * *"
        case "@weekly": return "0 0 * * 0"
        case "@daily", "@midnight": return "0 0 * * *"
        case "@hourly": return "0 * * * *"
        default: return nil                                   // @once / @boot / @reboot
        }
    }

    private static func parseField(_ raw: String,
                                   range: ClosedRange<Int>,
                                   names: [String: Int] = [:]) -> (values: Set<Int>, restricted: Bool)? {
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        if text == "*" || text == "?" { return (Set(range), false) }

        var result = Set<Int>()
        for part in text.split(separator: ",") {
            let piece = String(part)
            var step = 1
            var body = piece

            if let slash = piece.firstIndex(of: "/") {
                body = String(piece[piece.startIndex..<slash])
                guard let parsed = Int(piece[piece.index(after: slash)...]), parsed > 0 else { return nil }
                step = parsed
            }

            let lower: Int
            let upper: Int
            if body == "*" || body == "?" || body.isEmpty {
                lower = range.lowerBound
                upper = range.upperBound
            } else if let dash = body.firstIndex(of: "-") {
                guard let low = value(String(body[body.startIndex..<dash]), names: names),
                      let high = value(String(body[body.index(after: dash)...]), names: names)
                else { return nil }
                lower = low
                upper = high
            } else {
                guard let single = value(body, names: names) else { return nil }
                lower = single
                upper = step > 1 ? range.upperBound : single
            }

            guard lower <= upper else { return nil }
            var cursor = lower
            while cursor <= upper {
                if range.contains(cursor) { result.insert(cursor) }
                cursor += step
            }
        }

        guard !result.isEmpty else { return nil }
        return (result, true)
    }

    private static func value(_ text: String, names: [String: Int]) -> Int? {
        if let number = Int(text) { return number }
        return names[text.lowercased()]
    }

    // MARK: 下次执行时间

    func nextFireDate(after date: Date = Date(), calendar: Calendar = .current) -> Date? {
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        components.second = 0
        guard var cursor = calendar.date(from: components) else { return nil }
        cursor = calendar.date(byAdding: .minute, value: 1, to: cursor) ?? cursor

        let startOfDay = calendar.startOfDay(for: cursor)
        let sortedHours = hours.sorted()
        let sortedMinutes = minutes.sorted()

        for dayOffset in 0..<400 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: startOfDay) else { return nil }
            let dayParts = calendar.dateComponents([.month, .day, .weekday], from: day)
            guard let month = dayParts.month,
                  let dayOfMonth = dayParts.day,
                  let weekday = dayParts.weekday
            else { continue }

            guard months.contains(month) else { continue }

            // Calendar 的 weekday：1 = 周日 … 7 = 周六
            let weekIndex = (weekday - 1) % 7
            let dayMatches: Bool
            if dayOfMonthRestricted && dayOfWeekRestricted {
                dayMatches = daysOfMonth.contains(dayOfMonth) || daysOfWeek.contains(weekIndex)
            } else if dayOfMonthRestricted {
                dayMatches = daysOfMonth.contains(dayOfMonth)
            } else if dayOfWeekRestricted {
                dayMatches = daysOfWeek.contains(weekIndex)
            } else {
                dayMatches = true
            }
            guard dayMatches else { continue }

            for hour in sortedHours {
                for minute in sortedMinutes {
                    guard let candidate = calendar.date(bySettingHour: hour,
                                                        minute: minute,
                                                        second: 0,
                                                        of: day)
                    else { continue }
                    if candidate >= cursor { return candidate }
                }
            }
        }
        return nil
    }

    /// 给 UI 用：直接返回一句人话
    static func nextRunDescription(for expression: String?) -> String? {
        guard let expression, !expression.isEmpty else { return nil }
        guard let schedule = CronSchedule(expression) else { return nil }
        guard let next = schedule.nextFireDate() else { return nil }
        return "\(QLFormat.absolute(next))（\(QLFormat.countdown(to: next))）"
    }
}
