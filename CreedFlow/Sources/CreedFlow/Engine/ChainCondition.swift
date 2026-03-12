import Foundation

/// Represents a condition that can be evaluated against step output and review data
/// to decide whether a chain step passes or should branch to an alternative step.
///
/// Serialized as JSON in the `condition` column of `promptChainStep`.
/// Example: `{"field":"reviewScore","op":"gte","value":7}`
struct ChainCondition: Codable, Equatable {
    let field: ConditionField
    let op: ConditionOperator
    let value: ConditionValue

    enum ConditionField: String, Codable, CaseIterable {
        case reviewScore
        case reviewVerdict
        case outputContains
        case stepSuccess
    }

    enum ConditionOperator: String, Codable, CaseIterable {
        case eq
        case neq
        case gt
        case gte
        case lt
        case lte
        case contains
        case notContains
    }

    enum ConditionValue: Codable, Equatable {
        case number(Double)
        case string(String)
        case bool(Bool)

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let d = try? container.decode(Double.self) {
                self = .number(d)
            } else if let b = try? container.decode(Bool.self) {
                self = .bool(b)
            } else if let s = try? container.decode(String.self) {
                self = .string(s)
            } else {
                throw DecodingError.typeMismatch(
                    ConditionValue.self,
                    DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected number, string, or bool")
                )
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .number(let d): try container.encode(d)
            case .string(let s): try container.encode(s)
            case .bool(let b): try container.encode(b)
            }
        }

        var doubleValue: Double? {
            switch self {
            case .number(let d): return d
            case .string(let s): return Double(s)
            case .bool(let b): return b ? 1.0 : 0.0
            }
        }

        var stringValue: String {
            switch self {
            case .number(let d): return String(d)
            case .string(let s): return s
            case .bool(let b): return String(b)
            }
        }
    }

    /// Evaluate this condition against step output and optional review data.
    /// - Parameters:
    ///   - stepOutput: The text output of the step that just executed
    ///   - reviewScore: Latest review score for the task (if any)
    ///   - reviewVerdict: Latest review verdict string (if any)
    /// - Returns: `true` if the condition passes, `false` otherwise
    func evaluate(stepOutput: String?, reviewScore: Double?, reviewVerdict: String?) -> Bool {
        switch field {
        case .reviewScore:
            guard let score = reviewScore, let target = value.doubleValue else { return false }
            return compareNumbers(score, target)

        case .reviewVerdict:
            let verdict = reviewVerdict ?? ""
            let target = value.stringValue
            return compareStrings(verdict, target)

        case .outputContains:
            let output = stepOutput ?? ""
            let target = value.stringValue
            switch op {
            case .contains: return output.localizedCaseInsensitiveContains(target)
            case .notContains: return !output.localizedCaseInsensitiveContains(target)
            case .eq: return output == target
            case .neq: return output != target
            default: return output.localizedCaseInsensitiveContains(target)
            }

        case .stepSuccess:
            let hasOutput = !(stepOutput ?? "").isEmpty
            switch value {
            case .bool(let expected): return hasOutput == expected
            default: return hasOutput
            }
        }
    }

    private func compareNumbers(_ lhs: Double, _ rhs: Double) -> Bool {
        switch op {
        case .eq: return lhs == rhs
        case .neq: return lhs != rhs
        case .gt: return lhs > rhs
        case .gte: return lhs >= rhs
        case .lt: return lhs < rhs
        case .lte: return lhs <= rhs
        case .contains, .notContains: return lhs == rhs
        }
    }

    private func compareStrings(_ lhs: String, _ rhs: String) -> Bool {
        switch op {
        case .eq: return lhs.lowercased() == rhs.lowercased()
        case .neq: return lhs.lowercased() != rhs.lowercased()
        case .contains: return lhs.localizedCaseInsensitiveContains(rhs)
        case .notContains: return !lhs.localizedCaseInsensitiveContains(rhs)
        case .gt, .gte, .lt, .lte: return lhs.lowercased() == rhs.lowercased()
        }
    }

    /// Decode a ChainCondition from a JSON string.
    static func decode(from jsonString: String) -> ChainCondition? {
        guard let data = jsonString.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ChainCondition.self, from: data)
    }
}
