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
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        try process.run()
        process.waitUntilExit()
        let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if process.terminationStatus != 0 {
            let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw ShellError.nonZeroExit(code: process.terminationStatus, output: err)
        }
        return out
    }
}
