import 'distro.dart';

enum Host { windows, linux }

String? hostKey(Host h) => const {Host.windows: 'windows', Host.linux: 'linux'}[h];

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
  }
}
