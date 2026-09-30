import Foundation

/// Settings window: section headers, toggles, descriptions, and the language
/// selector (follow-system / 简体中文 / English).
enum SettingsStrings {
    static let entries: [String: (en: String, zh: String)] = [
        // Window / section headers
        "settings.title": (en: "Settings", zh: "设置"),
        "settings.section.general": (en: "General", zh: "通用"),
        "settings.section.portForwarding": (en: "Port Forwarding", zh: "端口转发"),
        "settings.section.autoKill": (en: "Auto-Kill Rules", zh: "自动结束规则"),
        "settings.section.notifications": (en: "Notifications", zh: "通知"),
        "settings.section.cloudflare": (en: "Cloudflare Tunnels", zh: "Cloudflare Tunnel"),
        "settings.section.shortcuts": (en: "Keyboard Shortcuts", zh: "键盘快捷键"),
        "settings.section.permissions": (en: "Permissions", zh: "权限"),
        "settings.section.updates": (en: "Software Updates", zh: "软件更新"),
        "settings.section.sponsors": (en: "Community", zh: "社区"),
        "settings.section.about": (en: "About", zh: "关于"),

        // Language selector (goal 5)
        "settings.language": (en: "Language", zh: "语言"),
        "settings.language.subtitle": (
            en: "Choose the language for PortKiller's interface",
            zh: "选择 PortKiller 界面使用的语言"
        ),
        "settings.language.system": (en: "Follow System", zh: "跟随系统"),
        "settings.language.english": (en: "English", zh: "English"),
        "settings.language.simplifiedChinese": (en: "简体中文", zh: "简体中文"),

        // Port Forwarder window tabs
        "portForwarder.title": (en: "Port Forwarder", zh: "端口转发"),
        "portForwarder.tab.connections": (en: "Connections", zh: "连接"),
        "portForwarder.tab.browse": (en: "Browse", zh: "浏览"),
        "portForwarder.tab.settings": (en: "Settings", zh: "设置"),

        // General
        "settings.general.launchAtLogin": (en: "Launch at Login", zh: "登录时启动"),
        "settings.general.launchAtLogin.subtitle": (
            en: "Start PortKiller when you log in",
            zh: "登录时自动启动 PortKiller"
        ),
        "settings.general.hideSystemProcesses": (en: "Hide System processes", zh: "隐藏系统进程"),
        "settings.general.hideSystemProcesses.subtitle": (
            en: "Hide macOS processes from the process list",
            zh: "在进程列表中隐藏 macOS 系统进程"
        ),
        "settings.general.skipKillConfirmation": (en: "Skip kill confirmation", zh: "跳过结束确认"),
        "settings.general.skipKillConfirmation.subtitle": (
            en: "Kill processes immediately without confirmation prompt",
            zh: "立即结束进程，不显示确认提示"
        ),

        // Auto-Kill Rules
        "settings.autoKill.header": (
            en: "Automatically kill processes after a timeout",
            zh: "在超时后自动结束进程"
        ),
        "settings.autoKill.subtitle": (
            en: "Rules are checked on each port scan cycle",
            zh: "每次端口扫描周期都会检查规则"
        ),
        "settings.autoKill.noRules": (en: "No rules configured", zh: "尚未配置规则"),
        "settings.autoKill.addRule": (en: "Add Rule", zh: "添加规则"),
        "settings.autoKill.newRuleName": (en: "New Rule", zh: "新建规则"),
        "settings.autoKill.unnamedRule": (en: "Unnamed Rule", zh: "未命名规则"),
        "settings.autoKill.rule.process": (en: "Process: %@", zh: "进程：%@"),
        "settings.autoKill.rule.port": (en: "Port: %d", zh: "端口：%d"),
        "settings.autoKill.rule.timeout": (en: "Timeout: %d min", zh: "超时：%d 分钟"),
        "settings.autoKill.editTitle": (en: "Edit Auto-Kill Rule", zh: "编辑自动结束规则"),
        "settings.autoKill.ruleName": (en: "Rule Name", zh: "规则名称"),
        "settings.autoKill.matchCriteria": (en: "Match Criteria", zh: "匹配条件"),
        "settings.autoKill.processPattern": (
            en: "Process Pattern (e.g. node*, python*)",
            zh: "进程匹配模式（例如 node*、python*）"
        ),
        "settings.autoKill.portField": (en: "Port (0 = any)", zh: "端口（0 = 任意）"),
        "settings.autoKill.behavior": (en: "Behavior", zh: "行为"),
        "settings.autoKill.timeoutStepper": (en: "Timeout: %d minutes", zh: "超时：%d 分钟"),
        "settings.autoKill.notifyBeforeKill": (en: "Notify before killing", zh: "结束前通知"),
        "settings.autoKill.enabled": (en: "Enabled", zh: "已启用"),

        // Notifications
        "settings.notifications.title": (en: "Port Notifications", zh: "端口通知"),
        "settings.notifications.header": (
            en: "Notify on new ports by process type",
            zh: "按进程类型通知新端口"
        ),
        "settings.notifications.subtitle": (
            en: "Get notified when a port opens for selected process types",
            zh: "当所选进程类型打开端口时收到通知"
        ),

        // Port Forwarding
        "settings.portForwarding.autoStart": (en: "Auto-start connections", zh: "自动启动连接"),
        "settings.portForwarding.autoStart.subtitle": (
            en: "Start all connections when app launches",
            zh: "应用启动时启动所有连接"
        ),
        "settings.portForwarding.optional": (en: "(optional)", zh: "（可选）"),
        "settings.portForwarding.installed": (en: "Installed", zh: "已安装"),
        "settings.portForwarding.notFound": (en: "Not found", zh: "未找到"),
        "settings.portForwarding.install": (en: "Install", zh: "安装"),
        "settings.portForwarding.customPath": (
            en: "Custom path (leave empty for auto)",
            zh: "自定义路径（留空则自动检测）"
        ),
        "settings.portForwarding.using": (en: "Using:", zh: "正在使用："),
        "settings.portForwarding.custom": (en: "(custom)", zh: "（自定义）"),
        "settings.portForwarding.auto": (en: "(auto)", zh: "（自动）"),
        "settings.portForwarding.autoDetected": (en: "Auto-detected:", zh: "自动检测到："),

        // Cloudflare Tunnels (settings section)
        "settings.cloudflared.protocol": (en: "Tunnel protocol", zh: "隧道协议"),
        "settings.cloudflared.protocol.subtitle": (
            en: "Choose how cloudflared connects to Cloudflare (applies to new tunnels)",
            zh: "选择 cloudflared 连接 Cloudflare 的方式（对新建隧道生效）"
        ),
        "settings.cloudflared.path": (en: "cloudflared path", zh: "cloudflared 路径"),

        // Software Updates
        "settings.updates.appVersion": (en: "PortKiller %@", zh: "PortKiller %@"),
        "settings.updates.lastChecked": (en: "Last checked %@", zh: "上次检查：%@"),
        "settings.updates.neverChecked": (en: "Never checked for updates", zh: "尚未检查过更新"),
        "settings.updates.checkNow": (en: "Check Now", zh: "立即检查"),
        "settings.updates.checkAutomatically": (en: "Check automatically", zh: "自动检查"),
        "settings.updates.checkAutomatically.subtitle": (
            en: "Look for updates in the background",
            zh: "在后台检查更新"
        ),
        "settings.updates.downloadAutomatically": (en: "Download automatically", zh: "自动下载"),
        "settings.updates.downloadAutomatically.subtitle": (
            en: "Download updates when available",
            zh: "有可用更新时自动下载"
        ),

        // Sponsors
        "settings.sponsors.showWindow": (en: "Show Community Window", zh: "显示社区窗口"),
        "settings.sponsors.showWindow.subtitle": (
            en: "How often to display the community window",
            zh: "显示社区窗口的频率"
        ),
        "settings.sponsors.view": (en: "View Community", zh: "查看社区"),
        "settings.sponsors.view.subtitle": (en: "See project supporters and contributors", zh: "查看项目支持者和贡献者"),
        "settings.sponsors.showWindowButton": (en: "Show Window", zh: "显示窗口"),

        // About
        "settings.about.developer": (en: "Maintainer", zh: "维护者"),
        "settings.about.github.subtitle": (en: "Independent project repository", zh: "独立维护的项目仓库"),
        "settings.about.support": (en: "Support Project", zh: "支持项目"),
        "settings.about.support.subtitle": (en: "Ways to support development", zh: "查看支持项目的方式"),
        "settings.about.upstream": (en: "Fork Origin", zh: "Fork 来源"),
        "settings.about.upstream.subtitle": (en: "Original upstream repository", zh: "原始上游仓库"),
        "settings.about.reportIssue": (en: "Report Issue", zh: "反馈问题"),
        "settings.about.reportIssue.subtitle": (en: "Found a bug?", zh: "发现了 Bug？"),
        "settings.about.showWelcome": (en: "Show Welcome Screen", zh: "显示欢迎界面"),
        "settings.about.showWelcome.subtitle": (
            en: "Replay the onboarding wizard",
            zh: "重新播放引导向导"
        ),

        // Keyboard Shortcuts
        "settings.shortcuts.toggleMainWindow": (en: "Toggle Main Window", zh: "切换主窗口"),
        "settings.shortcuts.toggleMainWindow.subtitle": (
            en: "Show or hide the PortKiller window",
            zh: "显示或隐藏 PortKiller 窗口"
        ),
        "settings.shortcuts.resetHelp": (en: "Reset to default (⌘⇧P)", zh: "重置为默认值（⌘⇧P）"),
        "settings.shortcuts.accessibilityRequired": (en: "Accessibility Required", zh: "需要辅助功能权限"),
        "settings.shortcuts.accessibilityRequired.subtitle": (
            en: "Global shortcuts need Accessibility permission",
            zh: "全局快捷键需要辅助功能权限"
        ),

        // Permissions
        "settings.permissions.accessibility": (en: "Accessibility", zh: "辅助功能"),
        "settings.permissions.accessibility.granted": (en: "Permission granted", zh: "已授予权限"),
        "settings.permissions.accessibility.required": (
            en: "Required for global shortcuts",
            zh: "全局快捷键需要此权限"
        ),
        "settings.permissions.grantedBadge": (en: "Granted", zh: "已授予"),
        "settings.permissions.grantAccess": (en: "Grant Access", zh: "授予权限"),
        "settings.permissions.notifications": (en: "Notifications", zh: "通知"),
        "settings.permissions.openSettings": (en: "Open Settings", zh: "打开设置"),
        "settings.permissions.notif.authorized": (
            en: "Alerts enabled for port watch",
            zh: "已为端口监视启用提醒"
        ),
        "settings.permissions.notif.denied": (
            en: "Notifications disabled in System Settings",
            zh: "已在系统设置中停用通知"
        ),
        "settings.permissions.notif.notDetermined": (
            en: "Required for port watch alerts",
            zh: "端口监视提醒需要此权限"
        ),
        "settings.permissions.notif.provisional": (
            en: "Provisional notifications enabled",
            zh: "已启用临时通知"
        ),
        "settings.permissions.notif.ephemeral": (
            en: "Temporary notifications enabled",
            zh: "已启用临时通知"
        ),
        "settings.permissions.notif.unknown": (en: "Unknown status", zh: "未知状态"),
    ]
}
