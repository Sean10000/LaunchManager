import Foundation

enum ShellError: LocalizedError {
    case nonZeroExit(code: Int32, output: String)

    var errorDescription: String? {
        if case .nonZeroExit(_, let out) = self { return out }
        return nil
    }
}

protocol ShellRunner {
    func run(_ path: String, arguments: [String]) throws -> String
}

struct DefaultShellRunner: ShellRunner {
    func run(_ path: String, arguments: [String]) throws -> String {
        let process = Process()
        // Set UTF-8 locale for the tool without replacing the inherited environment.
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["LC_ALL=C.UTF-8", "LANG=C.UTF-8", path] + arguments
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        try process.run()
        process.waitUntilExit()
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        let out = String(data: outData, encoding: .utf8)
            ?? String(decoding: outData, as: UTF8.self)
        let err = String(data: errData, encoding: .utf8)
            ?? String(decoding: errData, as: UTF8.self)
        if process.terminationStatus != 0 {
            if path.hasSuffix("/lsof"), process.terminationStatus == 1, err.isEmpty {
                return out
            }
            throw ShellError.nonZeroExit(code: process.terminationStatus, output: err.isEmpty ? out : err)
        }
        return out
    }
}
