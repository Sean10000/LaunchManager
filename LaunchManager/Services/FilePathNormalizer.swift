import Foundation

enum FilePathNormalizer {
    /// Normalizes filesystem paths and shell-sourced strings for correct Unicode display.
    static func display(_ text: String) -> String {
        let normalized = normalize(text)
        guard normalized.hasPrefix("/") else { return normalized }
        // Avoid URL round-trip for non-ASCII paths; kernel and plist paths are already UTF-8.
        if normalized.contains(where: { !$0.isASCII }) {
            return normalized
        }
        return URL(fileURLWithPath: normalized).path
    }

    static func normalize(_ path: String) -> String {
        let decoded = decodeLsofOctalEscapes(path)
        if let repaired = repairUTF8Mojibake(decoded) {
            return repaired
        }
        return decoded
    }

    /// lsof may encode non-ASCII bytes as `\ooo` when locale encoding is limited.
    static func decodeLsofOctalEscapes(_ path: String) -> String {
        guard path.contains("\\") else { return path }

        var bytes = [UInt8]()
        var index = path.startIndex
        while index < path.endIndex {
            if path[index] == "\\" {
                let afterSlash = path.index(after: index)
                var cursor = afterSlash
                var value = 0
                var digits = 0
                while cursor < path.endIndex, digits < 3, let digit = path[cursor].wholeNumberValue, digit < 8 {
                    value = value * 8 + digit
                    cursor = path.index(after: cursor)
                    digits += 1
                }
                if digits > 0 {
                    bytes.append(UInt8(value))
                    index = cursor
                    continue
                }
            }
            for byte in String(path[index]).utf8 {
                bytes.append(byte)
            }
            index = path.index(after: index)
        }
        return String(data: Data(bytes), encoding: .utf8) ?? path
    }

    /// Repairs UTF-8 text that was misinterpreted as a legacy byte encoding.
    static func repairUTF8Mojibake(_ string: String) -> String? {
        guard string.contains(where: { !$0.isASCII }) else { return nil }
        // Already valid CJK — do not run legacy re-encoding (it corrupts good Unicode).
        if containsCJK(string) { return nil }
        guard containsMojibakeMarkers(string) else { return nil }

        let candidateEncodings: [String.Encoding] = [
            .isoLatin1,
            .windowsCP1252,
            macOSRoman,
        ]

        for encoding in candidateEncodings {
            guard let bytes = string.data(using: encoding, allowLossyConversion: true),
                  let repaired = String(data: bytes, encoding: .utf8),
                  repaired != string
            else { continue }
            if containsCJK(repaired) || !containsMojibakeMarkers(repaired) {
                return repaired
            }
        }
        return nil
    }

    private static let macOSRoman = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringBuiltInEncodings.macRoman.rawValue
        )
    )

    private static func containsCJK(_ string: String) -> Bool {
        string.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
    }

    private static func containsMojibakeMarkers(_ string: String) -> Bool {
        string.unicodeScalars.contains { scalar in
            (0x00C0...0x00FF).contains(scalar.value) && !scalar.isASCII
        }
    }
}
