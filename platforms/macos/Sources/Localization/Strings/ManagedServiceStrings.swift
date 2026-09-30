import Foundation

/// Local Services (managed service profiles) UI strings.
enum ManagedServiceStrings {
    static let entries: [String: (en: String, zh: String)] = [
        // MARK: Validation and lifecycle errors
        "service.error.emptyName": (en: "Service name is required.", zh: "服务名称不能为空。"),
        "service.error.duplicateName": (en: "A service named “%@” already exists.", zh: "已存在名为“%@”的服务。"),
        "service.error.emptyHost": (en: "Host is required.", zh: "主机不能为空。"),
        "service.error.portRange": (en: "Port must be between 1 and 65535 (got %ld).", zh: "端口必须在 1 到 65535 之间（当前为 %ld）。"),
        "service.error.duplicatePort": (en: "Another service already uses port %ld.", zh: "另一个服务已使用端口 %ld。"),
        "service.error.missingDirectory": (en: "Working directory does not exist: %@", zh: "工作目录不存在：%@"),
        "service.error.emptyCommand": (en: "Start command is required.", zh: "启动命令不能为空。"),
        "service.error.unsupportedPlaceholder": (en: "Unsupported placeholder %@. Only {port} is allowed.", zh: "不支持的占位符 %@。仅允许使用 {port}。"),
        "service.error.launchFailed": (en: "Failed to launch the service command: %@", zh: "无法启动服务命令：%@"),
        "service.error.exitedBeforeReady": (en: "The process exited before port %ld became ready.", zh: "进程在端口 %ld 就绪前退出。"),
        "service.error.exitedUnexpectedly": (en: "The process exited unexpectedly (exit code %ld).", zh: "进程意外退出（退出码 %ld）。"),
        "service.error.startupTimeout": (en: "Port %ld did not become ready within %ld seconds.", zh: "端口 %ld 未在 %ld 秒内就绪。"),
        "service.error.stopFailed": (en: "Failed to stop the service.", zh: "无法停止服务。"),
        "service.error.portStillOccupied": (en: "Port %ld is still occupied after stopping.", zh: "停止后端口 %ld 仍被占用。"),
        "service.error.conflictStillOccupied": (en: "Port %ld is still occupied; the service was not started.", zh: "端口 %ld 仍被占用，服务未启动。"),
        "service.error.browserOpenFailed": (en: "Could not open %@ in the browser.", zh: "无法在浏览器中打开 %@。"),
        "service.error.tunnel": (en: "Quick Tunnel operation failed.", zh: "快速隧道操作失败。"),
        "service.error.invalidConfiguration": (en: "The service configuration is invalid.", zh: "服务配置无效。"),
        "service.error.notRunning": (en: "The service is not running.", zh: "服务未运行。"),
        "service.error.running": (en: "Stop the service first.", zh: "请先停止服务。"),

        // MARK: Status
        "service.status.stopped": (en: "Stopped", zh: "已停止"),
        "service.status.starting": (en: "Starting", zh: "启动中"),
        "service.status.running": (en: "Running", zh: "运行中"),
        "service.status.stopping": (en: "Stopping", zh: "停止中"),
        "service.status.conflict": (en: "Conflict", zh: "冲突"),
        "service.status.failed": (en: "Failed", zh: "失败"),

        // MARK: Sidebar and list
        "service.title": (en: "Local Services", zh: "本地服务"),
        "service.add": (en: "Add Service", zh: "添加服务"),
        "service.addHelp": (en: "Add a local service", zh: "添加本地服务"),
        "service.searchPlaceholder": (en: "Search services...", zh: "搜索服务…"),
        "service.empty.title": (en: "No Services Yet", zh: "暂无服务"),
        "service.empty.detail": (en: "Add a local service to start and manage it from Port Manager.", zh: "添加本地服务，即可在 Port Manager 中启动和管理。"),
        "service.noSelection.title": (en: "No Service Selected", zh: "未选择服务"),
        "service.noSelection.detail": (en: "Select a service from the list to view details.", zh: "从列表中选择一个服务以查看详情。"),
        "service.count.total": (en: "%ld services", zh: "%ld 个服务"),
        "service.count.running": (en: "%ld running", zh: "%ld 个运行中"),
        "service.count.conflict": (en: "%ld conflicts", zh: "%ld 个冲突"),
        "service.badge.conflict": (en: "Conflict", zh: "冲突"),
        "service.badge.error": (en: "Error", zh: "错误"),

        // MARK: Actions
        "service.start": (en: "Start", zh: "启动"),
        "service.stop": (en: "Stop", zh: "停止"),
        "service.restart": (en: "Restart", zh: "重启"),
        "service.edit": (en: "Edit", zh: "编辑"),
        "service.delete": (en: "Delete", zh: "删除"),
        "service.open": (en: "Open", zh: "打开"),
        "service.cancel": (en: "Cancel", zh: "取消"),
        "service.save": (en: "Save", zh: "保存"),
        "service.action.starting": (en: "Starting...", zh: "启动中…"),
        "service.action.stopping": (en: "Stopping...", zh: "停止中…"),

        // MARK: Fields and editor
        "service.field.name": (en: "Name", zh: "名称"),
        "service.field.port": (en: "Port", zh: "端口"),
        "service.field.host": (en: "Host", zh: "主机"),
        "service.field.workingDirectory": (en: "Working Directory", zh: "工作目录"),
        "service.field.startCommand": (en: "Start Command", zh: "启动命令"),
        "service.field.chooseDirectory": (en: "Choose...", zh: "选择…"),
        "service.help.portPlaceholder": (en: "Use {port} to follow future port edits.", zh: "使用 {port} 以跟随后续端口修改。"),
        "service.help.foreground": (en: "Run the server in the foreground; daemonized commands are not supported.", zh: "请在前台运行服务，不支持守护进程化的命令。"),
        "service.help.secrets": (en: "Avoid embedding passwords or tokens; prefer environment variables.", zh: "请勿直接写入密码或令牌，建议使用环境变量。"),
        "service.editor.addTitle": (en: "Add Local Service", zh: "添加本地服务"),
        "service.editor.editTitle": (en: "Edit Local Service", zh: "编辑本地服务"),
        "service.editor.invalid": (en: "Fix the highlighted fields before saving.", zh: "请先修正错误后再保存。"),
        "service.editor.stopBeforeEdit": (en: "Stop the service before editing its configuration.", zh: "编辑配置前请先停止服务。"),
        "service.editor.validationFailed": (en: "The service configuration is invalid.", zh: "服务配置无效。"),

        // MARK: Detail
        "service.detail.workingDirectory": (en: "Working Directory", zh: "工作目录"),
        "service.detail.command": (en: "Start Command", zh: "启动命令"),
        "service.detail.rootPID": (en: "Root PID", zh: "主进程 PID"),
        "service.detail.listenerPIDs": (en: "Listener PIDs", zh: "监听进程 PID"),
        "service.detail.lastError": (en: "Last Error", zh: "最近错误"),
        "service.detail.output": (en: "Recent Output", zh: "最近输出"),
        "service.detail.startedAt": (en: "Started", zh: "启动时间"),
        "service.detail.exitCode": (en: "Exit Code", zh: "退出码"),
        "service.detail.tunnel": (en: "Quick Tunnel", zh: "快速隧道"),
        "service.detail.noOutput": (en: "No output captured yet.", zh: "暂无输出。"),
        "service.log.copy": (en: "Copy", zh: "复制"),
        "service.log.clear": (en: "Clear", zh: "清空"),

        // MARK: Conflict
        "service.conflict.title": (en: "Port Conflict", zh: "端口冲突"),
        "service.conflict.message": (en: "Port %ld is already in use by another process.", zh: "端口 %ld 已被其他进程占用。"),
        "service.conflict.occupant": (en: "%@ (PID %ld) · %@", zh: "%@（PID %ld）· %@"),
        "service.conflict.pid": (en: "PID", zh: "PID"),
        "service.conflict.process": (en: "Process", zh: "进程"),
        "service.conflict.command": (en: "Command", zh: "命令"),
        "service.conflict.user": (en: "User", zh: "用户"),
        "service.conflict.address": (en: "Address", zh: "地址"),
        "service.conflict.killAndStart": (en: "Kill Occupying Process(es) & Start", zh: "结束占用进程并启动"),
        "service.conflict.cancel": (en: "Cancel", zh: "取消"),
        "service.conflict.startHelp": (en: "No process is killed without your confirmation.", zh: "未经确认不会结束任何进程。"),

        // MARK: Delete
        "service.delete.title": (en: "Delete Service", zh: "删除服务"),
        "service.delete.message": (en: "Delete “%@”?", zh: "删除“%@”？"),
        "service.delete.runningMessage": (en: "“%@” is running and will be stopped before deletion.", zh: "“%@”正在运行，删除前会先停止。"),
        "service.delete.confirm": (en: "Delete", zh: "删除"),

        // MARK: Quick Tunnel
        "service.tunnel.start": (en: "Start Tunnel", zh: "启动隧道"),
        "service.tunnel.starting": (en: "Starting tunnel...", zh: "正在启动隧道…"),
        "service.tunnel.publicURL": (en: "Public URL", zh: "公网地址"),
        "service.tunnel.copy": (en: "Copy", zh: "复制"),
        "service.tunnel.open": (en: "Open", zh: "打开"),
        "service.tunnel.stop": (en: "Stop Tunnel", zh: "停止隧道"),
        "service.tunnel.retry": (en: "Retry", zh: "重试"),
        "service.tunnel.unavailable": (en: "cloudflared is not installed.", zh: "未安装 cloudflared。"),
        "service.tunnel.stopped": (en: "No tunnel running.", zh: "隧道未运行。"),
    ]
}
