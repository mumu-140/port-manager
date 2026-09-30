import Foundation

/// Community supporters and contributors window.
enum SponsorStrings {
    static let entries: [String: (en: String, zh: String)] = [
        "sponsor.title": (en: "Community", zh: "社区"),
        "sponsor.thankYou": (en: "Thanks to everyone supporting and contributing to PortKiller!", zh: "感谢所有支持和参与 PortKiller 的贡献者！"),
        "sponsor.becomeSponsor": (en: "Support Project", zh: "支持项目"),
        "sponsor.activeSponsors": (en: "Current Supporters", zh: "当前支持者"),
        "sponsor.contributors": (en: "Contributors", zh: "贡献者"),
        "sponsor.noContributors": (en: "No contributors found", zh: "未找到贡献者"),
        "sponsor.pastSponsors": (en: "Past Supporters", zh: "往期支持者"),
        "sponsor.loadFailed": (en: "Couldn't load community data", zh: "无法加载社区数据"),
        "sponsor.tryAgain": (en: "Try Again", zh: "重试"),
        "sponsor.beFirst": (en: "No supporters or contributors listed yet", zh: "暂未列出支持者或贡献者"),
        "sponsor.sponsor": (en: "Support", zh: "支持"),
        "sponsor.visit": (en: "Visit", zh: "访问"),
        "sponsor.interval.monthly": (en: "Monthly", zh: "每月"),
        "sponsor.interval.bimonthly": (en: "Every 2 Months", zh: "每 2 个月"),
        "sponsor.interval.quarterly": (en: "Every 3 Months", zh: "每 3 个月"),
        "sponsor.interval.never": (en: "Never", zh: "从不"),
        "sponsor.error.network": (en: "Network error: %@", zh: "网络错误：%@"),
        "sponsor.error.invalidResponse": (en: "Invalid response from server", zh: "服务器返回了无效响应"),
        "sponsor.error.decoding": (en: "Failed to parse community data: %@", zh: "解析社区数据失败：%@"),
    ]
}
