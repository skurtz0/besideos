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
; The same 20 languages as the site and the app. Turkish and English ship with Inno Setup; the rest live in tool/installer/languages.
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "turkish"; MessagesFile: "compiler:Languages\Turkish.isl"
Name: "german"; MessagesFile: "languages\German.isl"
Name: "french"; MessagesFile: "languages\French.isl"
Name: "spanish"; MessagesFile: "languages\Spanish.isl"
Name: "italian"; MessagesFile: "languages\Italian.isl"
Name: "brazilianportuguese"; MessagesFile: "languages\BrazilianPortuguese.isl"
Name: "russian"; MessagesFile: "languages\Russian.isl"
Name: "chinesesimplified"; MessagesFile: "languages\ChineseSimplified.isl"
Name: "chinesetraditional"; MessagesFile: "languages\ChineseTraditional.isl"
Name: "japanese"; MessagesFile: "languages\Japanese.isl"
Name: "korean"; MessagesFile: "languages\Korean.isl"
Name: "arabic"; MessagesFile: "languages\Arabic.isl"
Name: "polish"; MessagesFile: "languages\Polish.isl"
Name: "vietnamese"; MessagesFile: "languages\Vietnamese.isl"
Name: "malaysian"; MessagesFile: "languages\Malaysian.isl"
Name: "finnish"; MessagesFile: "languages\Finnish.isl"
Name: "estonian"; MessagesFile: "languages\Estonian.isl"
Name: "ukrainian"; MessagesFile: "languages\Ukrainian.isl"
Name: "hindi"; MessagesFile: "languages\Hindi.isl"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{autoprograms}\BesideOS"; Filename: "{app}\BesideOS.exe"
Name: "{autodesktop}\BesideOS"; Filename: "{app}\BesideOS.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Run]
Filename: "{app}\BesideOS.exe"; Description: "{cm:LaunchProgram,BesideOS}"; Flags: nowait postinstall skipifsilent
