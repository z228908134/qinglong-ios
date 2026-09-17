//
//  QLFormat.swift
//  时间 / 体积格式化，以及日志文本清理
//

import Foundation

enum QLFormat {

    // MARK: 时间

    /// 青龙的时间戳字段（last_execution_time 等）单位是**毫秒**
    static func date(fromMillis value: Double?) -> Date? {
        guard let value, value > 0 else { return nil }
        return Date(timeIntervalSince1970: value / 1000)
    }

    static func absolute(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    static func short(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: date)
    }

    /// “刚刚 / 12 分钟前 / 3 小时前 / 2 天前”
    static func relative(millis value: Double?) -> String {
        guard let date = date(fromMillis: value) else { return "从未运行" }
        let seconds = Date().timeIntervalSince(date)
        if seconds < 0 { return absolute(date) }
        if seconds < 60 { return "刚刚" }
        if seconds < 3600 { return "\(Int(seconds / 60)) 分钟前" }
        if seconds < 86400 { return "\(Int(seconds / 3600)) 小时前" }
        if seconds < 86400 * 30 { return "\(Int(seconds / 86400)) 天前" }
        return absolute(date)
    }

    /// “5 分钟后 / 3 小时后 / 2 天后”
    static func countdown(to date: Date) -> String {
        let seconds = date.timeIntervalSinceNow
        if seconds < 0 { return "已过期" }
        if seconds < 60 { return "不到 1 分钟后" }
        if seconds < 3600 { return "\(Int(seconds / 60)) 分钟后" }
        if seconds < 86400 { return "\(Int(seconds / 3600)) 小时后" }
        return "\(Int(seconds / 86400)) 天后"
    }

    static func isoDate(_ text: String?) -> Date? {
        guard let text, !text.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }

    // MARK: 体积

    static func byteSize(_ value: Double?) -> String? {
        guard let value, value >= 0 else { return nil }
        let units = ["B", "KB", "MB", "GB"]
        var size = value
        var index = 0
        while size >= 1024 && index < units.count - 1 {
            size /= 1024
            index += 1
        }
        return index == 0
            ? "\(Int(size)) \(units[index])"
            : String(format: "%.1f %@", size, units[index])
    }
}

// MARK: - 日志文本处理

extension String {

    /// 去掉终端颜色控制符（青龙的日志文件里带 ANSI 转义序列）
    var strippingANSI: String {
        var text = self
        // CSI 序列：ESC [ ... 字母
        text = text.replacingOccurrences(
            of: "\u{001B}\\[[0-9;?]*[ -/]*[@-~]",
            with: "",
            options: .regularExpression
        )
        // OSC 序列：ESC ] ... BEL / ESC \
        text = text.replacingOccurrences(
            of: "\u{001B}\\][^\u{0007}\u{001B}]*(\u{0007}|\u{001B}\\\\)",
            with: "",
            options: .regularExpression
        )
        // 单独出现的 ESC
        text = text.replacingOccurrences(of: "\u{001B}", with: "")
        return text
    }

    /// 日志太长时只保留尾部，避免手机内存和渲染压力
    func tailLines(_ limit: Int) -> (text: String, truncated: Bool) {
        let lines = split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > limit else { return (self, false) }
        let kept = lines.suffix(limit).joined(separator: "\n")
        return ("……（已省略前 \(lines.count - limit) 行）\n" + kept, true)
    }
}
