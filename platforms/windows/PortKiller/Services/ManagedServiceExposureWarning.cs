using PortKiller.Models;

namespace PortKiller.Services;

/// <summary>
/// Exposure double-warning mapping (design section 10.2): publicly sharing
/// a writable Dufs gets an explicit warning; publicly sharing Jupyter gets a
/// strong warning (public Jupyter = arbitrary code execution). Everything
/// else shares without an extra gate, exactly as today. Mirrors macOS
/// ManagedServiceExposureWarning.
/// </summary>
public static class ManagedServiceExposureWarning
{
    /// <summary>Warning message for publicly sharing this service, or null
    /// when the existing share flow needs no extra warning.</summary>
    public static string? MessageFor(ManagedServiceConfig config)
    {
        switch (config.PresetId)
        {
            case "dufs-file-share":
                // Mode is encoded in the generated flags; detect writability
                // from the command rather than persisting form state.
                return config.StartCommand.Contains("--allow-upload", StringComparison.Ordinal)
                    ? "exposure.warning.dufsWritablePublic"
                    : "exposure.warning.dufsPublic";
            case "jupyter-lab":
                return "exposure.warning.jupyterPublic";
            default:
                return null;
        }
    }
}
