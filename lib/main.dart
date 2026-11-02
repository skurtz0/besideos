import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'catalog/distro.dart';
import 'catalog/routes.dart';
import 'theme.dart';

void main() => runApp(const BesideSite());

Future<String> _loadCatalogAsset() => rootBundle.loadString('assets/catalog/catalog.json');

class BesideSite extends StatefulWidget {
  /// [catalog] is injected by tests; otherwise it is loaded (lazily, only for /distros) via [catalogLoader].
  const BesideSite({this.catalog, this.catalogLoader, super.key});
  final Catalog? catalog;
  final Future<String> Function()? catalogLoader;

  @override
  State<BesideSite> createState() => _BesideSiteState();
}

class _BesideSiteState extends State<BesideSite> {
  late final Future<Catalog> _catalog = widget.catalog != null
      ? Future.value(widget.catalog)
      : (widget.catalogLoader ?? _loadCatalogAsset)().then(Catalog.parse);

  Route<dynamic> _route(RouteSettings s) {
    final seg = (Uri.tryParse(s.name ?? '')?.pathSegments ?? const <String>[]).where((e) => e.isNotEmpty);
    if (seg.isEmpty || seg.first != 'distros') {
      return MaterialPageRoute(settings: s, builder: (_) => const HomePage());
    }
    return MaterialPageRoute(
      settings: s,
      builder: (context) => FutureBuilder<Catalog>(
        future: _catalog,
        builder: (context, snap) {
          if (snap.hasData) {
            // catalogRoute always returns a MaterialPageRoute; reuse its page.
            return (catalogRoute(s, snap.data!) as MaterialPageRoute).builder(context);
          }
          if (snap.hasError) return _CatalogError(snap.error);
          return const Scaffold(backgroundColor: kBg, body: Center(child: CircularProgressIndicator()));
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateRoute: _route,
      title: 'BesideOS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: kBg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: kAccent,
          brightness: Brightness.dark,
          surface: kBg,
        ),
      ),
    );
  }
}

class _CatalogError extends StatelessWidget {
  const _CatalogError(this.error);
  final Object? error;

  @override
  Widget build(BuildContext context) {
    final msg = error is CatalogException ? (error as CatalogException).message : '$error';
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(backgroundColor: kBg, foregroundColor: kText),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Katalog yüklenemedi: $msg', style: const TextStyle(color: kText, fontSize: 18)),
        ),
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SingleChildScrollView(
        child: Column(
          children: [
            _GlowBackground(child: _Section(child: _Hero())),
            _Section(child: _HowItWorks()),
            _Section(child: _Platforms()),
            _Section(child: _Safety()),
            _Section(child: _Status()),
            _Footer(),
          ],
        ),
      ),
    );
  }
}

bool _reduced(BuildContext context) => MediaQuery.disableAnimationsOf(context);

/// Centres content in a column no wider than 960 px, with a gutter on phones.
/// Content fades in once it scrolls into view.
class _Section extends StatelessWidget {
  const _Section({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 36),
          child: _Reveal(child: child),
        ),
      ),
    );
  }
}

/// Fades and slides its child in the first time it is near the visible part of the page.
class _Reveal extends StatefulWidget {
  const _Reveal({required this.child, this.delay = Duration.zero});
  final Widget child;
  final Duration delay;

  @override
  State<_Reveal> createState() => _RevealState();
}

