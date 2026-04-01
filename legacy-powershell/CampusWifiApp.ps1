param(
    [switch]$AutoStart
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

Import-Module (Join-Path $PSScriptRoot 'CampusWifi.Core.psm1') -Force

function Convert-StatusMessageToChinese {
    param([Parameter(Mandatory = $true)][string]$Message)

    switch -Regex ($Message) {
        '^Checking Wi-Fi adapter\.$' { return '正在检查无线网卡状态。' }
        '^Checking current Wi-Fi connection\.$' { return '正在检查当前 Wi-Fi 连接。' }
        '^Connected SSID: (.+)$' { return "当前连接的无线网络：$($Matches[1])" }
        '^Checking campus portal online status\.$' { return '正在检查校园网在线状态。' }
        '^Online status check failed before login: (.+)$' { return "登录前在线状态检查失败：$($Matches[1])" }
        '^Checking whether captive portal authentication is required\.$' { return '正在判断是否需要校园网认证。' }
        '^Opening campus portal: (.+)$' { return "正在进入认证页面：$($Matches[1])" }
        '^Preparing encrypted login payload\.$' { return '正在生成加密登录参数。' }
        '^Portal response: (.+)$' { return "认证接口返回：$($Matches[1])" }
        '^Verifying final online status\.$' { return '正在验证联网结果。' }
        '^Authentication succeeded\.$' { return '认证成功，已联网。' }
        '^Authentication request finished, but final online status is not confirmed\.$' { return '认证请求已完成，但暂未确认最终联网状态。' }
        '^Starting campus Wi-Fi workflow\.$' { return '正在启动校园网连接流程。' }
        '^No Wi-Fi adapter detected\.$' { return '未检测到无线网卡。' }
        '^Wi-Fi is turned off\.$' { return 'Wi-Fi 当前处于关闭状态。' }
        '^Wi-Fi is disabled\. Attempting to enable it\.$' { return 'Wi-Fi 已关闭，正在尝试开启。' }
        '^Wi-Fi enabled successfully\.$' { return 'Wi-Fi 已成功开启。' }
        '^Failed to enable Wi-Fi\.$' { return '开启 Wi-Fi 失败。' }
        '^Not connected to any Wi-Fi network\.$' { return '当前未连接任何 Wi-Fi。' }
        '^No Wi-Fi connection detected\. Attempting to connect to (.+)\.$' { return "当前未连接任何 Wi-Fi，正在尝试连接 $($Matches[1])。" }
        '^Connected to (.+) successfully\.$' { return "已成功连接到 $($Matches[1])。" }
        '^Campus Wi-Fi profile (.+) is not saved on this computer\.$' { return "这台电脑尚未保存 $($Matches[1]) 的无线配置，请先手动连接一次。" }
        '^Campus Wi-Fi (.+) is not currently in range\.$' { return "当前未扫描到 $($Matches[1])，请确认你已到校园网覆盖范围内。" }
        '^Failed to connect to (.+)\.$' { return "连接 $($Matches[1]) 失败。" }
        '^Wi-Fi connection is already present\.$' { return '已检测到当前存在 Wi-Fi 连接。' }
        '^No campus Wi-Fi SSID is configured\.$' { return '当前未配置校园网 SSID。' }
        '^Current Wi-Fi is not a campus network\.$' { return '当前连接的不是校园网。' }
        '^Campus portal already reports online\.$' { return '当前校园网状态显示已在线。' }
        '^Internet connectivity is already available\.$' { return '当前网络已经可用，无需再次认证。' }
        '^Captive portal authentication required\.$' { return '检测到需要进行校园网认证。' }
        '^Could not determine campus portal IP address\.$' { return '无法识别校园网认证所需的 IP 地址。' }
        '^Could not determine ac_id for the campus portal\.$' { return '无法识别校园网认证所需的 ac_id。' }
        '^Challenge token was not returned by the portal\.$' { return '认证服务器没有返回 challenge token。' }
        '^Unexpected JSONP response format\.$' { return '认证接口返回格式异常。' }
        '^流程执行完成。$' { return '流程执行完成。' }
        '^流程执行结束，但结果需要你手动确认。$' { return '流程执行结束，但结果需要你手动确认。' }
        '^发生异常：(.+)$' { return "发生异常：$($Matches[1])" }
        default { return $Message }
    }
}
function Load-XamlWindow {
    param([Parameter(Mandatory = $true)][string]$Xaml)

    [xml]$xml = $Xaml
    $reader = New-Object System.Xml.XmlNodeReader $xml
    $window = [Windows.Markup.XamlReader]::Load($reader)

    $controls = @{}
    foreach ($node in $xml.SelectNodes('//*[@Name]')) {
        $controls[$node.Name] = $window.FindName($node.Name)
    }

    [pscustomobject]@{
        Window   = $window
        Controls = $controls
    }
}

function Invoke-WpfUiRefresh {
    param([Parameter(Mandatory = $true)][System.Windows.Threading.Dispatcher]$Dispatcher)
    $Dispatcher.Invoke([Action] {}, [System.Windows.Threading.DispatcherPriority]::Background)
}

function Set-WpfBackgroundImage {
    param(
        [Parameter(Mandatory = $true)]$Target,
        [Parameter(Mandatory = $true)][string]$ImagePath
    )

    if (-not (Test-Path -LiteralPath $ImagePath)) {
        return $false
    }

    $bitmap = New-Object System.Windows.Media.Imaging.BitmapImage
    $bitmap.BeginInit()
    $bitmap.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
    $bitmap.UriSource = [Uri]$ImagePath
    $bitmap.EndInit()
    $bitmap.Freeze()

    if ($Target -is [System.Windows.Controls.Panel] -or $Target -is [System.Windows.Controls.Border]) {
        $brush = New-Object System.Windows.Media.ImageBrush $bitmap
        $brush.Stretch = 'UniformToFill'
        $Target.Background = $brush
        return $true
    }

    if ($Target -is [System.Windows.Controls.Image]) {
        $Target.Source = $bitmap
        return $true
    }

    return $false
}

function New-StatusWindow {
    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="校园网连接状态"
        Width="620"
        Height="420"
        WindowStartupLocation="CenterScreen"
        ResizeMode="NoResize"
        Background="#F6F8FB"
        FontFamily="SimSun"
        TextOptions.TextFormattingMode="Display"
        TextOptions.TextRenderingMode="ClearType"
        SnapsToDevicePixels="True">
    <Grid Margin="18">
        <Border CornerRadius="18" Background="#FFFFFFFF" BorderBrush="#D8E1EC" BorderThickness="1" Padding="18">
            <Grid Width="540" HorizontalAlignment="Center">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>
                <TextBlock Name="TitleText" Text="校园网认证进度" FontSize="20" FontWeight="Bold" Foreground="#1F3556"/>
                <TextBlock Grid.Row="1" Margin="0,10,0,12" Text="正在实时显示当前执行步骤" FontSize="12" Foreground="#5F6F84"/>
                <TextBox Name="StatusBox" Grid.Row="2" IsReadOnly="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Background="#F8FBFF" BorderBrush="#D7E3F1" BorderThickness="1" Padding="12" FontSize="12"/>
                <ProgressBar Name="ProgressBar" Grid.Row="3" Margin="0,14,0,0" Height="14" IsIndeterminate="True"/>
                <Button Name="CloseButton" Grid.Row="4" Width="132" Height="42" Margin="0,16,0,0" HorizontalAlignment="Right" Content="关闭窗口" FontSize="15" FontWeight="Bold" Background="#2566B5" Foreground="White" BorderThickness="0" IsEnabled="False"/>
            </Grid>
        </Border>
    </Grid>
</Window>
"@

    $view = Load-XamlWindow -Xaml $xaml
    [pscustomobject]@{
        Window      = $view.Window
        StatusBox   = $view.Controls['StatusBox']
        ProgressBar = $view.Controls['ProgressBar']
        CloseButton = $view.Controls['CloseButton']
    }
}

function Add-StatusLine {
    param(
        [Parameter(Mandatory = $true)]$Ui,
        [Parameter(Mandatory = $true)][string]$Message
    )

    $timestamp = Get-Date -Format 'HH:mm:ss'
    $translated = Convert-StatusMessageToChinese -Message $Message
    $line = "[$timestamp] $translated"

    if ([string]::IsNullOrWhiteSpace($Ui.StatusBox.Text)) {
        $Ui.StatusBox.Text = $line
    } else {
        $Ui.StatusBox.AppendText([Environment]::NewLine + $line)
    }

    $Ui.StatusBox.ScrollToEnd()
    Invoke-WpfUiRefresh -Dispatcher $Ui.Window.Dispatcher
}

function Show-StatusWorkflow {
    param(
        [Parameter(Mandatory = $true)][object]$Config,
        [Parameter(Mandatory = $true)][object]$Credentials,
        [switch]$AutoCloseOnSuccess
    )

    $ui = New-StatusWindow
    $resultHolder = [pscustomobject]@{
        Success       = $false
        Message       = ''
        ShouldExitApp = $false
    }

    $statusCallback = {
        param($message)
        Add-StatusLine -Ui $ui -Message $message
    }

    $ui.CloseButton.Add_Click({ $ui.Window.Close() })
    $started = $false

    $ui.Window.Add_ContentRendered({
        if ($started) { return }
        $started = $true
        try {
            $result = Invoke-CampusWifiLogin -Config $Config -Credentials $Credentials -StatusCallback $statusCallback
            $resultHolder.Success = [bool]$result.Success
            $resultHolder.Message = [string]$result.Message
            if ($result.Success) {
                Add-StatusLine -Ui $ui -Message '流程执行完成。'
                $ui.ProgressBar.IsIndeterminate = $false
                $ui.ProgressBar.Value = 100
                $resultHolder.ShouldExitApp = $true
                if ($AutoCloseOnSuccess) {
                    Start-Sleep -Seconds 2
                    $ui.Window.Close()
                    return
                }
            } else {
                Add-StatusLine -Ui $ui -Message '流程执行结束，但结果需要你手动确认。'
                $ui.ProgressBar.IsIndeterminate = $false
                $ui.ProgressBar.Value = 0
            }
        } catch {
            $resultHolder.Success = $false
            $resultHolder.Message = $_.Exception.Message
            Add-StatusLine -Ui $ui -Message "发生异常：$($_.Exception.Message)"
            $ui.ProgressBar.IsIndeterminate = $false
            $ui.ProgressBar.Value = 0
            $resultHolder.ShouldExitApp = $false
        } finally {
            $ui.CloseButton.IsEnabled = $true
        }
    })

    [void]$ui.Window.ShowDialog()
    $resultHolder
}

function New-MainWindow {
    param(
        [Parameter(Mandatory = $true)][object]$Saved,
        [Parameter(Mandatory = $true)][object]$Paths
    )

    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="杭州师范大学校园网助手"
        Width="980"
        Height="680"
        WindowStartupLocation="CenterScreen"
        ResizeMode="NoResize"
        Background="#EEF4FA"
        FontFamily="SimSun"
        TextOptions.TextFormattingMode="Display"
        TextOptions.TextRenderingMode="ClearType"
        SnapsToDevicePixels="True">
    <Grid Name="RootGrid">
        <Grid.Background>
            <SolidColorBrush Color="#EAF1F8"/>
        </Grid.Background>
        <Border HorizontalAlignment="Center" VerticalAlignment="Center" Width="690" Height="490" Background="#B2FFFFFF" BorderBrush="#C9D7E6" BorderThickness="1" CornerRadius="22" Padding="32">
            <Border.Effect>
                <DropShadowEffect BlurRadius="24" ShadowDepth="0" Color="#220B1A2B"/>
            </Border.Effect>
            <Grid Width="540" HorizontalAlignment="Center">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>
                <TextBlock Name="TitleText" Text="杭州师范大学校园网助手" FontSize="26" FontWeight="Bold" Foreground="#20395B" HorizontalAlignment="Center" TextAlignment="Center"/>
                <Rectangle Grid.Row="1" Margin="0,14,0,12" Height="1.5" Fill="#BACBDE" RadiusX="1" RadiusY="1"/>
                <TextBlock Grid.Row="2" Text="请输入账号信息，并选择是否保存凭据或开机自启" FontSize="13" FontWeight="SemiBold" Foreground="#56677C" HorizontalAlignment="Center" TextAlignment="Center"/>
                <Grid Grid.Row="3" Margin="28,38,28,0">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="86"/>
                        <ColumnDefinition Width="310"/>
                    </Grid.ColumnDefinitions>
                    <TextBlock Grid.Column="0" VerticalAlignment="Center" Text="学号" FontSize="20" FontWeight="Bold" Foreground="#23354D"/>
                    <TextBox Name="StudentIdBox" Grid.Column="1" Height="38" FontSize="18" Padding="10,10,10,4" BorderBrush="#B4C5D9" BorderThickness="1.2" Background="#FCFEFF"/>
                </Grid>
                <Grid Grid.Row="4" Margin="28,22,28,0">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="86"/>
                        <ColumnDefinition Width="310"/>
                    </Grid.ColumnDefinitions>
                    <TextBlock Grid.Column="0" VerticalAlignment="Center" Text="密码" FontSize="20" FontWeight="Bold" Foreground="#23354D"/>
                    <PasswordBox Name="PasswordBox" Grid.Column="1" Height="38" FontSize="16" Padding="10,10,10,4" BorderBrush="#B4C5D9" BorderThickness="1.2" Background="#FCFEFF"/>
                </Grid>
                <CheckBox Name="RememberCheckBox" Grid.Row="5" Margin="114,28,0,0" Content="保存账号密码" FontSize="16" FontWeight="Bold" Foreground="#2F4056"/>
                <CheckBox Name="StartupCheckBox" Grid.Row="6" Margin="114,16,0,0" Content="开机后自动检测并连接校园网" FontSize="16" FontWeight="Bold" Foreground="#2F4056"/>
                <StackPanel Grid.Row="7" Margin="114,24,0,0">
                    <TextBlock Name="SavedHintText" TextWrapping="Wrap" FontSize="12" Foreground="#5B6775"/>
                    <TextBlock Name="BackgroundHintText" Margin="0,8,0,0" TextWrapping="Wrap" FontSize="11" Foreground="#78828D"/>
                </StackPanel>
                <Button Name="ConnectButton" Grid.Row="8" HorizontalAlignment="Center" Width="196" Height="52" Margin="0,28,0,0" Content="连接校园网" FontSize="17" FontWeight="Bold" Foreground="White" Background="#2566B5" BorderThickness="0"/>
            </Grid>
        </Border>
    </Grid>
</Window>
"@

    $view = Load-XamlWindow -Xaml $xaml
    $window = $view.Window
    $controls = $view.Controls


    $backgroundPath = Join-Path $Paths.ScriptDir 'main_background.jpg'
    $hasBackground = Set-WpfBackgroundImage -Target $controls['RootGrid'] -ImagePath $backgroundPath

    $controls['SavedHintText'].Text = if ($Saved.RememberCredentials) { '当前已保存凭据，重新输入并连接后会覆盖旧信息。' } else { '当前未保存凭据。' }
    $controls['BackgroundHintText'].Text = if ($hasBackground) { '当前已加载主界面背景图。' } else { '未找到背景图，请将图片保存为 main_background.jpg 放到程序目录。' }
    $controls['RememberCheckBox'].IsChecked = $Saved.RememberCredentials
    $controls['StartupCheckBox'].IsChecked = $Saved.AutoStart

    if ($Saved.RememberCredentials) {
        $storedCredential = Get-CampusWifiRuntimeCredential -Config $Saved.Config -AllowStored
        if ($storedCredential) {
            $controls['StudentIdBox'].Text = [string]$storedCredential.StudentId
            $controls['PasswordBox'].Password = [string]$storedCredential.Password
        }
    }

    [pscustomobject]@{
        Window   = $window
        Controls = $controls
    }
}

function Show-MainForm {
    $saved = Get-CampusWifiSavedState
    $paths = Get-CampusWifiPaths
    $view = New-MainWindow -Saved $saved -Paths $paths
    $window = $view.Window
    $controls = $view.Controls

    $applyAutoStartPreference = {
        param([bool]$Enabled)
        $config = Get-CampusWifiConfig
        $config.autoStart = $Enabled
        Save-CampusWifiConfig -Config $config
        Set-CampusWifiStartupEnabled -Enabled $Enabled
    }

    $suppressStartupToggle = $false

    $controls['RememberCheckBox'].Add_Unchecked({
        if ($controls['StartupCheckBox'].IsChecked) {
            $suppressStartupToggle = $true
            $controls['StartupCheckBox'].IsChecked = $false
            $suppressStartupToggle = $false
            & $applyAutoStartPreference $false
            [System.Windows.MessageBox]::Show('已关闭开机自启。若不保存账号密码，将无法自动连接校园网。', '校园网助手', 'OK', 'Information') | Out-Null
            $window.Activate()
        }
    })

    $controls['StartupCheckBox'].Add_Checked({
        if ($suppressStartupToggle) { return }

        if (-not [bool]$controls['RememberCheckBox'].IsChecked) {
            $suppressStartupToggle = $true
            [System.Windows.MessageBox]::Show('要启用开机自启，请先勾选“保存账号密码”。', '校园网助手', 'OK', 'Warning') | Out-Null
            $controls['StartupCheckBox'].IsChecked = $false
            $suppressStartupToggle = $false
            $window.Activate()
            return
        }

        if (-not (Test-Path -LiteralPath $paths.CredentialPath)) {
            $suppressStartupToggle = $true
            [System.Windows.MessageBox]::Show('请先完成一次连接并保存账号密码，之后才能启用开机自启。', '校园网助手', 'OK', 'Information') | Out-Null
            $controls['StartupCheckBox'].IsChecked = $false
            $suppressStartupToggle = $false
            $window.Activate()
            return
        }

        & $applyAutoStartPreference $true
        $window.Activate()
    })

    $controls['StartupCheckBox'].Add_Unchecked({
        if ($suppressStartupToggle) { return }
        & $applyAutoStartPreference $false
        $window.Activate()
    })

    $saveAction = {
        $studentId = $controls['StudentIdBox'].Text.Trim()
        $password = $controls['PasswordBox'].Password
        $remember = [bool]$controls['RememberCheckBox'].IsChecked
        $autoStart = [bool]$controls['StartupCheckBox'].IsChecked

        if ($autoStart -and -not $remember) {
            [System.Windows.MessageBox]::Show('如果要开机自启，必须同时保存账号密码。', '校园网助手', 'OK', 'Warning') | Out-Null
            $window.Activate()
            return $null
        }

        if ([string]::IsNullOrWhiteSpace($studentId) -or [string]::IsNullOrWhiteSpace($password)) {
            [System.Windows.MessageBox]::Show('点击连接前，请先输入学号和密码。', '校园网助手', 'OK', 'Warning') | Out-Null
            $window.Activate()
            return $null
        }

        $persistedStudentId = if ($remember) { $studentId } else { '' }
        $persistedPassword = if ($remember) { $password } else { '' }

        Save-CampusWifiAppSettings -StudentId $persistedStudentId -Password $persistedPassword -RememberCredentials $remember -AutoStart $autoStart
        $controls['SavedHintText'].Text = if ($remember) { '设置已保存，当前将使用已保存凭据。' } else { '设置已保存，当前未保存凭据。' }

        [pscustomobject]@{
            StudentId = $studentId
            Password  = $password
        }
    }
    $controls['ConnectButton'].Add_Click({
        try {
            $runtimeConfig = Get-CampusWifiConfig
            $state = Get-CampusWifiState -Config $runtimeConfig

            switch ($state.State) {
                'NoWifiAdapter' {
                    [System.Windows.MessageBox]::Show('未检测到 Wi‑Fi 适配器。', '校园网助手', 'OK', 'Warning') | Out-Null
                    $window.Activate()
                    return
                }
                'WifiOff' {
                    [System.Windows.MessageBox]::Show('当前 Wi‑Fi 未开启，请先打开 Wi‑Fi 后再继续。', '校园网助手', 'OK', 'Information') | Out-Null
                    $window.Activate()
                    return
                }
                'NoWifiConnection' {
                    [System.Windows.MessageBox]::Show('当前未连接任何 Wi‑Fi，请先连接 HZNU 后再继续。', '校园网助手', 'OK', 'Information') | Out-Null
                    $window.Activate()
                    return
                }
                'OtherWifiConnected' {
                    $ssidText = if ($state.CurrentSsid) { [string]$state.CurrentSsid } else { '未知网络' }
                    [System.Windows.MessageBox]::Show("当前连接的不是校园网：$ssidText`n请先连接 HZNU 后再继续。", '校园网助手', 'OK', 'Information') | Out-Null
                    $window.Activate()
                    return
                }
                'CampusWifiOnline' {
                    [System.Windows.MessageBox]::Show('已经完成验证，无需重新验证。', '校园网助手', 'OK', 'Information') | Out-Null
                    $window.Activate()
                    return
                }
                'CampusWifiNeedsAuth' { }
                default {
                    [System.Windows.MessageBox]::Show((Convert-StatusMessageToChinese -Message $state.Reason), '校园网助手', 'OK', 'Information') | Out-Null
                    $window.Activate()
                    return
                }
            }

            $runtimeCredentials = & $saveAction
            if (-not $runtimeCredentials) { return }

            $window.Hide()
            $workflowResult = Show-StatusWorkflow -Config $runtimeConfig -Credentials $runtimeCredentials
            if ($workflowResult.ShouldExitApp) {
                $window.Close()
                return
            }
            $window.Show()
            $window.Activate()
        } catch {
            [System.Windows.MessageBox]::Show("连接流程异常：$($_.Exception.Message)", '校园网助手', 'OK', 'Warning') | Out-Null
            $window.Show()
            $window.Activate()
        }
    })

    [void]$window.ShowDialog()
}
if ($AutoStart) {
    try {
        $saved = Get-CampusWifiSavedState
        if (-not $saved.AutoStart) { exit 0 }

        $credentials = Get-CampusWifiRuntimeCredential -Config $saved.Config -AllowStored
        if (-not $credentials) { exit 0 }

        $state = Get-CampusWifiState -Config $saved.Config
        if ($state.State -eq 'CampusWifiNeedsAuth') {
            $workflowResult = Show-StatusWorkflow -Config $saved.Config -Credentials $credentials -AutoCloseOnSuccess
            if (-not $workflowResult.ShouldExitApp) {
                Show-MainForm
            }
        }
    } catch {
        Write-CampusWifiLog -Message "自启动流程异常：$($_.Exception.Message)"
    }
    exit 0
}
Show-MainForm
