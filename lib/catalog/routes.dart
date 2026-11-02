import 'package:flutter/material.dart';

import '../boot/boot_page.dart';
import '../brand.dart';
import '../site_mode.dart';
import '../theme.dart';
import 'catalog_page.dart';
import 'distro.dart';
import 'distro_page.dart';

Route<dynamic> catalogRoute(RouteSettings s, Catalog catalog) {
  final seg = (Uri.tryParse(s.name ?? '')?.pathSegments ?? const <String>[]).where((e) => e.isNotEmpty).toList();
  Widget body;
  if (seg.length == 1 && seg[0] == 'distros') {
    body = Builder(
      builder: (context) => Scaffold(
        backgroundColor: kBg,
        appBar: const SiteBar(page: 'Dağıtımlar', maxWidth: 1180, padding: 24),
        body: CatalogPage(catalog: catalog, onOpen: (d) => Navigator.pushNamed(context, '/distros/${d.id}')),
      ),
    );
  } else if (seg.length == 1 && seg[0] == 'boot') {
    // Only the desktop app can change the boot order; the website has no such page.
    body = Builder(builder: (context) => SiteMode.isWeb(context) ? const _NotFound() : const BootPage());
  } else {
    final d = seg.length == 2 && seg[0] == 'distros' ? catalog.byId(seg[1]) : null;
    body = d != null ? DistroPage(distro: d) : const _NotFound();
  }
  return MaterialPageRoute(settings: s, builder: (_) => body);
}

class _NotFound extends StatelessWidget {
  const _NotFound();
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: kBg,
        appBar: const SiteBar(page: 'Bulunamadı'),
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Böyle bir sayfa yok.', style: TextStyle(color: kText, fontSize: 18)),
            const SizedBox(height: 12),
            TextButton(onPressed: () => Navigator.pushReplacementNamed(context, '/distros'), child: const Text('Dağıtımlara dön')),
          ]),
        ),
      );
}
