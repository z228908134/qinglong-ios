import Foundation

/// 一个宽松的 JSON 值容器。
///
/// 青龙面板不同版本之间，同名字段的类型可能不一致（例如 `labels` 有时是数组、
/// 有时是被 JSON 序列化过的字符串；`status` 有时是数字、有时是字符串）。
/// 对于结构不确定的响应（日志目录树、系统信息等）用这个类型兜底，
/// 可以避免因为一个字段解析失败导致整页空白。
enum JSONValue: Codable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
            return
        }
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
            return
        }
        if let value = try? container.decode(Double.self) {
            self = .number(value)
            return
        }
        if let value = try? container.decode(String.self) {
            self = .string(value)
            return
        }
        if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
            return
        }
        if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
            return
        }
        self = .null
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

extension JSONValue {
    var stringValue: String? {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            if value == value.rounded() && abs(value) < 1e15 {
                return String(Int(value))
            }
            return String(value)
        case .bool(let value):
            return value ? "true" : "false"
        case .null:
            return nil
        case .array, .object:
            return nil
        }
    }

    var displayText: String {
        switch self {
        case .string(let value): return value
        case .number(let value):
            if value == value.rounded() && abs(value) < 1e15 {
                return String(Int(value))
            }
            return String(value)
        case .bool(let value): return value ? "true" : "false"
        case .null: return "-"
        case .array, .object:
            if let data = try? JSONEncoder().encode(self),
               let text = String(data: data, encoding: .utf8) {
                return text
            }
            return "-"
        }
    }

    var intValue: Int? {
        switch self {
        case .number(let value): return Int(value)
        case .string(let value): return Int(value)
        case .bool(let value): return value ? 1 : 0
        default: return nil
        }
    }

    var doubleValue: Double? {
        switch self {
        case .number(let value): return value
        case .string(let value): return Double(value)
        default: return nil
        }
    }

    var boolValue: Bool? {
        switch self {
        case .bool(let value): return value
        case .number(let value): return value != 0
        case .string(let value):
            let lower = value.lowercased()
            if ["true", "1", "yes"].contains(lower) { return true }
            if ["false", "0", "no", ""].contains(lower) { return false }
            return nil
        default: return nil
        }
    }

    var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    /// 按路径逐层取值，例如 value(at: ["data", "token"])。
    func value(at path: [String]) -> JSONValue? {
        var current: JSONValue? = self
        for key in path {
            guard let node = current else { return nil }
            if let index = Int(key), let list = node.arrayValue {
                current = (index >= 0 && index < list.count) ? list[index] : nil
            } else {
                current = node.objectValue?[key]
            }
        }
        return current
    }
}

/// 解析时对类型不敏感的工具方法。
/// 面板各接口的字段类型在不同版本间并不完全统一，用这些方法取值可以避免整条解析失败。
extension KeyedDecodingContainer {
    func flexInt(_ key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return Int(value) }
        if let value = try? decodeIfPresent(Bool.self, forKey: key) { return value ? 1 : 0 }
        if let value = try? decodeIfPresent(String.self, forKey: key) { return Int(value) }
        return nil
    }

    func flexDouble(_ key: Key) -> Double? {
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return Double(value) }
        if let value = try? decodeIfPresent(String.self, forKey: key) { return Double(value) }
        return nil
    }

    func flexString(_ key: Key) -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return String(value) }
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return String(value) }
        if let value = try? decodeIfPresent(Bool.self, forKey: key) { return value ? "true" : "false" }
        return nil
    }

    func flexBool(_ key: Key) -> Bool? {
        if let value = try? decodeIfPresent(Bool.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value != 0 }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            let lower = value.lowercased()
            if ["true", "1", "yes"].contains(lower) { return true }
            if ["false", "0", "no", ""].contains(lower) { return false }
        }
        return nil
    }

    /// `labels` 在部分版本会以 JSON 字符串形式返回，这里同时兼容两种形态。
    func flexStringArray(_ key: Key) -> [String]? {
        if let value = try? decodeIfPresent([String].self, forKey: key) { return value }
        if let value = try? decodeIfPresent([Int].self, forKey: key) { return value.map(String.init) }
        if let text = try? decodeIfPresent(String.self, forKey: key) {
            guard let data = text.data(using: .utf8),
                  let list = try? JSONDecoder().decode([JSONValue].self, from: data) else {
                return text.isEmpty ? [] : [text]
            }
            return list.compactMap { $0.stringValue }
        }
        return nil
    }

    /// 使用 JSONValue 承接任意结构，用于结构不确定的字段。
    func flexValue(_ key: Key) -> JSONValue? {
        try? decodeIfPresent(JSONValue.self, forKey: key)
    }
}
