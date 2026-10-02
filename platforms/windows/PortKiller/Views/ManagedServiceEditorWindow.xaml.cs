using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using PortKiller.Models;
using PortKiller.Services;
using PortKiller.ViewModels;

namespace PortKiller.Views;

/// <summary>
/// Add/edit window for a local service profile. Top of the form is a type
/// picker: Custom Service (the original form, unchanged) or one of the six
/// presets, which drives a generated form from the preset definition
/// (design sections 3 and 5). Saving always goes through the existing
/// ManagedServicesViewModel.SaveProfile — the preset never bypasses
/// validation or persistence.
/// </summary>
public partial class ManagedServiceEditorWindow : Window
{
    private readonly ManagedServicesViewModel _viewModel;
    private readonly ManagedServiceConfig _config;
    private readonly bool _isNew;
    private readonly PathDependencyProbe _probe = new();
    private string? _docsUrl;
    private ManagedServicePreset? PreviousPreset { get; set; }
    private Dictionary<string, string> _fieldValues = new();

    public ManagedServiceEditorWindow(ManagedServicesViewModel viewModel, ManagedServiceConfig? existing, ManagedServicePreset? openingPreset = null)
    {
        InitializeComponent();
        _viewModel = viewModel;
        _isNew = existing is null;
        _config = existing?.Clone() ?? new ManagedServiceConfig { Host = "localhost" };

        foreach (var preset in ManagedServicePresets.All)
        {
            TypeBox.Items.Add(new ComboBoxItem
            {
                Content = PickerTitle(preset),
                Tag = preset.Id,
            });
        }

        NameBox.Text = _config.Name;
        PortBox.Text = _config.Port > 0 ? _config.Port.ToString(CultureInfo.InvariantCulture) : string.Empty;

        if (openingPreset is not null)
        {
            SelectType(openingPreset.Id);
        }
        else if (_config.PresetId is { } existingPresetId
                 && ManagedServicePresets.PresetWithId(existingPresetId) is not null)
        {
            // Known preset profiles re-open the preset form pre-filled.
            SelectType(existingPresetId);
        }
        else
        {
            SelectType("");
        }
    }

    private string PickerTitle(ManagedServicePreset preset)
    {
        var title = PresetStrings.Lookup(preset.TitleKey);
        return _probe.Probe(RequirementFor(preset)).State == DependencyProbeState.NotInstalled
            ? title + " — " + PresetStrings.Lookup("dependency.notInstalled")
            : title;
    }

    private static DependencyRequirement RequirementFor(ManagedServicePreset preset) =>
        DependencyRequirement.RequirementForPresetId(preset.Id) ?? new DependencyRequirement
        {
            BinaryName = preset.Id,
            NotInstalledKey = "dependency.notInstalled",
            InstallDocumentsURL = "https://github.com/sigoden/dufs",
        };

    private ManagedServicePreset? CurrentPreset
    {
        get
        {
            if (TypeBox.SelectedItem is ComboBoxItem { Tag: string id } && id.Length > 0)
            {
                return ManagedServicePresets.PresetWithId(id);
            }
            return null;
        }
    }

    private void SelectType(string presetId)
    {
        foreach (var item in TypeBox.Items.OfType<ComboBoxItem>())
        {
            if ((item.Tag as string ?? "") == presetId)
            {
                TypeBox.SelectedItem = item;
                break;
            }
        }
    }

