import Foundation

/// Sponsors window.
enum SponsorStrings {
    static let entries: [String: (en: String, zh: String)] = [
        "sponsor.title": (en: "Sponsors", zh: "赞助者"),
        "sponsor.thankYou": (en: "Thank you for supporting PortKiller!", zh: "感谢你对 PortKiller 的支持！"),
        "sponsor.becomeSponsor": (en: "Become a Sponsor", zh: "成为赞助者"),
        "sponsor.activeSponsors": (en: "Active Sponsors", zh: "活跃赞助者"),
        "sponsor.contributors": (en: "Contributors", zh: "贡献者"),
        "sponsor.noContributors": (en: "No contributors found", zh: "未找到贡献者"),
        "sponsor.pastSponsors": (en: "Past Sponsors", zh: "往期赞助者"),
        "sponsor.loadFailed": (en: "Couldn't load sponsors", zh: "无法加载赞助者"),
        "sponsor.tryAgain": (en: "Try Again", zh: "重试"),
        "sponsor.beFirst": (en: "Be the first sponsor!", zh: "成为第一位赞助者！"),
        "sponsor.sponsor": (en: "Sponsor", zh: "赞助"),
        "sponsor.visit": (en: "Visit", zh: "访问"),
        "sponsor.interval.monthly": (en: "Monthly", zh: "每月"),
        "sponsor.interval.bimonthly": (en: "Every 2 Months", zh: "每 2 个月"),
        "sponsor.interval.quarterly": (en: "Every 3 Months", zh: "每 3 个月"),
        "sponsor.interval.never": (en: "Never", zh: "从不"),
        "sponsor.error.network": (en: "Network error: %@", zh: "网络错误：%@"),
        "sponsor.error.invalidResponse": (en: "Invalid response from server", zh: "服务器返回了无效响应"),
        "sponsor.error.decoding": (en: "Failed to parse sponsors: %@", zh: "解析赞助者数据失败：%@"),
    ]
}
