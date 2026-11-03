import 'distro.dart';

enum Host { windows, linux, macM1M2, macOther }

String? hostKey(Host h) => const {Host.windows: 'windows', Host.linux: 'linux', Host.macM1M2: 'mac-m1m2'}[h];

class SupportEntry {
  final bool supported;
  final String reason;
  const SupportEntry(this.supported, this.reason);
}

SupportEntry supportFor(Host host, DistroFamily guest) {
  switch (host) {
    case Host.windows:
      return SupportEntry(
        true,
        guest == DistroFamily.linux
            ? 'Windows bilgisayarda Linux, Windows yanına çift önyükleme olarak kurulabilir.'
            : 'Windows bilgisayarda ikinci bir Windows, ayrı bir bölüme çift önyükleme olarak kurulabilir.',
      );
    case Host.linux:
      return guest == DistroFamily.windows
          ? const SupportEntry(true, 'Linux bilgisayarda Windows, ayrı bir bölüme çift önyükleme olarak kurulabilir.')
          : const SupportEntry(true, 'Linux bilgisayarda başka bir Linux, ISO dosyasından bir GRUB girişiyle açılıp boş alana kurulabilir (bölüm küçültülmez).');
    case Host.macM1M2:
      return guest == DistroFamily.linux
          ? const SupportEntry(true, 'Apple Silicon Mac için Asahi Linux ile Linux, macOS yanına kurulabilir.')
          : const SupportEntry(false, 'Apple Silicon Mac\'lerde Windows yanına kurulamaz: Boot Camp yalnızca Intel Mac\'lerde vardı ve Windows\'un Apple Silicon üzerinde yerel çift önyüklemesi yok.');
    case Host.macOther:
      return guest == DistroFamily.linux
          ? const SupportEntry(false, 'Asahi Linux yalnızca M1/M2 Apple Silicon Mac\'leri destekler; diğer Mac\'lerde bu yöntem çalışmaz.')
          : const SupportEntry(false, 'BesideOS bu Mac modellerinde Windows kurulumunu desteklemiyor.');
  }
}

const List<MapEntry<String, SupportEntry>> unsupportedTargets = [
  MapEntry(
    'macOS (herhangi bir sistemin yanına)',
    SupportEntry(false, 'macOS lisansı yalnızca Apple donanımında çalışmasına izin verir; Apple dışı donanıma veya başka bir sistemin yanına kurulması desteklenmez.'),
  ),
  MapEntry(
    'Windows (Apple Silicon Mac yanına)',
    SupportEntry(false, 'Boot Camp yalnızca Intel Mac\'lerde vardı; Apple Silicon Mac\'lerde Windows\'u yanına kuracak bir yöntem yok.'),
  ),
];
