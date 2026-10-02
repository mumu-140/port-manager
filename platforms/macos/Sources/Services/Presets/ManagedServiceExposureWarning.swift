import Foundation

/// Exposure double-warning mapping (design section 10.2): publicly sharing a
/// writable Dufs gets an explicit warning; publicly sharing Jupyter gets a
/// strong warning (public Jupyter = arbitrary code execution). Everything
/// else shares without an extra gate, exactly as today.
enum ManagedServiceExposureWarning {
    /// Localized message key for publicly sharing this service, or nil when
    /// the existing share flow needs no extra warning.
    static func messageKey(for config: ManagedServiceConfig) -> String? {
        switch config.presetID {
        case "dufs-file-share":
            // Mode is encoded in the generated flags; detect writability from
            // the command rather than persisting form state.
            return config.startCommand.contains("--allow-upload")
                ? "exposure.warning.dufsWritablePublic"
                : "exposure.warning.dufsPublic"
        case "jupyter-lab":
            return "exposure.warning.jupyterPublic"
        default:
            return nil
        }
    }
}
