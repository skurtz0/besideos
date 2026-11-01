import 'package:flutter/material.dart';

import '../theme.dart';
import 'catalog_page.dart';
import 'distro.dart';
import 'distro_page.dart';

Route<dynamic> catalogRoute(RouteSettings s, Catalog catalog) {
  final name = s.name ?? '';
  Widget body;
  if (name == '/distros') {
    body = Builder(
      builder: (context) => Scaffold(
        backgroundColor: kBg,
        appBar: AppBar(backgroundColor: kBg, foregroundColor: kText, title: const Text('Dağıtımlar')),
        body: CatalogPage(catalog: catalog, onOpen: (d) => Navigator.pushNamed(context, '/distros/${d.id}')),
      ),
    );
  } else {
    final d = name.startsWith('/distros/') ? catalog.byId(name.substring('/distros/'.length)) : null;
    body = d != null ? DistroPage(distro: d) : const _NotFound();
  }
  return MaterialPageRoute(settings: s, builder: (_) => body);
}

class _NotFound extends StatelessWidget {
  const _NotFound();
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: kBg,
        appBar: AppBar(backgroundColor: kBg, foregroundColor: kText, title: const Text('Bulunamadı')),
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Böyle bir dağıtım yok.', style: TextStyle(color: kText, fontSize: 18)),
            const SizedBox(height: 12),
            TextButton(onPressed: () => Navigator.pushReplacementNamed(context, '/distros'), child: const Text('Dağıtımlara dön')),
          ]),
        ),
      );
}
