; Lightning Inno Setup Script
; Version: 1.0.0
; Author: Lightning Team

[Setup]
AppId={{9F8E7D6C-5B4A-4D3E-BF21-C0B9A8F7E6D5}
AppName=Lightning
AppVersion=1.0.0
AppPublisher=Lightning Team
DefaultDirName={autopf}\LightningVPN
DefaultGroupName=Lightning
AllowNoIcons=yes
; 架构要求：仅支持 x64
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
; 运行锁（防止安装时程序正在运行）
AppMutex=lightning_vpn_instance_lock
; 本地化设置
LanguageDetectionMethod=uilanguage
ShowLanguageDialog=yes
; 输出配置
OutputDir=installer_build
OutputBaseFilename=LightningVPN_Setup_v1.0.0
Compression=lzma2/ultra64
InternalCompressLevel=ultra
SolidCompression=yes
WizardStyle=modern
; 元数据
VersionInfoVersion=1.0.0
VersionInfoDescription=Lightning VPN Installer
; 图标配置
SetupIconFile=windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\lightning.exe
; 管理员权限要求（加载 wintun.dll 驱动及修改系统代理必需）
PrivilegesRequired=admin
; 覆盖安装时自动关闭运行中的程序
CloseApplications=yes
CloseApplicationsFilter=*.exe

[Languages]
Name: "en"; MessagesFile: "compiler:Default.isl"
Name: "zh"; MessagesFile: "installer_assets\ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; 🚀 Flutter Release 核心产物 (包含所有 dll 和 assets/data)
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

; 🚀 核心驱动与内核 (显式放置在根目录，方便 UAC 提权访问)
Source: "assets\windows\wintun.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "assets\windows\xray-core.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "assets\windows\geoip.dat"; DestDir: "{app}"; Flags: ignoreversion
Source: "assets\windows\geosite.dat"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\Lightning"; Filename: "{app}\lightning.exe"
Name: "{group}\{cm:UninstallProgram,Lightning}"; Filename: "{uninstallexe}"
Name: "{commondesktop}\Lightning"; Filename: "{app}\lightning.exe"; Tasks: desktopicon

[Run]
; 安装完成后自动启动
Filename: "{app}\lightning.exe"; Description: "{cm:LaunchProgram,Lightning}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; 卸载时彻底清理环境
Type: filesandordirs; Name: "{app}\logs"
Type: files; Name: "{app}\*.log"
Type: files; Name: "{app}\config.json"
Type: files; Name: "{app}\wintun.dll"
Type: filesandordirs; Name: "{app}\data"
; 彻底清理安装目录，防止残留
Type: filesandordirs; Name: "{app}"
; 🚀 核心修复：卸载时清理用户持久化数据 (AppData)
Type: filesandordirs; Name: "{userappdata}\lightning"

[Code]
// 🛡️ 环境检查：检测 VC++ 2015-2022 Redistributable (x64)
function VC2015RedistInstalled(): Boolean;
var
  Version: String;
begin
  Result := RegQueryStringValue(HKEY_LOCAL_MACHINE, 'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64', 'Version', Version);
  if not Result then
    Result := RegQueryStringValue(HKEY_LOCAL_MACHINE, 'SOFTWARE\WOW6432Node\Microsoft\VisualStudio\14.0\VC\Runtimes\x64', 'Version', Version);
end;

// 🛡️ 环境检查：检测 WebView2 Runtime
function WebView2Installed(): Boolean;
var
  Version: String;
begin
  Result := RegQueryStringValue(HKEY_LOCAL_MACHINE, 'SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8ABB-8224A2067880}', 'pv', Version);
  if not Result then
    Result := RegQueryStringValue(HKEY_CURRENT_USER, 'Software\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8ABB-8224A2067880}', 'pv', Version);
end;

function InitializeSetup(): Boolean;
begin
  Result := True;
  
  if not VC2015RedistInstalled() then
  begin
    if MsgBox('检测到您的系统缺少必要的 Visual C++ 运行库，程序可能无法正常启动。' #13#10 '建议安装后再继续，是否仍然坚持安装？', mbConfirmation, MB_YESNO) = IDNO then
      Result := False;
  end;

  if Result and not WebView2Installed() then
  begin
    if MsgBox('检测到您的系统缺少 WebView2 Runtime，部分功能（如内建网页显示）可能受限。' #13#10 '是否继续安装？', mbConfirmation, MB_YESNO) = IDNO then
      Result := False;
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  ResultCode: Integer;
begin
  if CurUninstallStep = usUninstall then
  begin
    // 1. 卸载前强制停止内核进程，防止文件占用导致删除失败
    Exec('taskkill', '/F /IM xray-core.exe /T', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    Exec('taskkill', '/F /IM lightning.exe /T', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  end;
  
  if CurUninstallStep = usPostUninstall then
  begin
    // 2. 清理开机自启注册表项
    RegDeleteValue(HKEY_CURRENT_USER, 'Software\Microsoft\Windows\CurrentVersion\Run', 'Lightning');
    // 3. 彻底恢复系统代理设置，防止卸载后断网
    if RegValueExists(HKEY_CURRENT_USER, 'Software\Microsoft\Windows\CurrentVersion\Internet Settings', 'ProxyEnable') then
    begin
      RegWriteDWordValue(HKEY_CURRENT_USER, 'Software\Microsoft\Windows\CurrentVersion\Internet Settings', 'ProxyEnable', 0);
      RegWriteStringValue(HKEY_CURRENT_USER, 'Software\Microsoft\Windows\CurrentVersion\Internet Settings', 'ProxyServer', '');
      RegWriteStringValue(HKEY_CURRENT_USER, 'Software\Microsoft\Windows\CurrentVersion\Internet Settings', 'ProxyOverride', '');
    end;
  end;
end;

