namespace PortKiller.Models;

/// <summary>
/// Interface language selection. System follows the OS UI culture
/// (Chinese when it starts with "zh", English otherwise).
/// </summary>
public enum AppLanguage
{
    System,
    English,
    SimplifiedChinese
}
