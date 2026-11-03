import 'package:flutter/foundation.dart';

import 'install_controller.dart';

/// Keeps one [InstallController] per distro for as long as the app runs, so leaving a distro's page
/// (to look at other systems) does not cancel its download or forget where it got to.
/// Several systems can be prepared side by side, each with its own GRUB entry.
class InstallSessions extends ChangeNotifier {
  InstallSessions._();
  static final instance = InstallSessions._();

  final _controllers = <String, InstallController>{};

  InstallController? obtain(String id, InstallController? Function() create) {
    final have = _controllers[id];
    if (have != null) return have;
    final c = create();
    if (c == null) return null;
    _controllers[id] = c;
    c.addListener(notifyListeners);
    c.download.addListener(notifyListeners);
    return c;
  }

}
