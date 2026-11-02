import 'package:flutter/material.dart';

import 'theme.dart';

const _purple = Color(0xFFA78BFA);

/// Small coloured label, a big title and an optional line under it. Opens each home page section.
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.eyebrow, required this.title, this.subtitle, this.color = kAccent});
  final String eyebrow;
  final String title;
  final String? subtitle;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 480;
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 22, height: 4, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 10),
          Text(eyebrow.toUpperCase(),
              style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 1.4)),
        ]),
        const SizedBox(height: 12),
        Text(title,
            style: TextStyle(color: kText, fontSize: narrow ? 26 : 34, fontWeight: FontWeight.w800, height: 1.15, letterSpacing: -0.5)),
        if (subtitle != null) ...[
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Text(subtitle!, style: const TextStyle(color: kMuted, fontSize: 17, height: 1.6)),
          ),
        ],
      ]),
    );
  }
}

/// Lays [children] out in equal-width columns that follow the available width (1 on a phone, up to [maxColumns]),
/// with every card in a row as tall as the tallest.
class ResponsiveCards extends StatelessWidget {
  const ResponsiveCards({super.key, required this.children, this.minWidth = 260, this.maxColumns = 4, this.gap = 18});
  final List<Widget> children;
  final double minWidth;
  final int maxColumns;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth.isFinite ? box.maxWidth : minWidth * 3;
      var cols = ((w + gap) / (minWidth + gap)).floor();
      cols = cols.clamp(1, maxColumns).clamp(1, children.length);
      // never leave a single card alone on the last row (4 cards: 2 + 2 rather than 3 + 1)
      while (cols > 1 && children.length > cols && children.length % cols == 1) {
        cols--;
      }
      final rows = <Widget>[];
      for (var i = 0; i < children.length; i += cols) {
        final slice = children.sublist(i, (i + cols).clamp(0, children.length));
        rows.add(Padding(
          padding: EdgeInsets.only(top: i == 0 ? 0 : gap),
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (var j = 0; j < cols; j++) ...[
                if (j > 0) SizedBox(width: gap),
                Expanded(child: j < slice.length ? slice[j] : const SizedBox.shrink()),
              ],
            ]),
          ),
        ));
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
    });
  }
}

/// A tinted card with an icon tile, a title and text; optional big step number and status chip.
class FeatureCard extends StatefulWidget {
  const FeatureCard({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
    this.step,
    this.chip,
    this.chipColor,
  });
  final IconData icon;
  final Color color;
  final String title;
  final String body;
  final String? step;
  final String? chip;
  final Color? chipColor;

  @override
  State<FeatureCard> createState() => _FeatureCardState();
}

class _FeatureCardState extends State<FeatureCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.color;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(0, _hover ? -4 : 0, 0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [c.withAlpha(_hover ? 70 : 48), kPanel],
          ),
          border: Border.all(color: c.withAlpha(_hover ? 190 : 100)),
          boxShadow: _hover ? [BoxShadow(color: c.withAlpha(50), blurRadius: 24, offset: const Offset(0, 10))] : const [],
        ),
        child: Stack(children: [
          if (widget.step != null)
            Positioned(
              right: 18,
              top: 6,
              child: Text(widget.step!,
                  style: TextStyle(color: c.withAlpha(60), fontSize: 64, fontWeight: FontWeight.w900, height: 1)),
            ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(color: c.withAlpha(46), borderRadius: BorderRadius.circular(16)),
                child: Icon(widget.icon, color: c, size: 28),
              ),
              const SizedBox(height: 18),
              Text(widget.title, style: const TextStyle(color: kText, fontSize: 20, fontWeight: FontWeight.w800, height: 1.25)),
              const SizedBox(height: 8),
              Text(widget.body, style: const TextStyle(color: kMuted, fontSize: 16, height: 1.6)),
              if (widget.chip != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: (widget.chipColor ?? c).withAlpha(36),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: (widget.chipColor ?? c).withAlpha(120)),
                  ),
                  child: Text(widget.chip!,
                      style: TextStyle(color: widget.chipColor ?? c, fontSize: 13, fontWeight: FontWeight.w800)),
                ),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}

