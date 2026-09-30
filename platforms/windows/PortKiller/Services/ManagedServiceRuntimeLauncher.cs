using System.Collections;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;

namespace PortKiller.Services;

/// <summary>
/// Native launcher that gives a managed service file-backed stdout/stderr.
///
/// <see cref="System.Diagnostics.ProcessStartInfo"/> can only redirect output
/// to a parent-owned pipe, which a child that outlives Port Manager would break
/// on. The Windows equivalent of the macOS file-handle redirection is
/// <c>CreateProcess</c> with inherited file handles. A job object is used so a
/// stop terminates the whole owned tree.
/// </summary>
internal static class ManagedServiceRuntimeLauncher
{
    private const uint CREATE_NO_WINDOW = 0x08000000;
    private const uint CREATE_UNICODE_ENVIRONMENT = 0x00000400;
    private const uint STARTF_USESTDHANDLES = 0x00000100;
    private const uint GENERIC_READ = 0x80000000;
    private const uint GENERIC_WRITE = 0x40000000;
    private const uint FILE_SHARE_READ = 0x00000001;
    private const uint FILE_SHARE_WRITE = 0x00000002;
    private const uint FILE_SHARE_DELETE = 0x00000004;
    private const uint OPEN_EXISTING = 3;
    private const uint CREATE_ALWAYS = 2;
    private const uint FILE_ATTRIBUTE_NORMAL = 0x00000080;
    private const uint STILL_ACTIVE = 259;

