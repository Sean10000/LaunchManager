import Darwin
import Foundation

/// Reads the process command line from the kernel (UTF-8), avoiding ps/locale mojibake.
enum ProcessCommandLineResolver {
    static func commandLine(for pid: pid_t) -> String? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROCARGS2, pid]
        var size: size_t = 0
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else { return nil }

        var buffer = [UInt8](repeating: 0, count: Int(size))
        let status = buffer.withUnsafeMutableBytes { raw in
            sysctl(&mib, 4, raw.baseAddress, &size, nil, 0)
        }
        guard status == 0 else { return nil }

        var cursor = MemoryLayout<Int32>.size
        guard cursor < buffer.count else { return nil }

        // Skip executable path stored after argc.
        while cursor < buffer.count && buffer[cursor] != 0 { cursor += 1 }
        guard cursor < buffer.count else { return nil }
        cursor += 1

        while cursor < buffer.count && cursor % MemoryLayout<Int64>.size != 0 { cursor += 1 }

        var args: [String] = []
        while cursor < buffer.count {
            if buffer[cursor] == 0 {
                cursor += 1
                if args.isEmpty == false && cursor < buffer.count && buffer[cursor] == 0 { break }
                continue
            }
            let start = cursor
            while cursor < buffer.count && buffer[cursor] != 0 { cursor += 1 }
            if let arg = String(bytes: buffer[start..<cursor], encoding: .utf8), !arg.isEmpty {
                args.append(arg)
            }
            cursor += 1
        }

        let line = args.joined(separator: " ")
        return line.isEmpty ? nil : line
    }
}
