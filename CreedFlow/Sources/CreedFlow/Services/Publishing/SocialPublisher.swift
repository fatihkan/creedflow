import Foundation

/// Publishes content to Twitter/X via API v2.
struct TwitterPublisher: PublisherProtocol {
    let channelType = PublishingChannel.ChannelType.twitter

    func publish(content: ExportedContent, options: PublishOptions) async throws -> PublicationResult {
        let credentials = options.credentials
        guard let bearerToken = credentials["bearer_token"] else {
            throw PublishingError.missingCredential("Twitter bearer_token")
        }

        let url = URL(string: "https://api.twitter.com/2/tweets")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Twitter has 280 char limit — truncate with link if needed
        let tweetText = String(content.body.prefix(280))
        let body: [String: Any] = ["text": tweetText]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw PublishingError.apiError("Twitter API error: \(errorText)")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let tweetData = json?["data"] as? [String: Any]
        let tweetId = tweetData?["id"] as? String ?? ""

        return PublicationResult(
            externalId: tweetId,
            url: "https://twitter.com/i/status/\(tweetId)",
            publishedAt: Date()
        )
    }

    func validateCredentials(_ credentials: [String: String]) async throws -> Bool {
        guard let bearerToken = credentials["bearer_token"] else { return false }

        let url = URL(string: "https://api.twitter.com/2/users/me")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await URLSession.shared.data(for: request)
        return (response as? HTTPURLResponse)?.statusCode == 200
    }
}

/// Publishes content to LinkedIn via API.
struct LinkedInPublisher: PublisherProtocol {
    let channelType = PublishingChannel.ChannelType.linkedin

    func publish(content: ExportedContent, options: PublishOptions) async throws -> PublicationResult {
        let credentials = options.credentials
        guard let accessToken = credentials["access_token"] else {
            throw PublishingError.missingCredential("LinkedIn access_token")
        }

        // Get user URN first
        let profileUrl = URL(string: "https://api.linkedin.com/v2/userinfo")!
        var profileRequest = URLRequest(url: profileUrl)
        profileRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (profileData, _) = try await URLSession.shared.data(for: profileRequest)
        let profileJson = try JSONSerialization.jsonObject(with: profileData) as? [String: Any]
        let sub = profileJson?["sub"] as? String ?? ""

        // Create post
        let url = URL(string: "https://api.linkedin.com/v2/ugcPosts")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let postText = String(content.body.prefix(3000))
        let body: [String: Any] = [
            "author": "urn:li:person:\(sub)",
            "lifecycleState": "PUBLISHED",
            "specificContent": [
                "com.linkedin.ugc.ShareContent": [
                    "shareCommentary": ["text": postText],
                    "shareMediaCategory": "NONE"
                ]
            ],
            "visibility": ["com.linkedin.ugc.MemberNetworkVisibility": "PUBLIC"]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw PublishingError.apiError("LinkedIn API error: \(errorText)")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let postId = json?["id"] as? String ?? ""

        return PublicationResult(externalId: postId, url: "https://linkedin.com", publishedAt: Date())
    }

    func validateCredentials(_ credentials: [String: String]) async throws -> Bool {
        guard let accessToken = credentials["access_token"] else { return false }
        let url = URL(string: "https://api.linkedin.com/v2/userinfo")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (_, response) = try await URLSession.shared.data(for: request)
        return (response as? HTTPURLResponse)?.statusCode == 200
    }
}