    /// <summary>Rebuilds the form for the selected type. Custom keeps the
    /// original rows; presets render their field descriptors dynamically.</summary>
    private void Type_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        var preset = CurrentPreset;
        if (preset is not null)
        {
            if (_config.PresetId == preset.Id && !_isNew)
            {
                _fieldValues = ManagedServicePresetFieldExtractor.ExtractFieldValues(
                    preset, _config, Environment.GetFolderPath(Environment.SpecialFolder.UserProfile));
            }
            else
            {
                _fieldValues = preset.DefaultFieldValues();
                if (_fieldValues.ContainsKey("directory"))
                {
                    _fieldValues["directory"] = DirectoryBox.Text;
                }
            }
            if (preset.SuggestedPort is { } suggested && PortBox.Text.Length == 0)
            {
                PortBox.Text = suggested.ToString(CultureInfo.InvariantCulture);
            }
            RenderPresetFields(preset);
        }
        else
        {
            // Custom mode: keep the user's work — the start command becomes the
            // generated draft when leaving a preset.
            if (PreviousPreset is { } leaving)
            {
                var draft = GeneratePresetConfig(leaving);
                CommandBox.Text = draft.StartCommand;
                DirectoryBox.Text = draft.WorkingDirectory;
                NameBox.Text = draft.Name;
            }
            CustomPanel.Visibility = Visibility.Visible;
            PresetPanel.Visibility = Visibility.Collapsed;
            AdvancedPanel.Visibility = Visibility.Collapsed;
            DependencyBanner.Visibility = Visibility.Collapsed;
            PresetSummary.Visibility = Visibility.Collapsed;
        }
        PreviousPreset = preset;
    }

    private void RenderPresetFields(ManagedServicePreset preset)
    {
        PresetPanel.Children.Clear();
        AdvancedFields.Children.Clear();

        PresetSummary.Text = PresetStrings.Lookup(preset.SummaryKey);
        PresetSummary.Visibility = Visibility.Visible;
        CustomPanel.Visibility = Visibility.Collapsed;
        PresetPanel.Visibility = Visibility.Visible;

        RefreshDependencyBanner(preset);

        // Preset warnings (design section 10.2): static keys, with the
        // GatewayPorts warning only while the remote bind leaves loopback and
        // a home-root scope warning for directory presets.
        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        foreach (var warningKey in preset.ActiveWarningKeys(_fieldValues, home))
        {
            PresetPanel.Children.Add(new TextBlock
            {
                Text = PresetStrings.Lookup(warningKey),
                Foreground = System.Windows.Media.Brushes.Orange,
                FontSize = 11,
                TextWrapping = TextWrapping.Wrap,
                Margin = new Thickness(0, 0, 0, 10),
            });
        }

        foreach (var field in preset.Fields.Where(f => !f.IsAdvanced))
        {
            AddFieldRow(PresetPanel, field);
        }

        var advanced = preset.Fields.Where(f => f.IsAdvanced).ToList();
        foreach (var field in advanced)
        {
            AddFieldRow(AdvancedFields, field);
        }
        AdvancedPanel.Visibility = advanced.Count > 0 ? Visibility.Visible : Visibility.Collapsed;
    }

    private void AddFieldRow(StackPanel panel, PresetField field)
    {
        panel.Children.Add(new TextBlock
        {
            Text = PresetStrings.Lookup(field.TitleKey),
            Foreground = System.Windows.Media.Brushes.Gray,
            FontSize = 12,
        });

        switch (field.Kind)
        {
            case PresetFieldKind.Directory:
                var row = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 2, 0, 10) };
                var dirText = new TextBlock
                {
                    Text = ValueOf(field),
                    FontSize = 12,
                    VerticalAlignment = VerticalAlignment.Center,
                    TextTrimming = TextTrimming.CharacterEllipsis,
                    MaxWidth = 340,
                    Foreground = System.Windows.Media.Brushes.White,
                };
                var browse = new Button { Content = "Choose...", Padding = new Thickness(8, 2, 8, 2), Margin = new Thickness(8, 0, 0, 0) };
                browse.Click += (_, _) =>
                {
                    using var dialog = new System.Windows.Forms.FolderBrowserDialog
                    {
                        UseDescriptionForTitle = true,
                        Description = PresetStrings.Lookup(field.TitleKey),
                    };
                    if (dialog.ShowDialog() == System.Windows.Forms.DialogResult.OK)
                    {
                        _fieldValues[field.Id] = dialog.SelectedFolder;
                        dirText.Text = dialog.SelectedFolder;
                    }
                };
                row.Children.Add(dirText);
                row.Children.Add(browse);
                panel.Children.Add(row);
                break;

            case PresetFieldKind.SingleSelect:
                var combo = new ComboBox { Margin = new Thickness(0, 2, 0, 10), MinWidth = 180 };
                var current = ValueOf(field);
                foreach (var option in field.Options)
                {
                    combo.Items.Add(new ComboBoxItem { Content = PresetStrings.Lookup(option.TitleKey), Tag = option.Id });
                }
                var index = field.Options.ToList().FindIndex(o => o.Id == current);
                combo.SelectedIndex = index >= 0 ? index : 0;
                combo.SelectionChanged += (_, _) =>
                {
                    if (combo.SelectedItem is ComboBoxItem { Tag: string id })
                    {
                        _fieldValues[field.Id] = id;
                    }
                };
                panel.Children.Add(combo);
                break;

            default:
                var textBox = new TextBox { Padding = new Thickness(6), Margin = new Thickness(0, 2, 0, 10), Text = ValueOf(field) };
                textBox.TextChanged += (_, _) => _fieldValues[field.Id] = textBox.Text;
                panel.Children.Add(textBox);
                break;
        }

        if (field.HelpKey is { } helpKey)
        {
            panel.Children.Add(new TextBlock
            {
                Text = PresetStrings.Lookup(helpKey),
                Foreground = System.Windows.Media.Brushes.Gray,
                FontSize = 11,
                TextWrapping = TextWrapping.Wrap,
                Margin = new Thickness(0, 0, 0, 10),
            });
        }
    }

    private string ValueOf(PresetField field) =>
        _fieldValues.TryGetValue(field.Id, out var value) ? value : string.Empty;

    // MARK: Dependency banner

    private void RefreshDependencyBanner(ManagedServicePreset preset)
    {
        var requirement = DependencyRequirement.RequirementForPresetId(preset.Id);
        if (requirement is null)
        {
            DependencyBanner.Visibility = Visibility.Collapsed;
            return;
        }
        var (state, path) = _probe.Probe(requirement);
        if (state == DependencyProbeState.Available)
        {
            DependencyBannerText.Text = PresetStrings.Lookup("dependency.available", path);
            DependencyBannerText.Foreground = System.Windows.Media.Brushes.LightGreen;
            DependencyDocsButton.Visibility = Visibility.Collapsed;
            _docsUrl = null;
        }
        else
        {
            DependencyBannerText.Text = PresetStrings.Lookup(
                "dependency.notInstalledTitle", requirement.BinaryName) + " — "
                + PresetStrings.Lookup(requirement.NotInstalledKey);
            DependencyBannerText.Foreground = System.Windows.Media.Brushes.Orange;
            DependencyDocsButton.Visibility = Visibility.Visible;
            _docsUrl = requirement.InstallDocumentsURL;
        }
        DependencyBanner.Visibility = Visibility.Visible;
    }

    private void DependencyDocs_Click(object sender, RoutedEventArgs e)
    {
        if (_docsUrl is { } url)
        {
            try
            {
                System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo
                {
                    FileName = url,
                    UseShellExecute = true,
                });
            }
            catch
            {
                // Opening the browser is best effort; never crash the editor over it.
            }
        }
    }

    // MARK: Save

    private ManagedServiceConfig GeneratePresetConfig(ManagedServicePreset preset) =>
        preset.Generate(new PresetGenerationContext
        {
            Id = _config.Id,
            Name = NameBox.Text.Trim(),
            Port = ParsePort(),
            HomeDirectory = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
        }, _fieldValues);

    private int ParsePort() =>
        int.TryParse(PortBox.Text.Trim(), NumberStyles.Integer, CultureInfo.InvariantCulture, out var port)
            ? port : 0;

    private void Save_Click(object sender, RoutedEventArgs e)
    {
        if (!int.TryParse(PortBox.Text.Trim(), NumberStyles.Integer, CultureInfo.InvariantCulture, out var port))
        {
            ErrorText.Text = "Port must be a number.";
            return;
        }

        ManagedServiceConfig config;
        if (CurrentPreset is { } preset)
        {
            var fieldError = FirstInvalidField(preset);
            if (fieldError is not null)
            {
                ErrorText.Text = fieldError;
                return;
            }
            config = GeneratePresetConfig(preset);
        }
        else
        {
            _config.Name = NameBox.Text.Trim();
            _config.Port = port;
            _config.Host = HostBox.Text.Trim();
            _config.WorkingDirectory = DirectoryBox.Text.Trim();
            _config.StartCommand = CommandBox.Text;
            config = _config;
        }

        var error = _viewModel.SaveProfile(config, _isNew);
        if (error is not null)
        {
            ErrorText.Text = error.Message;
            return;
        }

        DialogResult = true;
        Close();
    }

    private string? FirstInvalidField(ManagedServicePreset preset)
    {
        foreach (var field in preset.Fields)
        {
            var value = _fieldValues.TryGetValue(field.Id, out var raw) ? raw : string.Empty;
            var kindError = ManagedServicePresetCharsetValidator.Validate(field.Charset, value);
            if (kindError is PresetFieldValueErrorKind.Empty)
            {
                if (field.IsRequired)
                {
                    return PresetStrings.Lookup("preset.error.empty", PresetStrings.Lookup(field.TitleKey));
                }
                continue;
            }
            if (kindError is PresetFieldValueErrorKind.NotAnInteger)
            {
                return PresetStrings.Lookup("preset.error.notAnInteger", PresetStrings.Lookup(field.TitleKey));
            }
            if (kindError is PresetFieldValueErrorKind.InvalidCharacters)
            {
                return PresetStrings.Lookup("preset.error.invalidCharacters", PresetStrings.Lookup(field.TitleKey));
            }
        }
        return null;
    }

    private void Cancel_Click(object sender, RoutedEventArgs e)
    {
        DialogResult = false;
        Close();
    }
}
