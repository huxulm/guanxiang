; 观象 Windows 安装程序（Inno Setup 7）。
;
; 先构建：flutter build windows --release
; 再打包："C:\Program Files\Inno Setup 7\ISCC.exe" windows\installer.iss   （在 app/ 目录下）
; 输出：build\windows\installer\guanxiang-<版本>-windows-x64-setup.exe
;
; 版本号取自 guanxiang.exe 的 ProductVersion（即 pubspec.yaml 的 version），不用手改。
; 本文件含中文，必须保存为带 BOM 的 UTF-8。

#define SourceDir "..\build\windows\x64\runner\Release"
#define AppExe "guanxiang.exe"
#define FullVersion GetStringFileInfo(SourceDir + "\" + AppExe, "ProductVersion")
#if Pos("+", FullVersion) > 0
  #define AppVersion Copy(FullVersion, 1, Pos("+", FullVersion) - 1)
#else
  #define AppVersion FullVersion
#endif
#define AppUrl "https://guanx.huxulm.dev"

[Setup]
; AppId 用来识别同一个应用，升级时覆盖安装。不要改。
AppId={{D767CDC0-D7A7-4B2D-8A1B-71F90C08D3CC}
AppName={cm:AppName}
AppVersion={#AppVersion}
AppVerName={cm:AppName} {#AppVersion}
AppPublisher=Guanxiang
AppPublisherURL={#AppUrl}
AppSupportURL={#AppUrl}
AppUpdatesURL={#AppUrl}
VersionInfoVersion={#AppVersion}
VersionInfoProductName=Guanxiang
VersionInfoDescription=Guanxiang Setup
; 默认装到当前用户目录，不需要管理员权限；安装向导里可以改为所有用户
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
DefaultDirName={autopf}\Guanxiang
DisableProgramGroupPage=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
SetupIconFile=runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={cm:AppName}
OutputDir=..\build\windows\installer
OutputBaseFilename=guanxiang-{#AppVersion}-windows-x64-setup
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; 升级或卸载时如果程序正在运行，提示关闭
CloseApplications=yes
RestartApplications=no

[Languages]
; 第一项是默认语言：系统不是中文时用英文
Name: "en"; MessagesFile: "compiler:Default.isl"
Name: "chs"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"

[CustomMessages]
en.AppName=Guanxiang
chs.AppName=观象
en.DeleteUserData=Also delete Guanxiang's settings and caches (location, satellite elements, map tiles)?
chs.DeleteUserData=是否同时删除观象的设置和缓存（观测位置、卫星根数、地图瓦片）？

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{cm:AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{cm:AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{cm:AppName}}"; Flags: nowait postinstall skipifsilent

[Code]
// 卸载后询问是否删除用户数据。数据目录由 path_provider 按 exe 的 CompanyName/ProductName 决定。
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if (CurUninstallStep = usPostUninstall) and (not UninstallSilent) then
  begin
    if MsgBox(CustomMessage('DeleteUserData'), mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES then
    begin
      DelTree(ExpandConstant('{userappdata}\cn.ac.xao\guanxiang'), True, True, True);
      DelTree(ExpandConstant('{localappdata}\cn.ac.xao\guanxiang'), True, True, True);
    end;
  end;
end;
