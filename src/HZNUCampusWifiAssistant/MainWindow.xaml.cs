using System;
using System.IO;
using System.Reflection;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using HZNUCampusWifiAssistant.Models;
using HZNUCampusWifiAssistant.Services;

namespace HZNUCampusWifiAssistant;

public partial class MainWindow : Window
{
    private const string EmbeddedBackgroundResourceName = "HZNUCampusWifiAssistant.main_background.jpg";

    private readonly bool _autoStartMode;
    private readonly AppPaths _paths;
    private readonly SettingsService _settingsService;
    private readonly CredentialStore _credentialStore;
    private readonly ShortcutService _shortcutService;
    private readonly CampusWifiService _campusWifiService;

    private AppSettings _settings;
    private bool _suppressAutoStartEvents;
    private bool _lastWorkflowSucceeded;

    public MainWindow(bool autoStartMode)
    {
        InitializeComponent();

        _autoStartMode = autoStartMode;
        _paths = new AppPaths();
        _settingsService = new SettingsService(_paths);
        _credentialStore = new CredentialStore(_paths);
        _shortcutService = new ShortcutService(_paths);
        _campusWifiService = new CampusWifiService();
        _settings = _settingsService.Load();

        Loaded += MainWindow_Loaded;
        ConnectButton.Click += ConnectButton_Click;
        StatusCloseButton.Click += StatusCloseButton_Click;
        AutoStartCheckBox.Checked += AutoStartCheckBox_Checked;
        AutoStartCheckBox.Unchecked += AutoStartCheckBox_Unchecked;
        RememberCredentialsCheckBox.Unchecked += RememberCredentialsCheckBox_Unchecked;

        if (_autoStartMode)
        {
            Opacity = 0;
            ShowInTaskbar = false;
        }
    }

    private async void MainWindow_Loaded(object sender, RoutedEventArgs e)
    {
        ApplyBackgroundImage();
        _shortcutService.EnsureDesktopShortcut();
        LoadSavedStateToUi();

        if (_autoStartMode)
        {
            await RunAutoStartAsync();
            return;
        }

        ShowSettingsView();
    }

    private void ApplyBackgroundImage()
    {
        try
        {
            using var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream(EmbeddedBackgroundResourceName)
                ?? throw new InvalidOperationException("未找到内嵌背景图资源。");

            using var memoryStream = new MemoryStream();
            stream.CopyTo(memoryStream);
            memoryStream.Position = 0;

            var bitmap = new BitmapImage();
            bitmap.BeginInit();
            bitmap.CacheOption = BitmapCacheOption.OnLoad;
            bitmap.StreamSource = memoryStream;
            bitmap.EndInit();
            bitmap.Freeze();

            RootGrid.Background = new ImageBrush(bitmap)
            {
                Stretch = Stretch.UniformToFill
            };
            BackgroundHintTextBlock.Text = "当前已加载内置背景图。";
        }
        catch (Exception ex)
        {
            BackgroundHintTextBlock.Text = $"未能加载内置背景图，将使用默认背景。({ex.Message})";
        }
    }

    private void LoadSavedStateToUi()
    {
        _settings = _settingsService.Load();
        RememberCredentialsCheckBox.IsChecked = _settings.RememberCredentials;

        _suppressAutoStartEvents = true;
        AutoStartCheckBox.IsChecked = _settings.AutoStart;
        _suppressAutoStartEvents = false;

        var credential = _credentialStore.Load();
        if (credential is not null)
        {
            StudentIdTextBox.Text = credential.StudentId;
            PasswordBox.Password = credential.Password;
            HintTextBlock.Text = "当前已保存凭据，重新输入并连接后会覆盖旧信息。";
        }
        else
        {
            HintTextBlock.Text = "当前未保存凭据。";
        }
    }

    private void ShowSettingsView()
    {
        SettingsPanel.Visibility = Visibility.Visible;
        StatusPanel.Visibility = Visibility.Collapsed;
        StatusCloseButton.IsEnabled = false;
        if (_autoStartMode && Opacity == 0)
        {
            Opacity = 1;
            ShowInTaskbar = true;
        }

        Activate();
    }