    [StructLayout(LayoutKind.Sequential)]
    private struct SECURITY_ATTRIBUTES
    {
        public int nLength;
        public IntPtr lpSecurityDescriptor;
        public int bInheritHandle;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct STARTUPINFO
    {
        public int cb;
        public IntPtr lpReserved;
        public IntPtr lpDesktop;
        public IntPtr lpTitle;
        public int dwX;
        public int dwY;
        public int dwXSize;
        public int dwYSize;
        public int dwXCountChars;
        public int dwYCountChars;
        public int dwFillAttribute;
        public int dwFlags;
        public short wShowWindow;
        public short cbReserved2;
        public IntPtr lpReserved2;
        public IntPtr hStdInput;
        public IntPtr hStdOutput;
        public IntPtr hStdError;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct PROCESS_INFORMATION
    {
        public IntPtr hProcess;
        public IntPtr hThread;
        public int dwProcessId;
        public int dwThreadId;
    }

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern bool CreateProcessW(
        string? lpApplicationName,
        StringBuilder lpCommandLine,
        IntPtr lpProcessAttributes,
        IntPtr lpThreadAttributes,
        bool bInheritHandles,
        uint dwCreationFlags,
        IntPtr lpEnvironment,
        string? lpCurrentDirectory,
        ref STARTUPINFO lpStartupInfo,
        out PROCESS_INFORMATION lpProcessInformation);

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern IntPtr CreateFileW(
        string lpFileName,
        uint dwDesiredAccess,
        uint dwShareMode,
        ref SECURITY_ATTRIBUTES lpSecurityAttributes,
        uint dwCreationDisposition,
        uint dwFlagsAndAttributes,
        IntPtr hTemplateFile);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool CloseHandle(IntPtr hObject);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr CreateJobObjectW(IntPtr lpJobAttributes, string? lpName);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool AssignProcessToJobObject(IntPtr hJob, IntPtr hProcess);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool TerminateJobObject(IntPtr hJob, uint uExitCode);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool TerminateProcess(IntPtr hProcess, uint uExitCode);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GetExitCodeProcess(IntPtr hProcess, out uint lpExitCode);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern uint WaitForSingleObject(IntPtr hHandle, uint dwMilliseconds);

    public static int Launch(
        string command,
        string? workingDirectory,
        Guid serviceId,
        string stdoutPath,
        string stderrPath,
        out IntPtr processHandle,
        out IntPtr jobHandle)
    {
        processHandle = IntPtr.Zero;
        jobHandle = IntPtr.Zero;

        var attributes = new SECURITY_ATTRIBUTES
        {
            nLength = Marshal.SizeOf<SECURITY_ATTRIBUTES>(),
            lpSecurityDescriptor = IntPtr.Zero,
            bInheritHandle = 1,
        };

        var stdoutHandle = CreateFileW(stdoutPath, GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
            ref attributes, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, IntPtr.Zero);
        var stderrHandle = CreateFileW(stderrPath, GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
            ref attributes, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, IntPtr.Zero);
        var stdinHandle = CreateFileW("NUL", GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE,
            ref attributes, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, IntPtr.Zero);

        if (stdoutHandle == IntPtr.Zero || stdoutHandle == new IntPtr(-1) ||
            stderrHandle == IntPtr.Zero || stderrHandle == new IntPtr(-1))
        {
            CloseQuietly(stdinHandle);
            CloseQuietly(stdoutHandle);
            CloseQuietly(stderrHandle);
            throw new Win32Exception(Marshal.GetLastWin32Error(), "Unable to open managed-service runtime log files.");
        }

        var environment = BuildEnvironmentBlock(serviceId);
        var startup = new STARTUPINFO
        {
            cb = Marshal.SizeOf<STARTUPINFO>(),
            dwFlags = STARTF_USESTDHANDLES,
            hStdInput = stdinHandle,
            hStdOutput = stdoutHandle,
            hStdError = stderrHandle,
        };
        var commandLine = new StringBuilder();
        commandLine.Append('"').Append(ResolveShell()).Append('"');
        commandLine.Append(" /d /s /c \"").Append(command).Append('"');

        try
        {
            if (!CreateProcessW(null, commandLine, IntPtr.Zero, IntPtr.Zero, true,
                    CREATE_NO_WINDOW | CREATE_UNICODE_ENVIRONMENT, environment, workingDirectory,
                    ref startup, out var processInfo))
            {
                throw new Win32Exception(Marshal.GetLastWin32Error(), "Unable to start managed service process.");
            }

            CloseHandle(processInfo.hThread);
            processHandle = processInfo.hProcess;

            var job = CreateJobObjectW(IntPtr.Zero, null);
            if (job != IntPtr.Zero && !AssignProcessToJobObject(job, processHandle))
            {
                CloseHandle(job);
                job = IntPtr.Zero;
            }
            jobHandle = job;

            return processInfo.dwProcessId;
        }
        finally
        {
            Marshal.FreeHGlobal(environment);
            CloseQuietly(stdinHandle);
            CloseQuietly(stdoutHandle);
            CloseQuietly(stderrHandle);
        }
    }

    public static bool IsAlive(IntPtr processHandle)
    {
        if (processHandle == IntPtr.Zero) return false;
        return GetExitCodeProcess(processHandle, out var exitCode) && exitCode == STILL_ACTIVE;
    }

    public static void WaitForExit(IntPtr processHandle, int milliseconds)
    {
        if (processHandle == IntPtr.Zero) return;
        WaitForSingleObject(processHandle, (uint)milliseconds);
    }

    public static void TerminateTree(IntPtr jobHandle, IntPtr processHandle)
    {
        if (jobHandle != IntPtr.Zero)
        {
            TerminateJobObject(jobHandle, 1);
            return;
        }
        if (processHandle != IntPtr.Zero) TerminateProcess(processHandle, 1);
    }

    public static void CloseHandleQuietly(IntPtr handle)
    {
        if (handle != IntPtr.Zero) CloseHandle(handle);
    }

    private static void CloseQuietly(IntPtr handle)
    {
        if (handle != IntPtr.Zero && handle != new IntPtr(-1)) CloseHandle(handle);
    }

    private static IntPtr BuildEnvironmentBlock(Guid serviceId)
    {
        var variables = new SortedDictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (DictionaryEntry entry in Environment.GetEnvironmentVariables())
        {
            if (entry.Key is string key && entry.Value is string value) variables[key] = value;
        }
        variables["PORT_MANAGER_SERVICE_ID"] = serviceId.ToString("D");

        var block = new StringBuilder();
        foreach (var pair in variables)
        {
            block.Append(pair.Key).Append('=').Append(pair.Value).Append('\0');
        }
        block.Append('\0');
        return Marshal.StringToHGlobalUni(block.ToString());
    }

    private static string ResolveShell()
    {
        var comSpec = Environment.GetEnvironmentVariable("ComSpec");
        return string.IsNullOrWhiteSpace(comSpec) ? "cmd.exe" : comSpec;
    }
}