class _RevealState extends State<_Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 650));
  late final Animation<double> _curve =
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
  late final Animation<Offset> _slide =
      Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero).animate(_curve);
  ScrollPosition? _position;
  Timer? _timer;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _position?.removeListener(_check);
    _position = Scrollable.maybeOf(context)?.position;
    _position?.addListener(_check);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  void _check() {
    if (!mounted || _started) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached) return;
    final top = box.localToGlobal(Offset.zero).dy;
    if (top < MediaQuery.sizeOf(context).height * 0.92) {
      _started = true;
      _timer = Timer(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _position?.removeListener(_check);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_reduced(context)) return widget.child;
    return FadeTransition(
      opacity: _curve,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

/// A soft blue glow that drifts slowly behind the top of the page.
class _GlowBackground extends StatefulWidget {
  const _GlowBackground({required this.child});
  final Widget child;

  @override
  State<_GlowBackground> createState() => _GlowBackgroundState();
}

class _GlowBackgroundState extends State<_GlowBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(seconds: 9));
  bool _running = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = _reduced(context);
    if (!reduced && !_running) {
      _controller.repeat(reverse: true);
      _running = true;
    } else if (reduced && _running) {
      _controller.stop();
      _running = false;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final v = Curves.easeInOut.transform(_controller.value);
        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.lerp(const Alignment(-0.8, -0.7), const Alignment(0.8, 0.2), v)!,
              radius: 1.1,
              colors: [kAccent.withAlpha(48), kBg.withAlpha(0)],
            ),
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        Text('BesideOS',
            style: t.titleLarge?.copyWith(color: kAccent, fontWeight: FontWeight.w700)),
        const SizedBox(height: 16),
        Text(
          'Bilgisayarına ikinci bir sistem kur. USB bellek gerekmez.',
          style: t.displaySmall?.copyWith(color: kText, fontWeight: FontWeight.w800, height: 1.15),
        ),
        const SizedBox(height: 16),
        Text(
          'BesideOS diskinde yer açar, kurulumu hazırlar ve bilgisayarı yeniden başlatır. '
          "Windows'un olduğu gibi yerinde kalır.",
          style: t.titleMedium?.copyWith(color: kMuted, height: 1.5),
        ),
        const SizedBox(height: 28),
        SizedBox(
          height: 64,
          child: FilledButton.icon(
            onPressed: () => Navigator.pushNamed(context, '/distros'),
            icon: const Icon(Icons.touch_app_rounded, size: 28),
            label: const Text('Başlamak için tıklayın'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              textStyle: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
          ),
        ),
        const SizedBox(height: 24),
        const Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _Chip('Windows'),
            _Chip('Linux'),
            _Chip('Mac → Linux (M1/M2, rehberli)'),
            _Chip('Açık kaynak, MIT'),
          ],
        ),
        const SizedBox(height: 24),
        const _DiskDemo(),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: kPanel,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: const TextStyle(color: kText)),
    );
  }
}

/// A looping picture of one disk: the old system shrinks, the installer appears, the new system fills the gap.
/// It illustrates the idea and does not read anything from the visitor's computer.
class _DiskDemo extends StatefulWidget {
  const _DiskDemo();

  @override
  State<_DiskDemo> createState() => _DiskDemoState();
}

class _DiskDemoState extends State<_DiskDemo> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(seconds: 12));
  bool _running = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = _reduced(context);
    if (!reduced && !_running) {
      _controller.repeat();
      _running = true;
    } else if (reduced && _running) {
      _controller.stop();
      _running = false;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  static String _caption(double t) {
    if (t < 0.2) return 'Diskin şimdi böyle.';
    if (t < 0.4) return 'Yer açılır: bir bölüm küçülür.';
    if (t < 0.55) return 'Kurulum dosyaları aynı diske konur.';
    if (t < 0.85) return 'Bir kez yeniden başlayınca yeni sistem eskisinin yanına kurulur.';
    return 'İki sistem, tek disk. USB bellek yok.';
  }

  @override
  Widget build(BuildContext context) {
    final reduced = _reduced(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: kPanel,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final t = reduced ? 0.95 : _controller.value;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 64,
                    width: double.infinity,
                    child: CustomPaint(painter: _DiskPainter(t)),
                  ),
                  const SizedBox(height: 14),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: Text(
                      _caption(t),
                      key: ValueKey(_caption(t)),
                      style: const TextStyle(color: kText, fontSize: 16),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          const Text('Çizim. Gerçek plan, bir şey değişmeden önce sana tam olarak gösterilir.',
              style: TextStyle(color: kMuted, fontSize: 12)),
        ],
      ),
    );
  }
}

class _DiskPainter extends CustomPainter {
  _DiskPainter(this.t);
  final double t;

  static double _phase(double t, double from, double to) =>
      Curves.easeInOutCubic.transform(((t - from) / (to - from)).clamp(0.0, 1.0));

  @override
  void paint(Canvas canvas, Size size) {
    final bar = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width, size.height), const Radius.circular(12));
    canvas.drawRRect(bar, Paint()..color = const Color(0xFF2A3042));
    canvas.save();
    canvas.clipRRect(bar);

    final installer = 0.1 * _phase(t, 0.4, 0.55);
    final windows = 1.0 - 0.5 * _phase(t, 0.2, 0.4);
    final system = (1.0 - windows - installer) * _phase(t, 0.55, 0.8);

    final w = size.width;
    final h = size.height;
    final gap = 2.0;

    void segment(double from, double width, Color color, String label) {
      if (width <= 0.001) return;
      final rect = Rect.fromLTWH(from * w, 0, width * w - gap, h);
      canvas.drawRect(rect, Paint()..color = color);
      if (rect.width > 70) {
        final painter = TextPainter(
          text: TextSpan(
              text: label,
              style: const TextStyle(
                  color: Color(0xFF10131B), fontSize: 14, fontWeight: FontWeight.w700)),
          textDirection: TextDirection.ltr,
          maxLines: 1,
          ellipsis: '…',
        )..layout(maxWidth: rect.width - 16);
        painter.paint(canvas, Offset(rect.left + 10, (h - painter.height) / 2));
      }
    }

    segment(0, windows, const Color(0xFF8FA3C7), 'Şimdiki sistem');
    segment(1.0 - system - installer, installer, kAccent, 'Kurulum');
    segment(1.0 - system, system, kGreen, 'Yeni sistem');
    canvas.restore();
  }

  @override
  bool shouldRepaint(_DiskPainter oldDelegate) => oldDelegate.t != t;
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .headlineSmall
            ?.copyWith(color: kText, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _CardData {
  const _CardData(this.title, this.body);
  final String title;
  final String body;
}

/// A wrapping row of cards. Each one fades in a little after the one before it.
class _CardGrid extends StatelessWidget {
  const _CardGrid({required this.cards, this.width = 290});
  final List<_CardData> cards;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        for (var i = 0; i < cards.length; i++)
          _Reveal(
            delay: Duration(milliseconds: 120 * i),
            child: _HoverCard(data: cards[i], width: width),
          ),
      ],
    );
  }
}

