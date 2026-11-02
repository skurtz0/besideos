import 'dart:io';

/// The scripts and the planner binary the installer drives.
class Engine {
  const Engine({required this.probe, required this.apply, required this.inspect, required this.plan, this.boot});
  final File probe;
  final File apply;
  final File inspect;
  final File plan;

  /// Lists the installed systems and chooses which one starts next. Optional: older bundles lack it.
  final File? boot;

  bool get complete => probe.existsSync() && apply.existsSync() && inspect.existsSync() && plan.existsSync();
}

const _planExe = 'besideos-plan.exe';

/// Release layout: `engine/` next to the app executable (see tool/build_windows.ps1).
/// Development layout: walk up from the executable to the repository root.
Engine? locateEngine({String? exePath}) {
  final start = File(exePath ?? Platform.resolvedExecutable).parent;
  final sep = Platform.pathSeparator;

  final bundled = Directory('${start.path}${sep}engine');
  final e = Engine(
    probe: File('${bundled.path}${sep}collect-host-facts.ps1'),
    apply: File('${bundled.path}${sep}apply-plan.ps1'),
    inspect: File('${bundled.path}${sep}inspect-iso.ps1'),
    plan: File('${bundled.path}$sep$_planExe'),
    boot: File('${bundled.path}${sep}boot-entries.ps1'),
  );
  if (e.complete) return e;

  var dir = start;
  for (var i = 0; i < 8; i++) {
    final scripts = '${dir.path}${sep}probe${sep}windows';
    if (File('$scripts${sep}collect-host-facts.ps1').existsSync()) {
      for (final profile in const ['release', 'debug']) {
        final dev = Engine(
          probe: File('$scripts${sep}collect-host-facts.ps1'),
          apply: File('$scripts${sep}apply-plan.ps1'),
          inspect: File('$scripts${sep}inspect-iso.ps1'),
          plan: File('${dir.path}${sep}core${sep}target$sep$profile$sep$_planExe'),
          boot: File('$scripts${sep}boot-entries.ps1'),
        );
        if (dev.complete) return dev;
      }
      return null;
    }
    final up = dir.parent;
    if (up.path == dir.path) break;
    dir = up;
  }
  return null;
}
