; Inno Setup script — packages the flutter build windows --release output
; into a real Windows installer (Start Menu shortcut, uninstaller entry).
; Built by aion/.github/workflows/release.yml via:
;   ISCC.exe /DAppVersion=<version> windows\installer\aion.iss
; AppVersion is never hardcoded here — it always comes from the CI-supplied
; command-line define, sourced from the release git tag.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

[Setup]
AppId={{B6C6C6C1-6B60-4B2A-9C3A-6E6E6C6C6C6C}
AppName=Aion
AppVersion={#AppVersion}
AppPublisher=Aion
DefaultDirName={autopf}\Aion
DefaultGroupName=Aion
UninstallDisplayIcon={app}\aion.exe
OutputDir=Output
OutputBaseFilename=Aion-Setup-{#AppVersion}
Compression=lzma
SolidCompression=yes
WizardStyle=modern
SetupIconFile=..\runner\resources\app_icon.ico
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{group}\Aion"; Filename: "{app}\aion.exe"
Name: "{group}\Uninstall Aion"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Aion"; Filename: "{app}\aion.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\aion.exe"; Description: "Launch Aion"; Flags: nowait postinstall skipifsilent
