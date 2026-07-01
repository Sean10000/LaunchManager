import Foundation

struct DevServiceFilter {
    private let devPorts: Set<Int> = {
        var ports = Set<Int>()
        ports.formUnion(3000...3010)
        ports.formUnion([4000, 4173, 5000, 5001, 5173, 5432, 6379, 8080, 8443, 9000, 11434, 27017])
        ports.formUnion(8000...8008)
        return ports
    }()

    private let devExecutables: Set<String> = [
        "node", "python", "python3", "go", "java", "ruby", "nginx",
        "docker-proxy", "com.docker", "redis-server", "postgres", "mongod", "ollama",
    ]

    private let devFrameworkNames: Set<String> = [
        "Next.js", "Vite", "Nuxt", "FastAPI", "Flask", "Django", "Rust", "Go",
    ]

    func isDevService(_ service: Service) -> Bool {
        if devPorts.contains(service.port) {
            return true
        }

        let exeName = (service.executable as NSString).lastPathComponent.lowercased()
        if devExecutables.contains(exeName) {
            return true
        }
        if service.executable.lowercased().contains("com.docker") {
            return true
        }

        if devFrameworkNames.contains(service.displayName) {
            return true
        }

        return false
    }

    func filter(_ services: [Service], showAll: Bool) -> [Service] {
        guard !showAll else { return services }
        return services.filter(isDevService)
    }
}
