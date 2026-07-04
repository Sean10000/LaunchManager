enum CommandLineParser {
    static func parse(_ command: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inSingle = false
        var inDouble = false
        let chars = Array(command)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "'" && !inDouble {
                inSingle.toggle()
                i += 1
                continue
            }
            if c == "\"" && !inSingle {
                inDouble.toggle()
                i += 1
                continue
            }
            if c.isWhitespace && !inSingle && !inDouble {
                if !current.isEmpty {
                    result.append(current)
                    current = ""
                }
                i += 1
                continue
            }
            if c == "\\" && inDouble && i + 1 < chars.count {
                current.append(chars[i + 1])
                i += 2
                continue
            }
            current.append(c)
            i += 1
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}
