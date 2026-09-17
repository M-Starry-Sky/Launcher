; 星穹次元启动器 — 企业式图形安装向导（Inno Setup 6）
; 含：欢迎页 / 许可协议 / 安装目录 / 附加任务 / 就绪确认 / 进度 / 完成页
; 品牌：Setup 图标 + 向导左右侧 Logo 图

#define MyAppName "星穹次元启动器"
#define MyAppVersion "0.2.4"
#define MyAppPublisher "星穹次元 / M-Starry-Sky"
#define MyAppURL "https://github.com/M-Starry-Sky/Launcher"
#define MyAppExeName "xingqiong_launcher.exe"

[Setup]
AppId={{A7E3C2D1-9F40-4B8E-8C11-7E2F0B6A1D03}}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}/issues
AppUpdatesURL={#MyAppURL}/releases
DefaultDirName={autopf}\XingqiongLauncher
DefaultGroupName={#MyAppName}
AllowNoIcons=yes
OutputDir=..\dist
OutputBaseFilename=XingqiongLauncher-{#MyAppVersion}-Windows-x64-Setup
SetupIconFile=branding\setup.ico
WizardImageFile=branding\wizard_image.bmp
WizardSmallImageFile=branding\wizard_small.bmp
WizardStyle=modern
WizardSizePercent=120
Compression=lzma2/ultra64
SolidCompression=yes
LZMAUseSeparateProcess=yes
PrivilegesRequired=admin
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
DisableProgramGroupPage=no
DisableWelcomePage=no
DisableDirPage=no
DisableReadyPage=no
DisableFinishedPage=no
AlwaysShowDirOnReadyPage=yes
AlwaysShowGroupOnReadyPage=yes
ShowLanguageDialog=yes
LicenseFile=license_zh.txt
InfoBeforeFile=welcome_zh.txt
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppName}
VersionInfoVersion={#MyAppVersion}.0
VersionInfoCompany={#MyAppPublisher}
VersionInfoProductName={#MyAppName}
VersionInfoDescription={#MyAppName} 安装程序
VersionInfoCopyright=Copyright (C) 2026 {#MyAppPublisher}
AppMutex=XingqiongLauncherSetupMutex
CloseApplications=yes
RestartApplications=no
ChangesAssociations=no

[Languages]
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Messages]
chinesesimplified.WelcomeLabel1=欢迎使用「星穹次元启动器」安装向导
chinesesimplified.WelcomeLabel2=本向导将引导您在计算机上安装 {#MyAppName} {#MyAppVersion}。%n%n建议在继续之前关闭其他应用程序，这样安装程序才能更新相关系统文件，而无需重新启动计算机。%n%n点击「下一步」继续。
chinesesimplified.FinishedHeadingLabel=完成「星穹次元启动器」安装向导
chinesesimplified.FinishedLabelNoIcons=安装程序已在计算机中安装好 {#MyAppName}。点击「完成」退出安装向导。
chinesesimplified.ClickNext=点击「下一步」继续，或点击「取消」退出安装向导。
chinesesimplified.SelectDirDesc=请选择 {#MyAppName} 的安装位置
chinesesimplified.SelectDirLabel3=安装程序将把 {#MyAppName} 安装到下列文件夹。
chinesesimplified.WizardReady=准备安装
chinesesimplified.ReadyLabel1=安装程序已准备好开始安装 {#MyAppName}。
chinesesimplified.InstallingLabel=正在安装 {#MyAppName}，请稍候…

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "附加图标："; Flags: checkedonce
Name: "startmenuicon"; Description: "创建开始菜单快捷方式"; GroupDescription: "附加图标："; Flags: checkedonce

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; 附带品牌 Logo，便于用户识别
Source: "..\assets\images\logo.png"; DestDir: "{app}\branding"; Flags: ignoreversion
Source: "branding\setup.ico"; DestDir: "{app}\branding"; Flags: ignoreversion

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\branding\setup.ico"; Tasks: startmenuicon
Name: "{group}\卸载 {#MyAppName}"; Filename: "{uninstallexe}"; Tasks: startmenuicon
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\branding\setup.ico"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "立即运行 星穹次元启动器"; Flags: nowait postinstall skipifsilent unchecked

[UninstallDelete]
Type: filesandordirs; Name: "{app}\branding"

[Code]
procedure InitializeWizard();
begin
  WizardForm.WelcomeLabel1.Caption := '欢迎安装 星穹次元启动器';
  WizardForm.WelcomeLabel2.Caption :=
    '本安装向导将引导您完成「星穹次元启动器」{#MyAppVersion} 的安装。'#13#10#13#10
    + '安装过程包括：'#13#10
    + '  · 阅读软件许可协议'#13#10
    + '  · 选择安装目录'#13#10
    + '  · 创建开始菜单 / 桌面快捷方式'#13#10
    + '  · 复制程序文件并完成配置'#13#10#13#10
    + '建议关闭正在运行的旧版启动器后再继续。'#13#10#13#10
    + '点击「下一步」继续。';
end;