    private void ShowStatusView(string subtitle)
    {
        SettingsPanel.Visibility = Visibility.Collapsed;
        StatusPanel.Visibility = Visibility.Visible;
        StatusSubtitleTextBlock.Text = subtitle;
        StatusTextBox.Clear();
        StatusCloseButton.IsEnabled = false;

        if (_autoStartMode && Opacity == 0)
        {
            Opacity = 1;
            ShowInTaskbar = true;
        }

        Activate();
    }

    private void AppendStatus(string message)
    {
        var line = $"[{DateTime.Now:HH:mm:ss}] {message}";
        if (string.IsNullOrWhiteSpace(StatusTextBox.Text))
        {
            StatusTextBox.Text = line;
        }
        else
        {
            StatusTextBox.AppendText(Environment.NewLine + line);
        }

        StatusTextBox.ScrollToEnd();
    }

    private async void ConnectButton_Click(object sender, RoutedEventArgs e)
    {
        var studentId = StudentIdTextBox.Text.Trim();
        var password = PasswordBox.Password;

        if (string.IsNullOrWhiteSpace(studentId) || string.IsNullOrWhiteSpace(password))
        {
            MessageBox.Show("点击连接前，请先输入学号和密码。", "校园网助手", MessageBoxButton.OK, MessageBoxImage.Warning);
            Activate();
            return;
        }

        _settings.RememberCredentials = RememberCredentialsCheckBox.IsChecked == true;
        _settings.AutoStart = AutoStartCheckBox.IsChecked == true;
        _settingsService.Save(_settings);

        if (_settings.RememberCredentials)
        {
            _credentialStore.Save(new CredentialInfo(studentId, password));
            HintTextBlock.Text = "当前已保存凭据，重新输入并连接后会覆盖旧信息。";
        }
        else
        {
            _credentialStore.Delete();
            HintTextBlock.Text = "当前未保存凭据。";
        }

        _shortcutService.SetStartupEnabled(_settings.AutoStart);
        _shortcutService.EnsureDesktopShortcut();

        CampusWifiState state;
        try
        {
            state = await _campusWifiService.GetCampusWifiStateAsync(_settings);
        }
        catch (Exception ex)
        {
            MessageBox.Show($"状态检查失败：{ex.Message}", "校园网助手", MessageBoxButton.OK, MessageBoxImage.Warning);
            Activate();
            return;
        }

        switch (state.Kind)
        {
            case CampusWifiStateKind.NoWifiAdapter:
            case CampusWifiStateKind.WifiOff:
            case CampusWifiStateKind.NoWifiConnection:
            case CampusWifiStateKind.OtherWifiConnected:
            case CampusWifiStateKind.CampusWifiOnline:
                MessageBox.Show(state.Message, "校园网助手", MessageBoxButton.OK, MessageBoxImage.Information);
                Activate();
                return;
            case CampusWifiStateKind.CampusWifiNeedsAuth:
                break;
            default:
                MessageBox.Show("当前状态暂不支持处理。", "校园网助手", MessageBoxButton.OK, MessageBoxImage.Information);
                Activate();
                return;
        }

        await RunAuthenticationWorkflowAsync(state, new CredentialInfo(studentId, password), autoCloseOnSuccess: true);
    }

    private async Task RunAutoStartAsync()
    {
        if (!_settings.AutoStart)
        {
            Close();
            return;
        }

        var credential = _credentialStore.Load();
        if (credential is null)
        {
            Close();
            return;
        }

        CampusWifiState state;
        try
        {
            state = await _campusWifiService.GetCampusWifiStateAsync(_settings);
        }
        catch
        {
            Close();
            return;
        }

        if (state.Kind != CampusWifiStateKind.CampusWifiNeedsAuth)
        {
            Close();
            return;
        }

        StudentIdTextBox.Text = credential.StudentId;
        PasswordBox.Password = credential.Password;
        RememberCredentialsCheckBox.IsChecked = true;
        await RunAuthenticationWorkflowAsync(state, credential, autoCloseOnSuccess: true);
    }

