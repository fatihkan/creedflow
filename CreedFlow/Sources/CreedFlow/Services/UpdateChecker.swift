import Foundation

package struct UpdateInfo {
    let latestVersion: String
    let currentVersion: String
    let releaseUrl: String
    let releaseNotes: String
}

package actor UpdateChecker {
    private let repoOwner = "fatihkan"
    private let repoName = "creedflow"
    private let currentVersion: String

    package init() {
        // Read from bundle or fallback
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            currentVersion = version
        } else {
            currentVersion = "1.3.0"
        }
    }

    package func checkForUpdates() async -> UpdateInfo? {
        let urlString = "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest"
        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return nil
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String,
                  let htmlUrl = json["html_url"] as? String else {
                return nil
            }

            let latestVersion = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
            let notes = json["body"] as? String ?? ""

            guard isNewer(latestVersion, than: currentVersion) else {
                return nil
            }

            return UpdateInfo(
                latestVersion: latestVersion,
                currentVersion: currentVersion,
                releaseUrl: htmlUrl,
                releaseNotes: notes
            )
        } catch {
            return nil // Fail silently
        }
    }

    private func isNewer(_ latest: String, than current: String) -> Bool {
        let latestParts = latest.split(separator: ".").compactMap { Int($0) }
        let currentParts = current.split(separator: ".").compactMap { Int($0) }

        for i in 0..<max(latestParts.count, currentParts.count) {
            let l = i < latestParts.count ? latestParts[i] : 0
            let c = i < currentParts.count ? currentParts[i] : 0
            if l > c { return true }
            if l < c { return false }
        }
        return false
    }
}