class HowItWorks extends StatelessWidget {
  const HowItWorks({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionHeader(
        eyebrow: 'Adım adım',
        title: 'Nasıl çalışır?',
        subtitle: 'Üç adım. Sen onaylamadan bilgisayarında hiçbir şey değişmez.',
      ),
      ResponsiveCards(minWidth: 270, maxColumns: 3, children: [
        FeatureCard(
          step: '1',
          icon: Icons.content_cut_rounded,
          color: kAccent,
          title: 'Yer açılır',
          body: 'Planı görüp dosyalarını yedeklediğini onayladıktan sonra diskte boş yer açılır.',
        ),
        FeatureCard(
          step: '2',
          icon: Icons.inventory_2_rounded,
          color: _purple,
          title: 'Kurulum hazırlanır',
          body: 'Kurulum dosyaları aynı diskteki küçük bir bölüme konur. USB bellek gerekmez.',
        ),
        FeatureCard(
          step: '3',
          icon: Icons.restart_alt_rounded,
          color: kGreen,
          title: 'Bir kez yeniden başlar',
          body: 'Bir sonraki açılışta kurulum ekranı gelir. Sonrasında bilgisayar her zamanki gibi açılır.',
        ),
      ]),
    ]);
  }
}

class Platforms extends StatelessWidget {
  const Platforms({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionHeader(
        eyebrow: 'Uyumluluk',
        title: 'Hangi bilgisayarlarda?',
        subtitle: 'Ne çalıştığını ve ne çalışmadığını açıkça söyleriz.',
        color: _purple,
      ),
      ResponsiveCards(minWidth: 270, maxColumns: 3, children: [
        FeatureCard(
          icon: Icons.desktop_windows_rounded,
          color: kAccent,
          title: "Windows'tan Linux'a",
          body: 'İlk hedef. UEFI ile açılan bir bilgisayar gerekir. Davranışı, bu projenin temelini oluşturan hop izler.',
          chip: 'Hazır',
          chipColor: kGreen,
        ),
        FeatureCard(
          icon: Icons.swap_horiz_rounded,
          color: _purple,
          title: "Linux'tan Windows'a",
          body: 'Sırada. Windows ISO dosyasını sen getirirsin.',
          chip: 'Sırada',
          chipColor: kWarn,
        ),
        FeatureCard(
          icon: Icons.laptop_mac_rounded,
          color: kWarn,
          title: 'macOS',
          body:
              "En son ve sınırlarını dürüstçe söyleyerek. Apple Silicon'da UEFI ve Boot Camp yok; bu yüzden BesideOS orada yalnızca resmi Asahi kurulumunu anlatır.",
          chip: 'Rehberli',
          chipColor: kMuted,
        ),
      ]),
    ]);
  }
}

class Safety extends StatelessWidget {
  const Safety({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionHeader(
        eyebrow: 'Güven',
        title: 'Önce güvenlik',
        subtitle: 'Diskine dokunan bir araç için en önemli şey: ne yapacağını önceden söylemesi ve geri alabilmen.',
        color: kGreen,
      ),
      ResponsiveCards(minWidth: 240, maxColumns: 4, children: [
        FeatureCard(
          icon: Icons.fact_check_rounded,
          color: kAccent,
          title: 'Önce plan',
          body: 'Diske dokunmadan önce her adımı görürsün.',
        ),
        FeatureCard(
          icon: Icons.backup_rounded,
          color: kWarn,
          title: 'Yedek uyarısı',
          body: 'Bir bölüm küçülmeden önce yedek aldığını onaylarsın.',
        ),
        FeatureCard(
          icon: Icons.verified_user_rounded,
          color: kGreen,
          title: 'Açık onay',
          body: 'Başlamadan önce son kez sorulur.',
        ),
        FeatureCard(
          icon: Icons.undo_rounded,
          color: _purple,
          title: 'Geri alma',
          body: 'Bir adım başarısız olursa ya da vazgeçersen, yapılanlar tersine geri alınır.',
        ),
      ]),
    ]);
  }
}
