import Foundation

/// Publishes content to WordPress via REST API.
struct WordPressPublisher: PublisherProtocol {
    let channelType = PublishingChannel.ChannelType.wordpress

    func publish(content: ExportedContent, options: PublishOptions) async throws -> PublicationResult {
        let credentials = options.credentials
        guard let siteUrl = credentials["site_url"],
              let username = credentials["username"],
              let appPassword = credentials["app_password"] else {
            throw PublishingError.missingCredential("WordPress site_url, username, and app_password")
        }

        let endpoint = "\(siteUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/wp-json/wp/v2/posts"
        guard let url = URL(string: endpoint) else {
            throw PublishingError.apiError("Invalid WordPress URL: \(endpoint)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Basic auth with application password
        let authString = "\(username):\(appPassword)"
        if let authData = authString.data(using: .utf8) {
            request.setValue("Basic \(authData.base64EncodedString())", forHTTPHeaderField: "Authorization")
        }

        let htmlContent = content.format == .html ? content.body : content.body
        let status = options.isDraft ? "draft" : "publish"
        let body: [String: Any] = [
            "title": options.title,
            "content": htmlContent,
            "status": status,
            "tags": options.tags
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw PublishingError.apiError("WordPress API error: \(errorText)")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let postId = json?["id"] as? Int ?? 0
        let postUrl = json?["link"] as? String ?? ""

        return PublicationResult(externalId: String(postId), url: postUrl, publishedAt: Date())
    }

    func validateCredentials(_ credentials: [String: String]) async throws -> Bool {
        guard let siteUrl = credentials["site_url"],
              let username = credentials["username"],
              let appPassword = credentials["app_password"] else { return false }

        let endpoint = "\(siteUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/wp-json/wp/v2/users/me"
        guard let url = URL(string: endpoint) else { return false }

        var request = URLRequest(url: url)
        let authString = "\(username):\(appPassword)"
        if let authData = authString.data(using: .utf8) {
            request.setValue("Basic \(authData.base64EncodedString())", forHTTPHeaderField: "Authorization")
        }

        let (_, response) = try await URLSession.shared.data(for: request)
        return (response as? HTTPURLResponse)?.statusCode == 200
    }
}
