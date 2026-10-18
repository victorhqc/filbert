import Foundation

struct LocalizedLookup {
    let location: String
    let arguments: String
    let key: LookupKey?
}

struct LookupKey {
    let segments: [String]

    var isInterpolated: Bool {
        segments.count > 1
    }

    /// Swift builds interpolated keys with one plain specifier per value, never a
    /// positional one, and escapes literal `%` as `%%`.
    func matches(_ catalogKey: String) -> Bool {
        guard isInterpolated else { return catalogKey == segments[0] }
        let specifier = "%(?:@|lld|ld|d|lf|f|llu|lu)"
        let pattern = segments
            .map { NSRegularExpression.escapedPattern(for: $0.replacingOccurrences(of: "%", with: "%%")) }
            .joined(separator: specifier)
        return catalogKey.range(of: "^\(pattern)$", options: .regularExpression) != nil
    }
}

enum LocalizedSourceScanner {
    static func lookups(in source: String, file: String) -> [LocalizedLookup] {
        let chars = Array(source)
        let text = String(chars)
        var results: [LocalizedLookup] = []
        var searchStart = text.startIndex
        while let match = text.range(
            of: #"String\(\s*displayLocalized:\s*"#,
            options: .regularExpression,
            range: searchStart ..< text.endIndex
        ) {
            let callStart = text.distance(from: text.startIndex, to: match.lowerBound)
            let argumentsStart = callStart + "String(".count
            let keyStart = text.distance(from: text.startIndex, to: match.upperBound)
            let close = scanCode(chars, from: argumentsStart)
            let line = chars[..<callStart].filter { $0 == "\n" }.count + 1
            results.append(LocalizedLookup(
                location: "\(file):\(line)",
                arguments: String(chars[argumentsStart ..< close]),
                key: chars[keyStart] == "\"" ? literal(chars, at: keyStart) : nil
            ))
            searchStart = text.index(text.startIndex, offsetBy: close)
        }
        return results
    }

    static func scanCode(_ chars: [Character], from start: Int) -> Int {
        var depth = 0
        var index = start
        while index < chars.count {
            switch chars[index] {
            case "\"":
                index = scanString(chars, from: index)
                continue
            case "(", "[", "{":
                depth += 1
            case ")", "]", "}":
                if depth == 0 {
                    return index
                }
                depth -= 1
            default:
                break
            }
            index += 1
        }
        return index
    }

    static func scanString(_ chars: [Character], from start: Int) -> Int {
        let isMultiline = isTripleQuote(chars, at: start)
        var index = start + (isMultiline ? 3 : 1)
        while index < chars.count {
            if chars[index] == "\\" {
                index = chars[index + 1] == "(" ? scanCode(chars, from: index + 2) + 1 : index + 2
                continue
            }
            if isMultiline, isTripleQuote(chars, at: index) {
                return index + 3
            }
            if !isMultiline, chars[index] == "\"" {
                return index + 1
            }
            index += 1
        }
        return index
    }

    private static func isTripleQuote(_ chars: [Character], at index: Int) -> Bool {
        index + 2 < chars.count && chars[index] == "\"" && chars[index + 1] == "\"" && chars[index + 2] == "\""
    }

    private static func literal(_ chars: [Character], at start: Int) -> LookupKey {
        let isMultiline = isTripleQuote(chars, at: start)
        let delimiter = isMultiline ? 3 : 1
        let end = scanString(chars, from: start)
        var body = Array(chars[(start + delimiter) ..< (end - delimiter)])
        if isMultiline {
            body = multilineContent(body)
        }

        var segments: [String] = []
        var current = ""
        var index = 0
        while index < body.count {
            guard body[index] == "\\" else {
                current.append(body[index])
                index += 1
                continue
            }
            let next = body[index + 1]
            if next == "(" {
                segments.append(current)
                current = ""
                index = scanCode(body, from: index + 2) + 1
            } else if next == "u" {
                let closing = body[index...].firstIndex(of: "}") ?? index
                let hex = String(body[(index + 3) ..< closing])
                if let scalar = UInt32(hex, radix: 16).flatMap(Unicode.Scalar.init) {
                    current.append(Character(scalar))
                }
                index = closing + 1
            } else {
                current.append(["n": "\n", "t": "\t", "0": "\0"][next] ?? next)
                index += 2
            }
        }
        segments.append(current)
        return LookupKey(segments: segments)
    }

    private static func multilineContent(_ body: [Character]) -> [Character] {
        var lines = String(body).components(separatedBy: "\n")
        let indentation = lines.removeLast()
        let content = lines.dropFirst()
            .map { $0.hasPrefix(indentation) ? String($0.dropFirst(indentation.count)) : $0 }
            .joined(separator: "\n")
        return Array(content.replacingOccurrences(of: "\\\n", with: ""))
    }
}
