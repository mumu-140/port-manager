import Foundation
import Testing
@testable import PortKiller

/**
 * Regression guards for the localization system.
 *
 * These tests inspect both the translation tables and the Swift sources so a
 * new user-visible string cannot ship untranslated, and so an `L(...)` call
 * cannot reference a key that does not exist.
 */
struct LocalizationRegressionTests {

    // MARK: - Format specifiers

    /// Every `L(key, args...)` call goes through `String(format:)`, so the
    /// English and Simplified Chinese variants must carry the same printf
    /// specifiers in the same order. A mismatch silently corrupts the output.
    @Test func formatSpecifiersMatchAcrossLanguages() throws {
        let pattern = try NSRegularExpression(
            pattern: "%(?:\\d+\\$)?[-+ #0]*\\d*(?:\\.\\d+)?(?:@|ld|lu|d|s|f|%)"
        )
        for (key, pair) in LocalizationTables.all {
            let english = specifiers(in: pair.en, matching: pattern)
            let chinese = specifiers(in: pair.zh, matching: pattern)
            #expect(english == chinese,
                    "\(key): en has \(english) but zh has \(chinese)")
        }
    }

    // MARK: - Key existence

    /// Every `L("...")` key in the sources must resolve to a table entry,
    /// otherwise the UI renders the raw key at runtime.
    @Test func everyLocalizationKeyExistsInTables() throws {
        let known = Set(LocalizationTables.all.keys)
        var missing: [String] = []
        for url in try swiftSources() {
            let source = try String(contentsOf: url, encoding: .utf8)
            for key in localizationKeys(in: source) where !known.contains(key) {
                missing.append("\(url.lastPathComponent): \(key)")
            }
        }
        #expect(missing.isEmpty,
                "L(...) keys without a translation:\n\(missing.joined(separator: "\n"))")
    }

    // MARK: - Hardcoded English gate

    /// User-visible SwiftUI literals must go through `L(...)`. This is a
    /// coarse gate: it flags any string literal containing ASCII letters that
    /// is passed directly to a common text-bearing initializer.
    @Test func noHardcodedEnglishUIStrings() throws {
        let initializers = "Text|Button|Label|TextField|SecureField|Toggle|Picker|navigationTitle|navigationSubtitle|confirmationDialog|accessibilityLabel|help|alert"
        let pattern = try NSRegularExpression(
            pattern: "(?:\(initializers))\\s*\\(\\s*\"((?:[^\"\\\\]|\\\\.)*)\""
        )
        let allowlist: Set<String> = ["productdevbook"]
        var offenders: [String] = []
        for url in try swiftSources() {
            let source = try String(contentsOf: url, encoding: .utf8)
            let ns = source as NSString
            for match in pattern.matches(in: source, range: NSRange(location: 0, length: ns.length)) {
                guard match.numberOfRanges > 1 else { continue }
                let literal = ns.substring(with: match.range(at: 1))
                let visible = strippingInterpolations(from: literal)
                guard containsASCIILetter(visible), !allowlist.contains(visible) else { continue }
                offenders.append("\(url.lastPathComponent):\(lineNumber(in: source, at: match.range.location)): \"\(literal)\"")
            }
        }
        #expect(offenders.isEmpty,
                "Hardcoded English UI strings (wrap in L(...)):\n\(offenders.joined(separator: "\n"))")
    }

    // MARK: - Helpers

    private func specifiers(in text: String, matching pattern: NSRegularExpression) -> [String] {
        let ns = text as NSString
        return pattern.matches(in: text, range: NSRange(location: 0, length: ns.length))
            .map { ns.substring(with: $0.range) }
    }

    /// Every `.swift` file under the package's `Sources` directory.
    private func swiftSources() throws -> [URL] {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sources = packageRoot.appendingPathComponent("Sources", isDirectory: true)
        let enumerator = FileManager.default.enumerator(
            at: sources,
            includingPropertiesForKeys: [.isRegularFileKey]
        )
        var urls: [URL] = []
        while let url = enumerator?.nextObject() as? URL {
            if url.pathExtension == "swift" { urls.append(url) }
        }
        return urls
    }

    /// Dot-namespaced string literals passed to `L(...)`, tolerating nested
    /// parentheses and ternaries inside the call.
    private func localizationKeys(in source: String) -> [String] {
        let chars = Array(source)
        var keys: [String] = []
        var i = 0
        while i < chars.count {
            let character = chars[i]
            if character == "/", i + 1 < chars.count, chars[i + 1] == "/" {
                while i < chars.count, chars[i] != "\n" { i += 1 }
                continue
            }
            if character == "/", i + 1 < chars.count, chars[i + 1] == "*" {
                i += 2
                while i + 1 < chars.count, !(chars[i] == "*" && chars[i + 1] == "/") { i += 1 }
                i = min(i + 2, chars.count)
                continue
            }
            if character == "\"" {
                i = skipStringLiteral(in: chars, from: i)
                continue
            }
            if character == "L", i + 1 < chars.count, chars[i + 1] == "(" {
                let previous = i > 0 ? chars[i - 1] : nil
                if previous == nil || !(previous!.isLetter || previous!.isNumber || previous! == "_") {
                    i = collectLocalizationKeys(in: chars, from: i, into: &keys)
                    continue
                }
            }
            i += 1
        }
        return keys
    }

    /// Index just past the string literal starting at the given quote.
    private func skipStringLiteral(in chars: [Character], from start: Int) -> Int {
        var i = start
        if i + 2 < chars.count, chars[i + 1] == "\"", chars[i + 2] == "\"" {
            i += 3
            while i + 2 < chars.count,
                  !(chars[i] == "\"" && chars[i + 1] == "\"" && chars[i + 2] == "\"") {
                i += 1
            }
            return min(i + 3, chars.count)
        }
        i += 1
        while i < chars.count {
            if chars[i] == "\\" { i += 2; continue }
            if chars[i] == "\"" { return i + 1 }
            i += 1
        }
        return i
    }

    /// Collect the keys passed to the call starting at the given index;
    /// returns the index just past the call.
    private func collectLocalizationKeys(in chars: [Character], from start: Int, into keys: inout [String]) -> Int {
        var j = start + 2
        var depth = 1
        while j < chars.count {
            let character = chars[j]
            if character == "\"" {
                var literal = ""
                j += 1
                while j < chars.count {
                    let inner = chars[j]
                    if inner == "\\", j + 1 < chars.count {
                        if chars[j + 1] == "(" {
                            var interpolationDepth = 1
                            j += 2
                            while j < chars.count, interpolationDepth > 0 {
                                if chars[j] == "\\", j + 1 < chars.count, chars[j + 1] == "(" {
                                    interpolationDepth += 1
                                    j += 2
                                    continue
                                }
                                if chars[j] == "(" { interpolationDepth += 1 }
                                else if chars[j] == ")" { interpolationDepth -= 1 }
                                j += 1
                            }
                            literal.append("()")
                            continue
                        }
                        j += 2
                        continue
                    }
                    if inner == "\"" { j += 1; break }
                    literal.append(inner)
                    j += 1
                }
                if depth == 1, isKeyShaped(literal) { keys.append(literal) }
                continue
            }
            if character == "(" {
                depth += 1
            } else if character == ")" {
                depth -= 1
                if depth == 0 { return j + 1 }
            }
            j += 1
        }
        return j
    }

    /// A translation key is dot-namespaced and made of identifier characters.
    private func isKeyShaped(_ text: String) -> Bool {
        guard text.contains(".") else { return false }
        for scalar in text.unicodeScalars {
            let value = scalar.value
            let allowed = (value >= 65 && value <= 90)
                || (value >= 97 && value <= 122)
                || (value >= 48 && value <= 57)
                || value == 46
                || value == 95
            if !allowed { return false }
        }
        return true
    }

    /// Remove `\(...)` interpolations and `\\u{...}` escapes, leaving only
    /// the literal text the user actually sees.
    private func strippingInterpolations(from literal: String) -> String {
        let chars = Array(literal)
        var output = ""
        var i = 0
        while i < chars.count {
            let character = chars[i]
            if character == "\\", i + 1 < chars.count {
                let next = chars[i + 1]
                if next == "(" {
                    var depth = 1
                    i += 2
                    while i < chars.count, depth > 0 {
                        if chars[i] == "(" {
                            depth += 1
                        } else if chars[i] == ")" {
                            depth -= 1
                        }
                        i += 1
                    }
                    continue
                }
                if next == "u", i + 2 < chars.count, chars[i + 2] == "{" {
                    var k = i + 3
                    while k < chars.count, chars[k] != "}" { k += 1 }
                    i = min(k + 1, chars.count)
                    continue
                }
                output.append(next)
                i += 2
                continue
            }
            output.append(character)
            i += 1
        }
        return output
    }

    private func containsASCIILetter(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (scalar.value >= 65 && scalar.value <= 90) || (scalar.value >= 97 && scalar.value <= 122)
        }
    }

    private func lineNumber(in source: String, at location: Int) -> Int {
        let ns = source as NSString
        let prefix = ns.substring(to: min(location, ns.length))
        return prefix.reduce(into: 1) { count, character in
            if character == "\n" { count += 1 }
        }
    }
}
