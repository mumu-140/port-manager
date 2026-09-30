import Foundation

/// First-launch onboarding flow.
enum OnboardingStrings {
    static let entries: [String: (en: String, zh: String)] = [
        "onboarding.welcome.title": (en: "Welcome to PortKiller", zh: "欢迎使用 PortKiller"),
        "onboarding.welcome.subtitle": (en: "Find and kill processes on any port.\nManage your development servers with ease.", zh: "在任意端口上查找并结束进程。\n轻松管理你的开发服务器。"),
        "onboarding.features.title": (en: "What you can do", zh: "你可以做什么"),
        "onboarding.setup.title": (en: "Quick Setup", zh: "快速设置"),
        "onboarding.setup.launchAtLogin": (en: "Launch at Login", zh: "登录时启动"),
        "onboarding.setup.launchAtLoginDetail": (en: "Start PortKiller when you log in", zh: "登录时启动 PortKiller"),
        "onboarding.setup.notificationsDetail": (en: "Get notified when watched ports change state", zh: "当监听的端口状态变化时收到通知"),
        "onboarding.setup.globalShortcut": (en: "Global Shortcut", zh: "全局快捷键"),
        "onboarding.setup.globalShortcutDetail": (en: "Open PortKiller from anywhere", zh: "随时随地打开 PortKiller"),
        "onboarding.openSettings": (en: "Open Settings", zh: "打开设置"),
        "onboarding.ready.title": (en: "You're All Set!", zh: "一切就绪！"),
        "onboarding.ready.detail": (en: "PortKiller is ready to use.\nLook for the icon in your menu bar.", zh: "PortKiller 已就绪。\n请在菜单栏中查找图标。"),
        "onboarding.back": (en: "Back", zh: "上一步"),
        "onboarding.skip": (en: "Skip", zh: "跳过"),
        "onboarding.next": (en: "Next", zh: "下一步"),
        "onboarding.getStarted": (en: "Get Started", zh: "开始使用"),
        "onboarding.features.scanning.title": (en: "Port Scanning", zh: "端口扫描"),
        "onboarding.features.scanning.detail": (en: "See all listening ports in one place", zh: "在一个地方查看所有监听端口"),
        "onboarding.features.quickKill.title": (en: "Quick Kill", zh: "快速结束"),
        "onboarding.features.quickKill.detail": (en: "Terminate processes with one click", zh: "一键结束进程"),
        "onboarding.features.favorites.title": (en: "Favorites", zh: "收藏"),
        "onboarding.features.favorites.detail": (en: "Pin frequently used ports for quick access", zh: "固定常用端口以便快速访问"),
        "onboarding.features.watched.title": (en: "Watched Ports", zh: "监听端口"),
        "onboarding.features.watched.detail": (en: "Get notifications when ports become active", zh: "端口变为活跃时收到通知"),
        "onboarding.features.tunnels.title": (en: "Cloudflare Tunnels", zh: "Cloudflare 隧道"),
        "onboarding.features.tunnels.detail": (en: "Share local ports publicly", zh: "公开分享本地端口"),
        "onboarding.ready.tipMenuBar": (en: "Click the menu bar icon\nfor quick access", zh: "点击菜单栏图标\n即可快速访问"),
        "onboarding.ready.tipSettings": (en: "Visit Settings to\ncustomize further", zh: "前往设置\n进行更多自定义"),
    ]
}
