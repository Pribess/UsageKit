import Foundation

struct CodexUsageResponse: Codable {
    let accountID: String?
    let userID: String?
    let email: String?
    let planType: String?
    let rateLimit: CodexRateLimitDetails?
    let credits: CodexCredits?
    let additionalRateLimits: [CodexAdditionalRateLimit]?
    let codeReviewRateLimit: CodexRateLimitDetails?

    enum CodingKeys: String, CodingKey {
        case accountID = "account_id"
        case userID = "user_id"
        case email
        case planType = "plan_type"
        case rateLimit = "rate_limit"
        case credits
        case additionalRateLimits = "additional_rate_limits"
        case codeReviewRateLimit = "code_review_rate_limit"
    }

    var pctPrimary: Double {
        rateLimit?.primaryWindow?.pct ?? 0
    }

    var pctSecondary: Double {
        rateLimit?.secondaryWindow?.pct ?? 0
    }

    var primaryResetsAt: Date? {
        rateLimit?.primaryWindow?.resetsAtDate
    }

    var secondaryResetsAt: Date? {
        rateLimit?.secondaryWindow?.resetsAtDate
    }

    var primaryWindowLabel: String {
        rateLimit?.primaryWindow?.windowLabel ?? "P"
    }

    var secondaryWindowLabel: String {
        rateLimit?.secondaryWindow?.windowLabel ?? "S"
    }

    var primaryWindowDisplayLabel: String {
        rateLimit?.primaryWindow?.windowDisplayLabel ?? "Primary Window"
    }

    var secondaryWindowDisplayLabel: String {
        rateLimit?.secondaryWindow?.windowDisplayLabel ?? "Secondary Window"
    }
}

struct CodexAdditionalRateLimit: Codable {
    let limitName: String?
    let meteredFeature: String?
    let rateLimit: CodexRateLimitDetails?

    enum CodingKeys: String, CodingKey {
        case limitName = "limit_name"
        case meteredFeature = "metered_feature"
        case rateLimit = "rate_limit"
    }
}

struct CodexRateLimitDetails: Codable {
    let allowed: Bool?
    let limitReached: Bool?
    let primaryWindow: CodexRateLimitWindow?
    let secondaryWindow: CodexRateLimitWindow?

    enum CodingKeys: String, CodingKey {
        case allowed
        case limitReached = "limit_reached"
        case primaryWindow = "primary_window"
        case secondaryWindow = "secondary_window"
    }
}

struct CodexRateLimitWindow: Codable {
    let usedPercent: Int
    let limitWindowSeconds: Int
    let resetAfterSeconds: Int
    let resetAt: Int

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case limitWindowSeconds = "limit_window_seconds"
        case resetAfterSeconds = "reset_after_seconds"
        case resetAt = "reset_at"
    }

    var pct: Double {
        Double(usedPercent) / 100.0
    }

    var resetsAtDate: Date? {
        guard resetAt > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(resetAt))
    }

    var windowLabel: String {
        formatWindowLabel(limitWindowSeconds)
    }

    var windowDisplayLabel: String {
        formatWindowDisplayLabel(limitWindowSeconds)
    }
}

struct CodexCredits: Codable {
    let hasCredits: Bool
    let unlimited: Bool
    let balance: String?

    enum CodingKeys: String, CodingKey {
        case hasCredits = "has_credits"
        case unlimited
        case balance
    }
}

private func formatWindowLabel(_ seconds: Int) -> String {
    guard seconds > 0 else { return "0m" }

    if seconds % (24 * 3600) == 0 {
        return "\(seconds / (24 * 3600))d"
    }

    if seconds % 3600 == 0 {
        return "\(seconds / 3600)h"
    }

    if seconds % 60 == 0 {
        return "\(seconds / 60)m"
    }

    return "\(seconds)s"
}

private func formatWindowDisplayLabel(_ seconds: Int) -> String {
    guard seconds > 0 else { return "0-Minute Window" }

    if seconds % (24 * 3600) == 0 {
        let days = seconds / (24 * 3600)
        return "\(days)-Day Window"
    }

    if seconds % 3600 == 0 {
        let hours = seconds / 3600
        return "\(hours)-Hour Window"
    }

    if seconds % 60 == 0 {
        let minutes = seconds / 60
        return "\(minutes)-Minute Window"
    }

    return "\(seconds)-Second Window"
}
