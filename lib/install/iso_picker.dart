import 'dart:convert';
import 'dart:io';

import 'process_runner.dart';

/// An ISO file found lying around on this computer.
class LocalIso {
  const LocalIso(this.file, this.bytes, this.modified);
  final File file;
  final int bytes;
  final DateTime modified;

  String get name => file.uri.pathSegments.last;
}

bool _isIso(String path) => path.toLowerCase().endsWith('.iso');

/// Shows the Windows "open file" dialog for ISO files. Returns null when the person cancels.
/// The path comes back base64-encoded so Turkish letters in folder names survive the console code page.
Future<File?> pickIsoFile(ProcessRunner runner) async {
  const cmd = r'''
$ProgressPreference = 'SilentlyContinue'
Add-Type -AssemblyName System.Windows.Forms
$f = New-Object System.Windows.Forms.Form
$f.TopMost = $true; $f.ShowInTaskbar = $false; $f.Opacity = 0; $f.StartPosition = 'CenterScreen'
$f.Show()
$d = New-Object System.Windows.Forms.OpenFileDialog
$d.Filter = 'ISO (*.iso)|*.iso'
$d.Title = 'Kurmak istedigin ISO dosyasini sec'
$dl = Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads'
if (Test-Path $dl) { $d.InitialDirectory = $dl }
$ok = $d.ShowDialog($f)
$f.Close()
if ($ok -eq [System.Windows.Forms.DialogResult]::OK) { [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($d.FileName)) }
''';
  final r = await runner.exec('powershell.exe', ['-NoProfile', '-STA', '-NonInteractive', '-EncodedCommand', encodePowerShell(cmd)]);
  final out = r.stdout.trim();
  if (r.exitCode != 0 || out.isEmpty) return null;
  try {
    final path = utf8.decode(base64.decode(out.split(RegExp(r'\s+')).last));
    final f = File(path);
    return _isIso(path) && f.existsSync() ? f : null;
  } catch (_) {
    return null;
  }
}

/// ISO files directly inside Downloads, Desktop and Documents, newest first (at most [limit]).
List<LocalIso> findLocalIsos({Map<String, String>? env, int limit = 6, List<Directory>? dirs}) {
  final e = env ?? Platform.environment;
  final home = e['USERPROFILE'] ?? e['HOME'];
  final roots = dirs ??
      [
        if (home != null) ...[
          Directory('$home${Platform.pathSeparator}Downloads'),
          Directory('$home${Platform.pathSeparator}Desktop'),
          Directory('$home${Platform.pathSeparator}Documents'),
        ],
      ];
  final found = <LocalIso>[];
  for (final d in roots) {
    try {
      if (!d.existsSync()) continue;
      for (final x in d.listSync(followLinks: false)) {
        if (x is File && _isIso(x.path)) {
          final s = x.statSync();
          // a real installer image is megabytes, never a few KB of something else named .iso
          if (s.size >= 1 << 20) found.add(LocalIso(x, s.size, s.modified));
        }
      }
    } catch (_) {}
  }
  found.sort((a, b) => b.modified.compareTo(a.modified));
  return found.take(limit).toList();
}
