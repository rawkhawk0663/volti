; Installationsprogramm für Volti (Inno Setup). Wird beim Build erzeugt:
;   iscc /DAppVersion=0.1.50 windows\installer\volti.iss
; Volti wird nur für den eigenen Benutzer installiert (keine Admin-Rechte nötig),
; in %LOCALAPPDATA%\Programs\Volti. Dort darf sich Volti selbst aktualisieren.
; Die Noten liegen woanders (%APPDATA%\Volti) und bleiben beim Deinstallieren.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

[Setup]
AppId={{6B2D8C1E-5F7A-4E39-9C1B-3A8E0D7F4B21}
AppName=Volti
AppVersion={#AppVersion}
AppVerName=Volti {#AppVersion}
AppPublisher=Volti
DefaultDirName={localappdata}\Programs\Volti
DisableDirPage=yes
DefaultGroupName=Volti
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=..\..\build\installer
OutputBaseFilename=Volti-Setup
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\Volti.exe
UninstallDisplayName=Volti
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern
ShowLanguageDialog=no
LanguageDetectionMethod=uilanguage
CloseApplications=force
RestartApplications=no

[Languages]
; Sprache nach Windows: Deutsch (Schweizer Schreibweise) oder Englisch.
Name: "de"; MessagesFile: "German-CH.isl"
Name: "en"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Volti"; Filename: "{app}\Volti.exe"
Name: "{autodesktop}\Volti"; Filename: "{app}\Volti.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\Volti.exe"; Description: "{cm:LaunchProgram,Volti}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Programmordner ganz wegräumen (auch alte Dateien von Updates). Die Noten
; liegen nicht hier und bleiben erhalten.
Type: filesandordirs; Name: "{app}"
