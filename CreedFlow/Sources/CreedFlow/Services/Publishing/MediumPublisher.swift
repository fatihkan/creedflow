import Foundation

/// Publishes content to Medium via their API.
struct MediumPublisher: PublisherProtocol {
    let channelType = PublishingChannel.ChannelType.medium

    func publish(content: ExportedContent, options: PublishOptions) async throws -> PublicationResult {
        let credentials = options.credentials
        guard let token = credentials["token"] else {
            throw PublishingError.missingCredential("Medium integration token")
        }

        // Step 1: Get authenticated user ID
        let userId = try await getMeUserId(token: token)

        // Step 2: Create post
        let url = URL(string: "https://api.medium.com/v1/users/\(userId)/posts")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let contentFormat = content.format == .html ? "html" : "markdown"
        let body: [String: Any] = [
            "title": options.title,
            "contentFormat": contentFormat,
            "content": content.body,
            "tags": options.tags,
            "publishStatus": options.isDraft ? "draft" : "public"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw PublishingError.apiError("Medium API error: \(errorText)")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let postData = json?["data"] as? [String: Any]
        let postId = postData?["id"] as? String ?? ""
        let postUrl = postData?["url"] as? String ?? ""

        return PublicationResult(externalId: postId, url: postUrl, publishedAt: Date())
    }

    func validateCredentials(_ credentials: [String: String]) async throws -> Bool {
        guard let token = credentials["token"] else { return false }
        _ = try await getMeUserId(token: token)
        return true
    }

    private func getMeUserId(token: String) async throws -> String {
        let url = URL(string: "https://api.medium.com/v1/me")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let userData = json?["data"] as? [String: Any],
              let userId = userData["id"] as? String else {
            throw PublishingError.apiError("Failed to get Medium user ID")
        }
        return userId
    }
}
