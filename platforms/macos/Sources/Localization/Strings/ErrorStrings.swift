import Foundation

/// User-facing error text: `PortKillerError`, `KubectlError`, port-forward and
/// tunnel failures. Format specifiers (`%@`, `%d`) mirror the original
/// interpolations so `L(key, args...)` reproduces them exactly.
enum ErrorStrings {
    static let entries: [String: (en: String, zh: String)] = [
        // PortKillerError.errorDescription
        "error.scanFailed": (en: "Failed to scan ports: %@", zh: "扫描端口失败：%@"),
        "error.killFailed": (en: "Failed to kill process %d: %@", zh: "结束进程 %d 失败：%@"),
        "error.permissionDenied": (
            en: "Permission denied. PortKiller requires accessibility permissions to manage processes.",
            zh: "权限被拒绝。PortKiller 需要辅助功能权限才能管理进程。"
        ),
        "error.networkError": (en: "Network error: %@", zh: "网络错误：%@"),

        // PortKillerError.failureReason
        "error.scanFailed.reason": (
            en: "The port scanning operation could not complete successfully.",
            zh: "端口扫描操作未能成功完成。"
        ),
        "error.killFailed.reason": (
            en: "The process termination request was denied or failed.",
            zh: "进程终止请求被拒绝或失败。"
        ),
        "error.permissionDenied.reason": (
            en: "PortKiller does not have the necessary system permissions.",
            zh: "PortKiller 没有所需的系统权限。"
        ),
        "error.networkError.reason": (
            en: "A network or system-level error occurred.",
            zh: "发生了网络或系统级错误。"
        ),

        // PortKillerError.recoverySuggestion
        "error.scanFailed.recovery": (
            en: "Try refreshing the port list or restarting PortKiller.",
            zh: "尝试刷新端口列表或重启 PortKiller。"
        ),
        "error.killFailed.recovery": (
            en: "The process may require elevated privileges. Try running 'sudo kill -9 %d' in Terminal.",
            zh: "该进程可能需要更高权限。请尝试在终端中运行 “sudo kill -9 %d”。"
        ),
        "error.permissionDenied.recovery": (
            en: "Go to System Settings > Privacy & Security > Accessibility and enable PortKiller.",
            zh: "前往“系统设置 > 隐私与安全性 > 辅助功能”并启用 PortKiller。"
        ),
        "error.networkError.recovery": (
            en: "Check your network connection and try again.",
            zh: "请检查网络连接后重试。"
        ),

        // KubectlError
        "error.kubectl.notFound": (
            en: "kubectl not found. Please install kubernetes-cli.",
            zh: "未找到 kubectl。请安装 kubernetes-cli。"
        ),
        "error.kubectl.executionFailed": (en: "kubectl failed: %@", zh: "kubectl 执行失败：%@"),
        "error.kubectl.parsingFailed": (en: "Failed to parse response: %@", zh: "解析响应失败：%@"),
        "error.kubectl.clusterNotConnected": (
            en: "Cannot connect to Kubernetes cluster. Check your kubectl configuration.",
            zh: "无法连接到 Kubernetes 集群。请检查你的 kubectl 配置。"
        ),
    ]
}
