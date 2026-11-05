; Builds BesideOS-Setup.exe from the Windows release folder.
; iscc /DAppVersion=0.1.0 /DSourceDir=C:\path\to\Release tool\installer\besideos.iss
#ifndef AppVersion
  #define AppVersion "0.1.0"
#endif
#ifndef SourceDir
  #error SourceDir is required (the build\windows\x64\runner\Release folder)
#endif

[Setup]
AppId={{6B1B1A2E-5E0F-4F0B-9C58-3A1F7E5D2B44}
AppName=BesideOS
AppVersion={#AppVersion}
AppPublisher=SKURTINATI
AppPublisherURL=https://besideos.com
AppSupportURL=https://github.com/skurtz0/besideos
DefaultDirName={localappdata}\Programs\BesideOS
DefaultGroupName=BesideOS
PrivilegesRequired=lowest
OutputDir=..\..\build\installer
OutputBaseFilename=BesideOS-Setup
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\BesideOS.exe
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
DisableProgramGroupPage=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "turkish"; MessagesFile: "compiler:Languages\Turkish.isl"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{autoprograms}\BesideOS"; Filename: "{app}\BesideOS.exe"
Name: "{autodesktop}\BesideOS"; Filename: "{app}\BesideOS.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Run]
Filename: "{app}\BesideOS.exe"; Description: "{cm:LaunchProgram,BesideOS}"; Flags: nowait postinstall skipifsilent
