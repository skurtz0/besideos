import 'dart:io';

/// The scripts and the planner binary the installer drives.
class Engine {
  const Engine({required this.probe, required this.apply, required this.inspect, required this.plan, this.grub});

  /// Linux host: the single GRUB loopback script does inspecting, preparing and undoing (probe/linux/besideos-grub.sh).
  /// The four Windows slots then all point at it so the rest of the code needs no special case.
  Engine.linux(File script)
      : probe = script,
        apply = script,
        inspect = script,
        plan = script,
        grub = script;
  final File? grub;
  bool get isLinux => grub != null;

  final File probe;
  final File apply;
  final File inspect;
  final File plan;

  bool get complete => probe.existsSync() && apply.existsSync() && inspect.existsSync() && plan.existsSync();
}

const _planExe = 'besideos-plan.exe';

/// Release layout: `engine/` next to the app executable (see tool/build_windows.ps1).
/// Development layout: walk up from the executable to the repository root.
Engine? locateEngine({String? exePath}) {
  final start = File(exePath ?? Platform.resolvedExecutable).parent;
  final sep = Platform.pathSeparator;

  // Tests pass an explicit exePath to exercise the Windows layout.
  if (exePath == null && Platform.isLinux) {
    var dir = start;
    for (var i = 0; i < 8; i++) {
      for (final rel in const ['engine/besideos-grub.sh', 'probe/linux/besideos-grub.sh']) {
        final f = File('${dir.path}/$rel');
        if (f.existsSync()) return Engine.linux(f);
      }
      final up = dir.parent;
      if (up.path == dir.path) break;
      dir = up;
    }
    return null;
  }

  final bundled = Directory('${start.path}${sep}engine');
  final e = Engine(
    probe: File('${bundled.path}${sep}collect-host-facts.ps1'),
    apply: File('${bundled.path}${sep}apply-plan.ps1'),
    inspect: File('${bundled.path}${sep}inspect-iso.ps1'),
    plan: File('${bundled.path}$sep$_planExe'),
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