class _HoverCard extends StatefulWidget {
  const _HoverCard({required this.data, required this.width});
  final _CardData data;
  final double width;

  @override
  State<_HoverCard> createState() => _HoverCardState();
}

class _HoverCardState extends State<_HoverCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: widget.width),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          transform: Matrix4.translationValues(0, _hover ? -4 : 0, 0),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: kPanel,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: _hover ? kAccent.withAlpha(170) : const Color(0x00000000)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.data.title,
                  style: const TextStyle(
                      color: kText, fontSize: 17, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text(widget.data.body, style: const TextStyle(color: kMuted, height: 1.5)),
            ],
          ),
        ),
      ),
    );
  }
}

class _HowItWorks extends StatelessWidget {
  const _HowItWorks();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Heading('Nasıl çalışır?'),
        _CardGrid(cards: [
          _CardData('1. Yer açılır',
              'Planı görüp dosyalarını yedeklediğini onayladıktan sonra diskte boş yer açılır.'),
          _CardData('2. Kurulum hazırlanır',
              'Kurulum dosyaları aynı diskteki küçük bir bölüme konur. USB bellek gerekmez.'),
          _CardData('3. Bir kez yeniden başlar',
              'Bir sonraki açılışta kurulum ekranı gelir. Sonrasında bilgisayar her zamanki gibi açılır.'),
        ]),
      ],
    );
  }
}

class _Platforms extends StatelessWidget {
  const _Platforms();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Heading('Hangi bilgisayarlarda?'),
        _CardGrid(cards: [
          _CardData("Windows'tan Linux'a",
              'İlk hedef. UEFI ile açılan bir bilgisayar gerekir. Davranışı, bu projenin temelini oluşturan hop izler.'),
          _CardData("Linux'tan Windows'a", 'Sırada. Windows ISO dosyasını sen getirirsin.'),
          _CardData('macOS',
              'En son ve sınırlarını dürüstçe söyleyerek. Apple Silicon\'da UEFI ve Boot Camp yok; bu yüzden BesideOS orada yalnızca resmi Asahi kurulumunu anlatır.'),
        ]),
      ],
    );
  }
}

class _Safety extends StatelessWidget {
  const _Safety();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Heading('Önce güvenlik'),
        _CardGrid(width: 220, cards: [
          _CardData('Önce plan', 'Diske dokunmadan önce her adımı görürsün.'),
          _CardData('Yedek uyarısı', 'Bir bölüm küçülmeden önce yedek aldığını onaylarsın.'),
          _CardData('Açık onay', 'Başlamadan önce son kez sorulur.'),
          _CardData('Geri alma',
              'Bir adım başarısız olursa ya da vazgeçersen, yapılanlar tersine geri alınır.'),
        ]),
      ],
    );
  }
}

class _Status extends StatelessWidget {
  const _Status();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: kPanel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kAccent.withAlpha(120)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Durum: erken geliştirme',
              style: TextStyle(color: kText, fontSize: 18, fontWeight: FontWeight.w700)),
          SizedBox(height: 8),
          Text(
            'Windows uygulaması dağıtımı indirip kuruluma hazırlayabiliyor, ama henüz geniş çapta denenmedi. '
            'Kurmadan önce önemli dosyalarını mutlaka yedekle.',
            style: TextStyle(color: kMuted, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    return const _Section(
      child: Text(
        'BesideOS MIT lisansıyla açık kaynaktır. Arjun Ingole\'nin hop projesini temel alır '
        '(o da MIT). Diğer işletim sistemi adları sahiplerine aittir ve yalnızca BesideOS\'un '
        'neyi kurabildiğini söylemek için kullanılır.',
        style: TextStyle(color: kMuted, fontSize: 13, height: 1.5),
      ),
    );
  }
}
