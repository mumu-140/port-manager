using System.IO;
using System.Security.AccessControl;
using System.Security.Principal;

namespace PortKiller.Services;

/// <summary>
/// On-disk locations and lifecycle of managed-service runtime output.
///
/// A managed service is allowed to outlive Port Manager (design notes, section
/// 6.5). A parent-owned stdout/stderr pipe cannot support that guarantee: once
/// the app exits the read end closes and the child dies on the next write.
/// Output is therefore redirected to per-service files that no app process has
/// to keep open, and the running app tails them into its bounded in-memory log.
///
/// Logs are runtime artifacts, never profile data. They live under the system
/// temporary directory, are truncated for every launch, and are removed on
/// explicit cleanup and on the next app startup.
/// </summary>
public static class ManagedServiceRuntimeLogStore
{
    public const string DirectoryName = "PortManagerManagedServices";
    public const string StdoutFileName = "stdout.log";
    public const string StderrFileName = "stderr.log";

    public static string RootDirectory => Path.Combine(Path.GetTempPath(), DirectoryName);

    public static string DirectoryFor(Guid serviceId) =>
        Path.Combine(RootDirectory, serviceId.ToString("D"));

    public static string StdoutPath(Guid serviceId) =>
        Path.Combine(DirectoryFor(serviceId), StdoutFileName);

    public static string StderrPath(Guid serviceId) =>
        Path.Combine(DirectoryFor(serviceId), StderrFileName);

    /// <summary>Creates (or truncates) the per-service log directory.</summary>
    public static void Prepare(Guid serviceId, out string stdoutPath, out string stderrPath)
    {
        var directory = DirectoryFor(serviceId);
        System.IO.Directory.CreateDirectory(directory);
        HardenDirectory(directory);

        stdoutPath = Path.Combine(directory, StdoutFileName);
        stderrPath = Path.Combine(directory, StderrFileName);
        Truncate(stdoutPath);
        Truncate(stderrPath);
    }

    /// <summary>Removes the runtime logs of one service.</summary>
    public static void Cleanup(Guid serviceId) => RemoveSafely(DirectoryFor(serviceId), RootDirectory);

    /// <summary>Removes every runtime log directory. Called at app startup.</summary>
    public static void RemoveAll() => RemoveSafely(RootDirectory, RootDirectory);

    private static void Truncate(string path)
    {
        using (new FileStream(path, FileMode.Create, FileAccess.Write, FileShare.ReadWrite | FileShare.Delete))
        {
        }
        HardenFile(path);
    }

    private static void HardenDirectory(string directory)
    {
        try
        {
            var info = new DirectoryInfo(directory);
            var security = info.GetAccessControl();
            security.SetAccessRuleProtection(true, false);
            var user = WindowsIdentity.GetCurrent().User;
            if (user is not null)
            {
                security.AddAccessRule(new FileSystemAccessRule(
                    user,
                    FileSystemRights.FullControl,
                    InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit,
                    PropagationFlags.None,
                    AccessControlType.Allow));
            }
            info.SetAccessControl(security);
        }
        catch (Exception)
        {
            // Permission hardening is best-effort; the log directory still lives
            // under the per-user temporary directory.
        }
    }

    private static void HardenFile(string path)
    {
        try
        {
            var info = new FileInfo(path);
            var security = info.GetAccessControl();
            security.SetAccessRuleProtection(true, false);
            var user = WindowsIdentity.GetCurrent().User;
            if (user is not null)
            {
                security.AddAccessRule(new FileSystemAccessRule(user, FileSystemRights.FullControl, AccessControlType.Allow));
            }
            info.SetAccessControl(security);
        }
        catch (Exception)
        {
        }
    }

    /// <summary>Deletes a path only when it lies inside <paramref name="root"/>.</summary>
    private static void RemoveSafely(string path, string root)
    {
        try
        {
            var full = Path.GetFullPath(path);
            var rootFull = Path.GetFullPath(root)
                .TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
            var inside = full.Equals(rootFull, StringComparison.OrdinalIgnoreCase) ||
                         full.StartsWith(rootFull + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase);
            if (!inside) return;
            if (System.IO.Directory.Exists(full)) System.IO.Directory.Delete(full, recursive: true);
        }
        catch (Exception)
        {
        }
    }
}
