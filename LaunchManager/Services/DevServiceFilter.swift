import Foundation

struct DevServiceFilter {
    private let devPorts: Set<Int> = {
        var ports = Set<Int>()
        ports.formUnion(3000...3010)
        ports.formUnion([4000, 4173, 5001, 5173, 5432, 6379, 8080, 8443, 9000, 11434, 27017])
        ports.formUnion(8000...8008)
        return ports
    }()

    private let devExecutables: Set<String> = [
        "node", "python", "python3", "go", "java", "ruby", "nginx",
        "docker-proxy", "com.docker", "redis-server", "postgres", "mongod", "ollama",
    ]

    private let devFrameworkNames: Set<String> = [
        "Next.js", "Vite", "Nuxt", "FastAPI", "Flask", "Django", "NestJS", "Rust", "Go",
        "Webpack Dev", "Python HTTP",
    ]

    private let excludedExecutables: Set<String> = [
        "controlcenter", "rapportd", "ardagent", "mdnsresponder", "limactl", "cloudflared",
    ]

    func isDevService(_ service: Service) -> Bool {
        let exeName = (service.executable as NSString).lastPathComponent.lowercased()

        if excludedExecutables.contains(exeName) { return false }
        if service.identityKind == .hostMechanism { return false }

        if devFrameworkNames.contains(service.displayName) { return true }

        if devExecutables.contains(exeName) || service.executable.lowercased().contains("com.docker") {
            return true
        }

        // Port alone is not enough — avoids macOS Control Center on :5000/:7000
        if devPorts.contains(service.port) {
            return devExecutables.contains(exeName) || devFrameworkNames.contains(service.displayName)
        }

        return false
    }

    func filter(_ services: [Service], showAll: Bool) -> [Service] {
        guard !showAll else { return services }
        return services.filter(isDevService)
    }
}
