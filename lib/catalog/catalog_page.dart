import 'package:flutter/material.dart';

import '../theme.dart';
import 'distro.dart';
import 'support_matrix.dart';

const _hostLabels = {
  Host.windows: 'Windows',
  Host.linux: 'Linux',
  Host.macM1M2: 'Mac M1/M2',
  Host.macOther: 'Diğer Mac',
};

const _hostKeys = {
  Host.windows: 'windows',
  Host.linux: 'linux',
  Host.macM1M2: 'mac-m1m2',
};

class CatalogPage extends StatefulWidget {
  const CatalogPage({super.key, required this.catalog, required this.onOpen});
  final Catalog catalog;
  final void Function(Distro) onOpen;

  @override
  State<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<CatalogPage> {
  DistroFamily? _family; // null = Hepsi
  Host? _host; // null = filtre yok

  List<Distro> get _visible => widget.catalog.distros.where((d) {
        if (_family != null && d.family != _family) return false;
        if (_host == null) return true;
        final key = _hostKeys[_host];
        return key != null && d.hosts.contains(key); // macOther: eşleşme yok
      }).toList();

  @override
  Widget build(BuildContext context) {
    final items = _visible;
    final String? note = _host == Host.macOther
        ? supportFor(Host.macOther, _family ?? DistroFamily.linux).reason
        : null;
    final empty = widget.catalog.distros.isEmpty
        ? 'Katalog boş'
        : (note ?? 'Eşleşen dağıtım yok');
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          const Text('Aile:', style: TextStyle(color: kMuted)),
          for (final f in <DistroFamily?>[null, ...DistroFamily.values])
            ChoiceChip(
              label: Text(f == null ? 'Hepsi' : (f == DistroFamily.linux ? 'Linux' : 'Windows')),
              selected: _family == f,
              onSelected: (_) => setState(() => _family = f),
            ),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          const Text('Ana sistem:', style: TextStyle(color: kMuted)),
          for (final h in Host.values)
            ChoiceChip(
              label: Text(_hostLabels[h]!),
              selected: _host == h,
              onSelected: (on) => setState(() => _host = on ? h : null),
            ),
        ]),
        const SizedBox(height: 16),
        if (items.isEmpty)
          Text(empty, style: const TextStyle(color: kMuted, height: 1.5))
        else
          Wrap(spacing: 12, runSpacing: 12, children: [
            for (final d in items) _DistroCard(distro: d, onTap: () => widget.onOpen(d)),
          ]),
      ]),
    );
  }
}

class _DistroCard extends StatefulWidget {
  const _DistroCard({required this.distro, required this.onTap});
  final Distro distro;
  final VoidCallback onTap;

  @override
  State<_DistroCard> createState() => _DistroCardState();
}

class _DistroCardState extends State<_DistroCard> {
  bool _active = false; // hover veya klavye odağı
  bool _hover = false;
  bool _focus = false;

  void _set({bool? hover, bool? focus}) => setState(() {
        _hover = hover ?? _hover;
        _focus = focus ?? _focus;
        _active = _hover || _focus;
      });

  @override
  Widget build(BuildContext context) {
    final d = widget.distro;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280, minWidth: 0),
      child: Material(
        color: kPanel,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: _active ? kAccent.withAlpha(170) : const Color(0x00000000)),
        ),
        child: InkWell(
          onTap: widget.onTap,
          onHover: (v) => _set(hover: v),
          onFocusChange: (v) => _set(focus: v),
          mouseCursor: SystemMouseCursors.click,
          child: Semantics(
            button: true,
            label: d.name,
            excludeSemantics: true,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(height: 4, color: Color(d.accent)),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(d.name, style: const TextStyle(color: kText, fontSize: 17, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Text(d.tagline, style: const TextStyle(color: kMuted, height: 1.5)),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
