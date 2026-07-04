import Foundation

struct LaunchAgentDraft: Equatable, Identifiable {
    var id: String { label }
    var label: String
    var program: String
    var programArguments: [String]
    var workingDirectory: String?
    var runAtLoad: Bool
    var keepAlive: Bool
    var triggerType: LaunchItem.TriggerType

    static func from(service: Service) -> LaunchAgentDraft? {
        guard service.runtimeGroup == .instance, service.killAllowed else { return nil }
        let args = CommandLineParser.parse(service.command)
        let program: String
        let programArguments: [String]
        if args.isEmpty {
            program = service.executable
            programArguments = []
        } else {
            program = args[0]
            programArguments = Array(args.dropFirst())
        }
        let slug = service.displayName
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let suggestedLabel = "dev.\(service.port).\(slug.isEmpty ? "service" : slug)"
        return LaunchAgentDraft(
            label: suggestedLabel,
            program: program,
            programArguments: programArguments,
            workingDirectory: service.workingDirectory ?? service.processDirectory,
            runAtLoad: true,
            keepAlive: false,
            triggerType: .atLoad
        )
    }
}
