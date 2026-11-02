import 'dart:convert';
import 'dart:io';

class RunResult {
  const RunResult(this.exitCode, this.stdout, this.stderr);
  final int exitCode;
  final String stdout;
  final String stderr;
}

/// Exit code of an elevated run when the user dismisses the UAC prompt (ERROR_CANCELLED).
const kElevationDeclined = 1223;

abstract class ProcessRunner {
  Future<RunResult> exec(String exe, List<String> args);

  /// Runs a PowerShell script file; `elevated` shows the UAC prompt and returns the script's exit code.
  Future<RunResult> script(File script, List<String> args, {bool elevated = false});
}

const _utf8 = Utf8Codec(allowMalformed: true);

class SystemProcessRunner implements ProcessRunner {
  @override
  Future<RunResult> exec(String exe, List<String> args) async {
    final r = await Process.run(exe, args, stdoutEncoding: _utf8, stderrEncoding: _utf8);
    return RunResult(r.exitCode, '${r.stdout}', '${r.stderr}');
  }

  @override
  Future<RunResult> script(File script, List<String> args, {bool elevated = false}) {
    const base = ['-NoProfile', '-ExecutionPolicy', 'Bypass'];
    if (!elevated) return exec('powershell.exe', [...base, '-File', script.path, ...args]);
    return exec('powershell.exe', [...base, '-EncodedCommand', encodePowerShell(elevatedCommand(script.path, args))]);
  }
}

String _psArg(String a) {
  if (a.contains('"') || a.contains('\n') || a.contains('\r')) {
    throw ArgumentError('Unsafe argument: $a');
  }
  // Start-Process joins the array with spaces and adds no quoting of its own.
  final q = a.isEmpty || a.contains(RegExp(r'\s')) ? '"$a"' : a;
  return "'${q.replaceAll("'", "''")}'";
}

/// PowerShell source that re-launches `script` elevated, waits, and exits with its exit code.
String elevatedCommand(String script, List<String> args) {
  final list = ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', script, ...args].map(_psArg).join(',');
  return 'try { \$p = Start-Process -FilePath powershell.exe -Verb RunAs -Wait -PassThru '
      '-WindowStyle Hidden -ArgumentList @($list); exit \$p.ExitCode } catch { exit $kElevationDeclined }';
}

String encodePowerShell(String s) {
  final b = <int>[];
  for (final u in s.codeUnits) {
    b..add(u & 0xff)..add(u >> 8);
  }
  return base64.encode(b);
}
