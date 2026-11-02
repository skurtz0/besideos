import 'package:flutter/material.dart';

import '../brand.dart';
import '../theme.dart';
import 'distro.dart';
import 'support_matrix.dart';

const _hostLabels = {
  Host.windows: 'Windows',
  Host.linux: 'Linux',
  Host.macM1M2: 'Mac M1/M2',
  Host.macOther: 'Diğer Mac',
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
        final key = hostKey(_host!);
        // macOther: eşleşme yok; matris reddettiği ana sistem de gösterilmez
        return key != null && supportFor(_host!, d.family).supported && d.hosts.contains(key);
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
    return PageScroll(
      maxWidth: 1180,
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Hangi sistemi kurmak istersin?',
            style: TextStyle(color: kText, fontSize: 28, fontWeight: FontWeight.w800, height: 1.2)),
        const SizedBox(height: 6),
        const Text('Birini seç. Nasıl kurulduğunu sana adım adım gösterelim.',
            style: TextStyle(color: kMuted, fontSize: 16, height: 1.5)),
        const SizedBox(height: 20),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          const Text('Ne tür?', style: TextStyle(color: kMuted)),
          for (final f in <DistroFamily?>[null, ...DistroFamily.values])
            ChoiceChip(
              label: Text(f == null ? 'Hepsi' : (f == DistroFamily.linux ? 'Linux' : 'Windows')),
              selected: _family == f,
              onSelected: (_) => setState(() => _family = f),
            ),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          const Text('Hangi bilgisayardasın?', style: TextStyle(color: kMuted)),
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
          for (final fam in DistroFamily.values)
            if (items.any((d) => d.family == fam)) ...[
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 12),
                child: Text(fam == DistroFamily.linux ? 'Linux sistemleri' : 'Windows sistemleri',
                    style: const TextStyle(color: kText, fontSize: 20, fontWeight: FontWeight.w800)),
              ),
              Wrap(spacing: 12, runSpacing: 12, children: [
                for (final d in items.where((d) => d.family == fam)) _DistroCard(distro: d, onTap: () => widget.onOpen(d)),
              ]),
              const SizedBox(height: 20),
            ],
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
    final accent = Color(d.accent);
    return SizedBox(
      width: 272,
      height: d.screens.isEmpty ? 176 : 270,
      child: Material(
        color: kPanel,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: _active ? accent : const Color(0x14FFFFFF), width: _active ? 2 : 1),
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
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [accent.withAlpha(_active ? 90 : 55), kPanel],
                ),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (d.screens.isNotEmpty)
                  SizedBox(
                    height: 112,
                    width: double.infinity,
                    child: Image.asset(
                      d.screens.first.file,
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                      excludeFromSemantics: true,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        LetterBadge(name: d.name, color: accent, size: d.screens.isEmpty ? 44 : 34),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(d.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: kText, fontSize: 19, fontWeight: FontWeight.w800)),
                        ),
                      ]),
                      const SizedBox(height: 8),
                      Text(d.tagline,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: kMuted, height: 1.45)),
                      const Spacer(),
                      Row(children: [
                        Text('Kurulumu gör', style: TextStyle(color: _active ? kText : kAccent, fontWeight: FontWeight.w700)),
                        const SizedBox(width: 4),
                        Icon(Icons.arrow_forward_rounded, size: 18, color: _active ? kText : kAccent),
                      ]),
                    ]),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
