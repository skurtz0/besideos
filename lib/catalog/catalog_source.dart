import 'distro.dart';
import 'remote_catalog_stub.dart' if (dart.library.io) 'remote_catalog_io.dart' as remote;

/// Where the desktop app looks for a newer catalog (the one the website itself ships), so new ISO releases
/// reach installed apps without a new app version.
const kRemoteCatalogUrl = 'https://besideos.com/assets/assets/catalog/catalog.json';

/// The catalog text to use: the fresh one from the website when it is complete and safe, else the bundled one.
/// [fetchRemote] is replaced in tests.
Future<String> loadCatalogJson(
  Future<String> Function() bundled, {
  Future<String?> Function()? fetchRemote,
}) async {
  final bundledJson = await bundled();
  final fresh = await (fetchRemote ?? remote.fetchRemoteCatalog)();
  if (fresh == null) return bundledJson;
  return acceptRemoteCatalog(fresh, Catalog.parse(bundledJson)) ? fresh : bundledJson;
}

/// A downloaded catalog replaces the bundled one only when it parses, lists exactly the distros the bundled one
/// has (new distros bring screenshots and need an app update), and every download and checksum address is https.
bool acceptRemoteCatalog(String json, Catalog bundled) {
  try {
    final c = Catalog.parse(json);
    if (c.distros.length != bundled.distros.length) return false;
    for (final d in bundled.distros) {
      if (c.byId(d.id) == null) return false;
    }
    for (final d in c.distros) {
      final isos = [...d.isos, for (final v in d.variants) ...v.isos];
      for (final i in isos) {
        if (!i.url.startsWith('https://') || !i.checksumUrl.startsWith('https://')) return false;
      }
    }
    return true;
  } on CatalogException {
    return false;
  }
}
