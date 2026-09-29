import Foundation

/// Cloudflare Tunnel UI: quick tunnels, named tunnels, ingress rules, tunnel
/// logs, and connection status.
enum TunnelStrings {
    static let entries: [String: (en: String, zh: String)] = [
        // Tunnel status / summary
        "tunnel.starting": (en: "Starting…", zh: "正在启动…"),
        "tunnel.managedElsewhere": (en: "Managed elsewhere", zh: "由外部管理"),
        "tunnel.noIngress": (en: "No ingress", zh: "无 Ingress 规则"),
        "tunnel.routeCount": (en: "%d route(s)", zh: "%d 条路由"),
        "tunnel.activeEdgeConnections": (en: "%d active edge connections", zh: "%d 个活跃边缘连接"),

        // Tunnel actions
        "tunnel.runTunnel": (en: "Run Tunnel", zh: "运行隧道"),
        "tunnel.stopTunnel": (en: "Stop Tunnel", zh: "停止隧道"),
        "tunnel.runHelp": (en: "Run tunnel", zh: "运行隧道"),
        "tunnel.stopHelp": (en: "Stop tunnel", zh: "停止隧道"),
        "tunnel.openRoute": (en: "Open %@", zh: "打开 %@"),

        // Cloudflare Tunnels list pane (CloudflareTunnelsView)
        "tunnel.title": (en: "Cloudflare Tunnels", zh: "Cloudflare 隧道"),
        "tunnel.refreshListHelp": (en: "Refresh tunnel list", zh: "刷新隧道列表"),
        "tunnel.stopAllMine": (en: "Stop All My Tunnels", zh: "停止我的全部隧道"),
        "tunnel.stopAllQuick": (en: "Stop All Quick Tunnels", zh: "停止全部快速隧道"),
        "tunnel.moreActions": (en: "More actions", zh: "更多操作"),
        "tunnel.runningCount": (en: "%d running", zh: "%d 个运行中"),
        "tunnel.quickCount": (en: "%d quick", zh: "%d 个快速"),
        "tunnel.noActiveTunnels": (en: "No active tunnels", zh: "没有活跃的隧道"),
        "tunnel.cloudflaredInstalled": (en: "cloudflared installed", zh: "cloudflared 已安装"),
        "tunnel.quickTunnels": (en: "Quick Tunnels", zh: "快速隧道"),
        "tunnel.portLabel": (en: "Port %d", zh: "端口 %d"),
        "tunnel.startingTunnel": (en: "Starting tunnel…", zh: "正在启动隧道…"),
        "tunnel.showLogs": (en: "Show Logs", zh: "显示日志"),
        "tunnel.hideLogs": (en: "Hide Logs", zh: "隐藏日志"),

        // Named tunnels section (NamedTunnelsSection)
        "tunnel.notLoggedInTitle": (en: "Not logged in to Cloudflare", zh: "未登录 Cloudflare"),
        "tunnel.notLoggedInDetail": (en: "Run `cloudflared tunnel login` in Terminal to list account tunnels. Local tunnel credentials and config are still supported when present.", zh: "在终端运行 `cloudflared tunnel login` 以列出账户隧道。检测到本地隧道凭证和配置时仍会支持。"),
        "tunnel.noTunnelsTitle": (en: "No tunnels yet", zh: "还没有隧道"),
        "tunnel.noTunnelsDetail": (en: "Create one with `cloudflared tunnel create <name>` or via the Cloudflare dashboard.", zh: "使用 `cloudflared tunnel create <name>` 或通过 Cloudflare 控制台创建一个。"),
        "tunnel.sectionRunning": (en: "Running", zh: "运行中"),
        "tunnel.sectionAvailable": (en: "Available", zh: "可用"),
        "tunnel.sectionManagedElsewhere": (en: "Managed Elsewhere", zh: "由外部管理"),
        "tunnel.loginWarningTitle": (en: "Cloudflare account login not found", zh: "未找到 Cloudflare 账户登录"),
        "tunnel.loginWarningDetail": (en: "Showing locally configured tunnels only. Run `cloudflared tunnel login` to discover all account tunnels.", zh: "仅显示本地配置的隧道。运行 `cloudflared tunnel login` 以发现所有账户隧道。"),
        "tunnel.discovering": (en: "Discovering tunnels…", zh: "正在发现隧道…"),
        "tunnel.connCount": (en: "%d conn", zh: "%d 连接"),
        "tunnel.noIngressConfigured": (en: "No ingress configured", zh: "未配置 Ingress"),
        "tunnel.run": (en: "Run", zh: "运行"),
        "tunnel.runThisHelp": (en: "Run this tunnel", zh: "运行此隧道"),
        "tunnel.stopThisHelp": (en: "Stop this tunnel", zh: "停止此隧道"),
        "tunnel.runAnyway": (en: "Run Anyway", zh: "仍然运行"),
        "tunnel.copyTunnelID": (en: "Copy Tunnel ID", zh: "复制隧道 ID"),

        // Named tunnel detail pane (NamedTunnelDetailView)
        "tunnel.connectionsBadge": (en: "%d connections", zh: "%d 个连接"),
        "tunnel.localConfig": (en: "Local config", zh: "本地配置"),
        "tunnel.runAnywayHelp": (en: "Add this Mac as another connector for the tunnel", zh: "将此 Mac 添加为该隧道的另一个连接器"),
        "tunnel.metaTunnelID": (en: "Tunnel ID", zh: "隧道 ID"),
        "tunnel.metaIngressSource": (en: "Ingress Source", zh: "Ingress 来源"),
        "tunnel.metaCreated": (en: "Created", zh: "创建于"),
        "tunnel.metaMetrics": (en: "Metrics", zh: "指标"),
        "tunnel.metaStarted": (en: "Started", zh: "启动于"),
        "tunnel.metaCredentials": (en: "Credentials", zh: "凭证"),
        "tunnel.ingressSourceDashboard": (en: "Cloudflare dashboard", zh: "Cloudflare 控制台"),
        "tunnel.ingressRules": (en: "Ingress Rules", zh: "Ingress 规则"),
        "tunnel.edgeConnections": (en: "Edge Connections", zh: "边缘连接"),
        "tunnel.managedByAnotherOriginTitle": (en: "This tunnel is managed by another origin", zh: "此隧道由另一个源管理"),
        "tunnel.managedByAnotherOriginDetail": (en: "It has active edge connections from other machines and no local ingress configuration. Running it here adds this Mac as another connector, which can split traffic between origins. Use Run Anyway only if that is intentional.", zh: "它有来自其他机器的活跃边缘连接，且没有本地 ingress 配置。在此运行会将此 Mac 添加为另一个连接器，可能会在多个源之间分流。仅在确实需要时才使用「仍然运行」。"),
        "tunnel.logs": (en: "Logs", zh: "日志"),

        // Tunnel logs (TunnelLogView)
        "tunnel.searchLogs": (en: "Search logs…", zh: "搜索日志…"),
        "tunnel.logRequests": (en: "Requests", zh: "请求"),
        "tunnel.logErrors": (en: "Errors", zh: "错误"),
        "tunnel.logWarnings": (en: "Warnings", zh: "警告"),
        "tunnel.logEntryCount": (en: "%d entries", zh: "%d 条"),
        "tunnel.clearLogsHelp": (en: "Clear logs", zh: "清除日志"),
        "tunnel.noLogs": (en: "No Logs", zh: "暂无日志"),
        "tunnel.logsWillAppear": (en: "Logs will appear here as requests come in", zh: "有请求时日志会显示在这里"),
        "tunnel.noLogsMatchFilter": (en: "No logs match the current filter", zh: "没有日志符合当前筛选"),
        "tunnel.waitingForOutput": (en: "Waiting for output…", zh: "正在等待输出…"),
        "tunnel.noLogsYet": (en: "No logs yet. Run the tunnel to see live output.", zh: "还没有日志。运行隧道以查看实时输出。"),

        // Ingress rule row (IngressRuleDetailRow)
        "tunnel.fallbackRule": (en: "(fallback)", zh: "(默认回退)"),
    ]
}
