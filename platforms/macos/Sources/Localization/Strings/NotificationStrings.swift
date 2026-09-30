import Foundation

/// User-facing notification titles and bodies.
enum NotificationStrings {
    static let entries: [String: (en: String, zh: String)] = [
        "notification.connected": (en: "Connected", zh: "已连接"),
        "notification.connectedBody": (en: "%@ is ready on port %ld", zh: "%@ 已在端口 %ld 就绪"),
        "notification.disconnected": (en: "Disconnected", zh: "已断开"),
        "notification.disconnectedBody": (en: "%@ connection lost", zh: "%@ 连接已断开"),
        "notification.autoKill": (en: "Auto-Kill: %@", zh: "自动结束：%@"),
        "notification.autoKillBody": (en: "Port %ld killed after %ld min (rule: %@)", zh: "端口 %ld 在 %ld 分钟后被结束（规则：%@）"),
        "notification.portAvailable": (en: "Port %ld Available", zh: "端口 %ld 已可用"),
        "notification.portAvailableBody": (en: "Port is now free.", zh: "端口现已空闲。"),
        "notification.portInUse": (en: "Port %ld In Use", zh: "端口 %ld 已占用"),
        "notification.portInUseBody": (en: "Used by %@.", zh: "被 %@ 占用。"),
        "notification.tunnelActive": (en: "Tunnel Active", zh: "隧道已激活"),
        "notification.tunnelActiveBody": (en: "Port %ld available at %@", zh: "端口 %ld 可通过 %@ 访问"),
        "notification.newProcessType": (en: "New %@ on Port %ld", zh: "新的 %@ 出现在端口 %ld"),
        "notification.newProcessTypeBody": (en: "%@ started listening.", zh: "%@ 开始监听。"),
    ]
}
