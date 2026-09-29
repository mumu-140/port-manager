import Foundation

/// Menu bar extra and its menus: status summary, quick actions, and the
/// tray/menu labels.
enum MenuBarStrings {
    static let entries: [String: (en: String, zh: String)] = [
        // Header / search
        "menubar.searchPlaceholder": (en: "Search…", zh: "搜索…"),

        // Quick actions
        "menubar.listView": (en: "List View", zh: "列表视图"),
        "menubar.treeView": (en: "Tree View", zh: "树状视图"),
        "menubar.killAll": (en: "Kill All", zh: "结束全部"),
        "menubar.kill": (en: "Kill", zh: "结束"),
        "menubar.killAllConfirm": (en: "Kill all %d processes?", zh: "结束全部 %d 个进程？"),
        "menubar.openApp": (en: "Open PortKiller", zh: "打开 PortKiller"),
        "menubar.settings": (en: "Settings…", zh: "设置…"),
        "menubar.quit": (en: "Quit PortKiller", zh: "退出 PortKiller"),

        // Section headers
        "menubar.section.localPorts": (en: "Local Ports", zh: "本地端口"),
        "menubar.section.k8sPortForward": (en: "K8s Port Forward", zh: "K8s 端口转发"),
        "menubar.section.quickTunnels": (en: "Quick Tunnels", zh: "快速隧道"),
        "menubar.section.myTunnels": (en: "My Tunnels", zh: "我的隧道"),

        // Empty state / process rows
        "menubar.noOpenPorts": (en: "No open ports", zh: "没有打开的端口"),
        "menubar.pid": (en: "PID %d", zh: "PID %d"),
        "menubar.pidCount": (en: "%d PIDs", zh: "%d 个 PID"),
    ]
}
