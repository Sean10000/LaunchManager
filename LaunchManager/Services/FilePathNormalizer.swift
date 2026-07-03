import Foundation

enum FilePathNormalizer {
    /// Normalizes filesystem paths from shell tools (lsof, ps) for correct Unicode display.
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

    /// Repairs UTF-8 paths that were misinterpreted as ISO Latin-1 (e.g. 启动器.app → mojibake).
    static func repairUTF8Mojibake(_ string: String) -> String? {
        guard string.contains(where: { $0.isASCII == false }) else { return nil }
        guard let latin1 = string.data(using: .isoLatin1),
              let repaired = String(data: latin1, encoding: .utf8),
              repaired != string else { return nil }
        return repaired
    }
}
