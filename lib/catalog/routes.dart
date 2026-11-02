import 'package:flutter/material.dart';

import '../brand.dart';
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
        appBar: const SiteBar(page: 'Dağıtımlar'),
        body: CatalogPage(catalog: catalog, onOpen: (d) => Navigator.pushNamed(context, '/distros/${d.id}')),
      ),
    );
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
            const Text('Böyle bir dağıtım yok.', style: TextStyle(color: kText, fontSize: 18)),
            const SizedBox(height: 12),
            TextButton(onPressed: () => Navigator.pushReplacementNamed(context, '/distros'), child: const Text('Dağıtımlara dön')),
          ]),
        ),
      );
}
