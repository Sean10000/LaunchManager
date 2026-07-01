import Foundation

struct ListeningProcess: Identifiable, Hashable, Sendable {
    var id: String { "\(pid)-\(port)-\(protocolName)" }
    let pid: Int32
    let port: Int
    let protocolName: String
    let command: String
    let executable: String
    let workingDirectory: String?
}
