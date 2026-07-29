#ifndef ProductVersion
  #define ProductVersion "0.3.0-beta"
#endif
#ifndef NumericVersion
  #define NumericVersion "0.3.0.0"
#endif
#ifndef PayloadRoot
  #error PayloadRoot must point to the prepared release directory.
#endif
#ifndef ProjectRoot
  #error ProjectRoot must point to the source repository.
#endif
#ifndef OutputDir
  #error OutputDir must point to the release output directory.
#endif

[Setup]
AppId={{5C836C8E-D328-4A2D-A271-30FBB9D39D01}
AppName=Codex Pet Dock
AppVersion={#ProductVersion}
AppVerName=Codex Pet Dock {#ProductVersion}
AppPublisher=Codex Pet Dock contributors
AppPublisherURL=https://github.com/hjxccc/codex-pet-dock
AppSupportURL=https://github.com/hjxccc/codex-pet-dock/issues
AppUpdatesURL=https://github.com/hjxccc/codex-pet-dock/releases
VersionInfoVersion={#NumericVersion}
VersionInfoCompany=Codex Pet Dock contributors
VersionInfoDescription=Quota dock and custom bases for the Codex desktop pet
VersionInfoProductName=Codex Pet Dock
VersionInfoProductVersion={#NumericVersion}
DefaultDirName={localappdata}\Programs\CodexPetDock
DefaultGroupName=Codex Pet Dock
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutputDir}
OutputBaseFilename=CodexPetDock-Setup-{#ProductVersion}
SetupIconFile={#ProjectRoot}\assets\branding\codex-pet-dock.ico
UninstallDisplayIcon={app}\assets\branding\codex-pet-dock.ico
LicenseFile={#ProjectRoot}\LICENSE
InfoBeforeFile={#ProjectRoot}\NOTICE.md
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
CloseApplications=no
RestartApplications=no
SetupLogging=yes
MinVersion=10.0.22000
UsePreviousTasks=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "startup"; Description: "{cm:AutoStartProgram,Codex Pet Dock}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: checkedonce
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#PayloadRoot}\*"; DestDir: "{app}"; Excludes: "tests\*,packaging\*,Install-Preview.cmd"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#ProjectRoot}\packaging\Stop-CodexPetDock.ps1"; DestDir: "{app}\tools"; Flags: ignoreversion
Source: "{#ProjectRoot}\packaging\Stop-CodexPetDock.ps1"; Flags: dontcopy

[Icons]
Name: "{group}\Codex Pet Dock"; Filename: "{sys}\wscript.exe"; Parameters: """{app}\CodexPetDock.vbs"""; WorkingDir: "{app}"; IconFilename: "{app}\assets\branding\codex-pet-dock.ico"
Name: "{group}\Uninstall Codex Pet Dock"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Codex Pet Dock"; Filename: "{sys}\wscript.exe"; Parameters: """{app}\CodexPetDock.vbs"""; WorkingDir: "{app}"; IconFilename: "{app}\assets\branding\codex-pet-dock.ico"; Tasks: desktopicon

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "CodexPetDock"; ValueData: """{sys}\wscript.exe"" ""{app}\CodexPetDock.vbs"""; Tasks: startup; Flags: uninsdeletevalue

[Run]
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy RemoteSigned -File ""{app}\tools\Stop-CodexPetDock.ps1"" -InstallRoot ""{app}"""; Flags: runhidden waituntilterminated
Filename: "{sys}\wscript.exe"; Parameters: """{app}\CodexPetDock.vbs"""; Description: "{cm:LaunchProgram,Codex Pet Dock}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy RemoteSigned -File ""{app}\tools\Stop-CodexPetDock.ps1"" -InstallRoot ""{app}"""; Flags: runhidden waituntilterminated; RunOnceId: "StopCodexPetDock"

[InstallDelete]
Type: filesandordirs; Name: "{app}\*"

[Code]
function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  ResultCode: Integer;
  StopScript: String;
  StopArguments: String;
begin
  Result := '';
  ExtractTemporaryFile('Stop-CodexPetDock.ps1');
  StopScript := ExpandConstant('{tmp}\Stop-CodexPetDock.ps1');
  StopArguments :=
    '-NoProfile -ExecutionPolicy RemoteSigned -File "' +
    StopScript +
    '" -InstallRoot "' +
    ExpandConstant('{app}') +
    '"';
  if not Exec(
    ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
    StopArguments,
    '',
    SW_HIDE,
    ewWaitUntilTerminated,
    ResultCode
  ) then
    Result := 'Could not stop the existing Codex Pet Dock process.'
  else if ResultCode <> 0 then
    Result := 'The existing Codex Pet Dock process could not be stopped.';
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssInstall then
  begin
    { Remove the uninstall registration created by the old Preview script.
      Inno Setup creates and owns its own versioned uninstall entry. }
    RegDeleteKeyIncludingSubkeys(
      HKEY_CURRENT_USER,
      'Software\Microsoft\Windows\CurrentVersion\Uninstall\CodexPetDock'
    );
  end;
end;