    private async Task RunAuthenticationWorkflowAsync(CampusWifiState state, CredentialInfo credential, bool autoCloseOnSuccess)
    {
        _lastWorkflowSucceeded = false;
        ShowStatusView("正在实时显示当前执行步骤");

        var progress = new Progress<string>(AppendStatus);
        WorkflowResult result;
        try
        {
            result = await _campusWifiService.AuthenticateAsync(_settings, credential, state, progress);
        }
        catch (Exception ex)
        {
            AppendStatus($"发生异常：{ex.Message}");
            StatusCloseButton.IsEnabled = true;
            return;
        }

        AppendStatus(result.Message);
        _lastWorkflowSucceeded = result.Success;
        StatusCloseButton.IsEnabled = true;

        if (result.Success && autoCloseOnSuccess)
        {
            await Task.Delay(1500);
            Close();
        }
    }

    private void StatusCloseButton_Click(object sender, RoutedEventArgs e)
    {
        if (_lastWorkflowSucceeded)
        {
            Close();
            return;
        }

        ShowSettingsView();
    }

    private void RememberCredentialsCheckBox_Unchecked(object sender, RoutedEventArgs e)
    {
        if (AutoStartCheckBox.IsChecked == true)
        {
            _suppressAutoStartEvents = true;
            AutoStartCheckBox.IsChecked = false;
            _suppressAutoStartEvents = false;
            _settings.AutoStart = false;
            _settingsService.Save(_settings);
            _shortcutService.SetStartupEnabled(false);
            MessageBox.Show("已关闭开机自启。若不保存账号密码，将无法自动连接校园网。", "校园网助手", MessageBoxButton.OK, MessageBoxImage.Information);
            Activate();
        }
    }

    private void AutoStartCheckBox_Checked(object sender, RoutedEventArgs e)
    {
        if (_suppressAutoStartEvents)
        {
            return;
        }

        if (RememberCredentialsCheckBox.IsChecked != true)
        {
            _suppressAutoStartEvents = true;
            AutoStartCheckBox.IsChecked = false;
            _suppressAutoStartEvents = false;
            MessageBox.Show("要启用开机自启，请先勾选“保存账号密码”。", "校园网助手", MessageBoxButton.OK, MessageBoxImage.Warning);
            Activate();
            return;
        }

        var studentId = StudentIdTextBox.Text.Trim();
        var password = PasswordBox.Password;
        var storedCredential = _credentialStore.Load();
        var hasRuntimeCredential = !string.IsNullOrWhiteSpace(studentId) && !string.IsNullOrWhiteSpace(password);
        var effectiveCredential = hasRuntimeCredential ? new CredentialInfo(studentId, password) : storedCredential;
        if (effectiveCredential is null)
        {
            _suppressAutoStartEvents = true;
            AutoStartCheckBox.IsChecked = false;
            _suppressAutoStartEvents = false;
            MessageBox.Show("请先输入并保存一次账号密码，然后再启用开机自启。", "校园网助手", MessageBoxButton.OK, MessageBoxImage.Information);
            Activate();
            return;
        }

        _settings.RememberCredentials = true;
        _settings.AutoStart = true;
        _settingsService.Save(_settings);
        _credentialStore.Save(effectiveCredential);
        _shortcutService.SetStartupEnabled(true);
        HintTextBlock.Text = "当前已保存凭据，重新输入并连接后会覆盖旧信息。";
        Activate();
    }

    private void AutoStartCheckBox_Unchecked(object sender, RoutedEventArgs e)
    {
        if (_suppressAutoStartEvents)
        {
            return;
        }

        _settings.AutoStart = false;
        _settingsService.Save(_settings);
        _shortcutService.SetStartupEnabled(false);
        Activate();
    }
}
