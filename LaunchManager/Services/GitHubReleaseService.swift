import Foundation

struct GitHubRelease: Equatable, Sendable, Identifiable {
    var id: String { tagName }
    let version: AppVersion
    let tagName: String
    let releasePageURL: URL
    let downloadURL: URL

    static let homebrewUpgradeCommand = """
brew tap Sean10000/tap
brew upgrade --cask launchmanager
"""
}

enum GitHubReleaseService {
    private static let latestReleaseURL = URL(
        string: "https://api.github.com/repos/Sean10000/LaunchManager/releases/latest"
    )!

    static func fetchLatest(session: URLSession = .shared) async -> GitHubRelease? {
        var request = URLRequest(url: latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("LaunchManager/\(AppVersion.current.displayString)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }
            return parseLatestRelease(data: data)
        } catch {
            return nil
        }
    }

    static func parseLatestRelease(data: Data) -> GitHubRelease? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tagName = json["tag_name"] as? String,
              let version = AppVersion.parse(tagName),
              let releasePageString = json["html_url"] as? String,
              let releasePageURL = URL(string: releasePageString) else {
            return nil
        }

        let downloadURL: URL
        if let assets = json["assets"] as? [[String: Any]],
           let dmg = assets.first(where: { ($0["name"] as? String) == "LaunchManager.dmg" }),
           let dmgURLString = dmg["browser_download_url"] as? String,
           let dmgURL = URL(string: dmgURLString) {
            downloadURL = dmgURL
        } else {
            downloadURL = releasePageURL
        }

        return GitHubRelease(
            version: version,
            tagName: tagName,
            releasePageURL: releasePageURL,
            downloadURL: downloadURL
        )
    }
}
