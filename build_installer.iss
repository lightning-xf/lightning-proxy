; Lightning Inno Setup Script
; Version: 1.0.0
; Author: Lightning Team

[Setup]
AppId={{9F8E7D6C-5B4A-4D3E-BF21-C0B9A8F7E6D5}
AppName=Lightning
AppVersion=1.0.2
AppPublisher=Lightning Team
DefaultDirName={autopf}\LightningVPN
DefaultGroupName=Lightning
AllowNoIcons=yes
; 架构要求
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
; 运行锁（防止安装时程序正在运行）
AppMutex=lightning_vpn_instance_lock
; 本地化设置
LanguageDetectionMethod=uilanguage
ShowLanguageDialog=yes
; 输出配置
OutputDir=installer_build
OutputBaseFilename=LightningVPN_Setup_v1.0.2
Compression=lzma2/ultra64
InternalCompressLevel=ultra
SolidCompression=yes
WizardStyle=modern
; 元数据
VersionInfoVersion=1.0.2
VersionInfoDescription=Lightning VPN Installer
; 图标配置
SetupIconFile=windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\lightning.exe
; 管理员权限要求（加载 wintun.dll 驱动及修改系统代理必需）
PrivilegesRequired=admin
; 覆盖安装时自动关闭运行中的程序，防止文件锁死
CloseApplications=yes
CloseApplicationsFilter=*.exe

[Languages]
Name: "en"; MessagesFile: "compiler:Default.isl"
Name: "zh"; MessagesFile: "installer_assets\ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; Flutter Release 产物
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; 核心依赖
Source: "assets\windows\wintun.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "assets\windows\xray-core.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "assets\windows\geoip.dat"; DestDir: "{app}"; Flags: ignoreversion
Source: "assets\windows\geosite.dat"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\Lightning"; Filename: "{app}\lightning.exe"
Name: "{group}\{cm:UninstallProgram,Lightning}"; Filename: "{uninstallexe}"
Name: "{commondesktop}\Lightning"; Filename: "{app}\lightning.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\lightning.exe"; Description: "{cm:LaunchProgram,Lightning}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; 清理日志、临时文件、用户配置以及可能残留的驱动
Type: filesandordirs; Name: "{app}\logs"
Type: files; Name: "{app}\*.log"
Type: files; Name: "{app}\config.json"
Type: files; Name: "{app}\wintun.dll"
Type: filesandordirs; Name: "{app}\data"
; 彻底清理安装目录（可选，慎用，确保不会删错用户数据）
; Type: filesandordirs; Name: "{app}"

[Code]
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  ResultCode: Integer;
begin
  if CurUninstallStep = usUninstall then
  begin
    // 1. 卸载前强制停止内核进程，防止文件占用
    Exec('taskkill', '/F /IM xray-core.exe /T', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  end;
  
  if CurUninstallStep = usPostUninstall then
  begin
    // 2. 清理开机自启注册表项
    RegDeleteValue(HKEY_CURRENT_USER, 'Software\Microsoft\Windows\CurrentVersion\Run', 'Lightning');
    // 3. 尝试清理系统代理（自愈）
    if RegValueExists(HKEY_CURRENT_USER, 'Software\Microsoft\Windows\CurrentVersion\Internet Settings', 'ProxyEnable') then
    begin
      RegWriteDWordValue(HKEY_CURRENT_USER, 'Software\Microsoft\Windows\CurrentVersion\Internet Settings', 'ProxyEnable', 0);
    end;
  end;
end;
