; PixelLab Studio — Windows installer (Inno Setup 6).
;
; Built by build.ps1, which passes the defines below on the ISCC command line.
; Per-user install: no admin, everything under %LOCALAPPDATA%\Programs and
; HKCU, so the future auto-updater can run this silently without UAC:
;
;   Setup.exe /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /CLOSEAPPLICATIONS /RELAUNCH
;
; /RELAUNCH is ours (see [Code]): start the app again after a silent install.

#ifndef AppVersion
  #error AppVersion must be defined (semver, e.g. 1.7.0-alpha.3)
#endif
#ifndef AppVersionNumeric
  #error AppVersionNumeric must be defined (4-part, e.g. 1.7.0.3)
#endif
#ifndef SourceDir
  #error SourceDir must point at the Godot Windows export folder
#endif
#ifndef OutputDir
  #define OutputDir "..\..\.artifacts\installer\windows"
#endif

#define AppName "PixelLab Studio"
#define AppExeName "PixelLab Studio.exe"
#define AppPublisher "Weeb Labs"
#define AppRepoURL "https://github.com/WeebLabs/PixelLabStudio"
#define AvatarProgId "PixelLabStudio.Avatar"

[Setup]
; NEVER change AppId: upgrades, the uninstall entry and the updater key off it.
AppId={{1A865213-A4D3-4225-A8BE-7CEC90BD90F9}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppRepoURL}
AppSupportURL={#AppRepoURL}/issues
AppUpdatesURL={#AppRepoURL}/releases
VersionInfoVersion={#AppVersionNumeric}
VersionInfoProductVersion={#AppVersionNumeric}
VersionInfoProductTextVersion={#AppVersion}
PrivilegesRequired=lowest
; With PrivilegesRequired=lowest, {autopf} is %LOCALAPPDATA%\Programs.
DefaultDirName={autopf}\{#AppName}
DisableDirPage=auto
DisableProgramGroupPage=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
OutputDir={#OutputDir}
OutputBaseFilename=PixelLabStudio-v{#AppVersion}-Windows-x64-Setup
SetupIconFile=..\..\finalIcon.ico
UninstallDisplayIcon={app}\{#AppExeName}
UninstallDisplayName={#AppName}
WizardStyle=modern
Compression=lzma2/max
SolidCompression=yes
ChangesAssociations=yes
; Close a running copy (Restart Manager) instead of failing on locked files.
CloseApplications=yes
RestartApplications=no

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[InstallDelete]
; Engine and extension DLLs are replaced wholesale each version so a library
; a newer build drops doesn't linger and get loaded.
Type: files; Name: "{app}\*.dll"
Type: filesandordirs; Name: "{app}\x86_64"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Registry]
; .pixlab -> PixelLabStudio.Avatar (HKA = HKCU\Software\Classes for a per-user install)
Root: HKA; Subkey: "Software\Classes\.pixlab"; ValueType: string; ValueName: ""; ValueData: "{#AvatarProgId}"; Flags: uninsdeletevalue uninsdeletekeyifempty
Root: HKA; Subkey: "Software\Classes\.pixlab\OpenWithProgids"; ValueType: string; ValueName: "{#AvatarProgId}"; ValueData: ""; Flags: uninsdeletevalue uninsdeletekeyifempty
Root: HKA; Subkey: "Software\Classes\{#AvatarProgId}"; ValueType: string; ValueName: ""; ValueData: "PixelLab Avatar"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\{#AvatarProgId}\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: """{app}\{#AppExeName}"",0"
Root: HKA; Subkey: "Software\Classes\{#AvatarProgId}\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#AppExeName}"" ""%1"""
; Lists the app under "Open with" for .pixlab files.
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExeName}\SupportedTypes"; ValueType: string; ValueName: ".pixlab"; ValueData: ""; Flags: uninsdeletekey
; Install marker: lets the app tell an installed copy (self-updates) from the
; portable zip (links to the release page instead).
Root: HKA; Subkey: "Software\{#AppName}"; ValueType: string; ValueName: "InstallDir"; ValueData: "{app}"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\{#AppName}"; ValueType: string; ValueName: "Version"; ValueData: "{#AppVersion}"

[Run]
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent
Filename: "{app}\{#AppExeName}"; Flags: nowait; Check: ShouldRelaunch

[Code]
function ShouldRelaunch: Boolean;
begin
  Result := WizardSilent and (Pos('/RELAUNCH', UpperCase(GetCmdTail)) > 0);
end;
