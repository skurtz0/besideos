import 'dart:io';

/// The language the person picked in the Windows installer. The installer writes its code (e.g. "de", "pt-BR") to
/// install_lang.txt next to the program; null when the file is missing, as in a build run from source.
String? installedLangCode() {
  try {
    final dir = File(Platform.resolvedExecutable).parent.path;
    final f = File('$dir${Platform.pathSeparator}install_lang.txt');
    if (!f.existsSync()) return null;
    final code = f.readAsStringSync().trim();
    return code.isEmpty ? null : code;
  } catch (_) {
    return null;
  }
}
