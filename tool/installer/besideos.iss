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
Name: "turkish"; MessagesFile: "compiler:LanguagesTurkish.isl"
Name: "german"; MessagesFile: "languages\1erman.isl"
Name: "french"; MessagesFile: "languages\1rench.isl"
Name: "spanish"; MessagesFile: "languages\1panish.isl"
Name: "italian"; MessagesFile: "languages\1talian.isl"
Name: "brazilianportuguese"; MessagesFile: "languages\1razilianPortuguese.isl"
Name: "russian"; MessagesFile: "languages\1ussian.isl"
Name: "chinesesimplified"; MessagesFile: "languages\1hineseSimplified.isl"
Name: "chinesetraditional"; MessagesFile: "languages\1hineseTraditional.isl"
Name: "japanese"; MessagesFile: "languages\1apanese.isl"
Name: "korean"; MessagesFile: "languages\1orean.isl"
Name: "arabic"; MessagesFile: "languages\1rabic.isl"
Name: "polish"; MessagesFile: "languages\1olish.isl"
Name: "vietnamese"; MessagesFile: "languages\1ietnamese.isl"
Name: "malaysian"; MessagesFile: "languages\1alaysian.isl"
Name: "finnish"; MessagesFile: "languages\1innish.isl"
Name: "estonian"; MessagesFile: "languages\1stonian.isl"
Name: "ukrainian"; MessagesFile: "languages\1krainian.isl"
Name: "hindi"; MessagesFile: "languages\1indi.isl"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{autoprograms}\BesideOS"; Filename: "{app}\BesideOS.exe"
Name: "{autodesktop}\BesideOS"; Filename: "{app}\BesideOS.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Run]
Filename: "{app}\BesideOS.exe"; Description: "{cm:LaunchProgram,BesideOS}"; Flags: nowait postinstall skipifsilent
