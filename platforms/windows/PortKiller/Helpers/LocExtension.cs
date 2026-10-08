using System;
using System.Windows.Data;
using System.Windows.Markup;
using PortKiller.Services;

namespace PortKiller.Helpers;

/// <summary>
/// XAML markup extension for localized strings: {loc:Loc settings.title}.
/// Produces a OneWay binding to LocalizationService[Key] so text updates
/// live when the language changes.
/// </summary>
[MarkupExtensionReturnType(typeof(string))]
public class LocExtension : MarkupExtension
{
    public string Key { get; set; }

    public LocExtension(string key)
    {
        Key = key;
    }

    public override object ProvideValue(IServiceProvider serviceProvider)
    {
        var binding = new Binding($"[{Key}]")
        {
            Source = LocalizationService.Instance,
            Mode = BindingMode.OneWay,
        };
        return binding.ProvideValue(serviceProvider);
    }
}
