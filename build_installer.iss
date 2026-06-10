; Lightning Inno Setup Script
; Version: 1.0.0
; Author: Lightning Team

[Setup]
AppId={{9F8E7D6C-5B4A-4D3E-BF21-C0B9A8F7E6D5}
AppName=Lightning
AppVersion=1.0.0
AppPublisher=https://lightning-vps.com
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
ShowLanguageDialog=no
; 输出配置
OutputDir=installer_build
OutputBaseFilename=LightningVPN_Setup_v1.0.0
Compression=lzma2/ultra64
InternalCompressLevel=ultra
SolidCompression=yes
WizardStyle=modern
; 极简安装流程优化
DisableWelcomePage=yes
DisableDirPage=no
DisableProgramGroupPage=yes
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

; 🚀 系统运行库 (可选：如果需要静默安装，请确保目录下有此文件)
Source: "installer_assets\VC_redist.x64.exe"; DestDir: "{tmp}"; Flags: ignoreversion deleteafterinstall nocompression; Check: not VC2015RedistInstalled

[Icons]
Name: "{group}\Lightning"; Filename: "{app}\lightning.exe"
Name: "{group}\{cm:UninstallProgram,Lightning}"; Filename: "{uninstallexe}"
Name: "{commondesktop}\Lightning"; Filename: "{app}\lightning.exe"; Tasks: desktopicon

[Run]
; 安装系统运行库 (如果缺失)
Filename: "{tmp}\VC_redist.x64.exe"; Parameters: "/quiet /norestart"; Check: not VC2015RedistInstalled; StatusMsg: "正在安装系统运行库 (VC++ 2015-2022)，请稍候..."
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

function InitializeSetup(): Boolean;
begin
  Result := True;
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

