import 'l10n/text.dart';
import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_localizations/flutter_localizations.dart';

import 'brand.dart';
import 'catalog/catalog_page.dart' show DistroSections;
import 'catalog/distro.dart';
import 'catalog/routes.dart';
import 'home_sections.dart';
import 'l10n/l10n.dart';
import 'site_mode.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await L10n.instance.init();
  runApp(const BesideSite());
}

Future<String> _loadCatalogAsset() =>
    rootBundle.loadString('assets/catalog/catalog.json');

class BesideSite extends StatefulWidget {
  /// [catalog] is injected by tests; otherwise it is loaded (lazily, only for /distros) via [catalogLoader].
  const BesideSite(
      {this.catalog,
      this.catalogLoader,
      this.initialRoute = '/',
      this.web,
      this.onDownload,
      super.key});
  final String initialRoute;

  /// Forces website (true) or desktop-app (false) behaviour; null follows the platform.
  final bool? web;

  /// Replaces the real browser download (tests).
  final VoidCallback? onDownload;
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
    final seg = (Uri.tryParse(s.name ?? '')?.pathSegments ?? const <String>[])
        .where((e) => e.isNotEmpty);
    if (seg.isEmpty || (seg.first != 'distros' && seg.first != 'boot')) {
      return MaterialPageRoute(
          settings: s, builder: (_) => HomePage(catalog: _catalog));
    }
    return MaterialPageRoute(
      settings: s,
      builder: (context) => FutureBuilder<Catalog>(
        future: _catalog,
        builder: (context, snap) {
          if (snap.hasData) {
            // catalogRoute always returns a MaterialPageRoute; reuse its page.
            return (catalogRoute(s, snap.data!) as MaterialPageRoute)
                .builder(context);
          }
          if (snap.hasError) return _CatalogError(snap.error);
          return const Scaffold(
              backgroundColor: kBg,
              body: Center(child: CircularProgressIndicator()));
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: kBg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: kAccent,
        brightness: Brightness.dark,
        surface: kBg,
      ),
    );
    // Larger, airier body text: this is what everything without an explicit size inherits.
    final tt = base.textTheme;
    return ListenableBuilder(
        listenable: L10n.instance,
        builder: (context, _) => MaterialApp(
              locale: L10n.instance.locale,
              supportedLocales: [for (final l in kLangs) l.locale],
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              onGenerateRoute: _route,
              initialRoute: widget.initialRoute,
              builder: (context, child) => SiteMode(
                  web: widget.web ?? kIsWeb,
                  onDownload: widget.onDownload,
                  child: child!),
              title: 'BesideOS',
              onGenerateTitle: (_) => tr('BesideOS: başka bir işletim sistemini bunun yanına kur'),
              debugShowCheckedModeBanner: false,
              theme: base.copyWith(
                textTheme: tt.copyWith(
                  // semi-bold by default so text stays crisp on dark backgrounds
                  bodyLarge: tt.bodyLarge?.copyWith(
                      fontSize: 17, height: 1.55, fontWeight: FontWeight.w600),
                  bodyMedium: tt.bodyMedium?.copyWith(
                      fontSize: 16, height: 1.55, fontWeight: FontWeight.w600),
                  bodySmall: tt.bodySmall?.copyWith(
                      fontSize: 14, height: 1.5, fontWeight: FontWeight.w600),
                  labelLarge: tt.labelLarge
                      ?.copyWith(fontSize: 15, fontWeight: FontWeight.w700),
                  labelMedium:
                      tt.labelMedium?.copyWith(fontWeight: FontWeight.w700),
                  titleSmall:
                      tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  titleMedium: tt.titleMedium?.copyWith(
                      fontSize: 18, height: 1.5, fontWeight: FontWeight.w700),
                ),
              ),
            ));
  }
}

class _CatalogError extends StatelessWidget {
  const _CatalogError(this.error);
  final Object? error;

  @override
  Widget build(BuildContext context) {
    final msg = error is CatalogException
        ? (error as CatalogException).message
        : '$error';
    return Scaffold(
      backgroundColor: kBg,
      appBar: const SiteBar(),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(tr('Katalog yüklenemedi: {msg}', {'msg': msg}),
              style: const TextStyle(color: kText, fontSize: 18)),
        ),
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key, this.catalog});

  /// Shown as the list of systems above the status note; null hides that section.
  final Future<Catalog>? catalog;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const SiteBar(showCatalog: true, maxWidth: 960, padding: 20),
      body: PageScroll(
        child: Column(
          children: [
            const _GlowBackground(child: _Section(child: _Hero())),
            const _Section(child: HowItWorks()),
            if (catalog != null) _Section(child: _Showcase(catalog: catalog!)),
            const _Section(child: _Status()),
            const _Footer(),
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
  const _Reveal({required this.child});
  final Widget child;

  @override
  State<_Reveal> createState() => _RevealState();
}

class _RevealState extends State<_Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 650));
  late final Animation<double> _curve =
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
  late final Animation<Offset> _slide =
      Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
          .animate(_curve);
  ScrollPosition? _position;
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
    if (!box.hasSize) {
      // not laid out yet (e.g. inside a LayoutBuilder); look again after the next frame
      WidgetsBinding.instance.addPostFrameCallback((_) => _check());
      return;
    }
    final top = box.localToGlobal(Offset.zero).dy;
    if (top < MediaQuery.sizeOf(context).height * 0.92) {
      _started = true;
      _controller.forward();
    }
  }

  @override
  void dispose() {
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
              center: Alignment.lerp(
                  const Alignment(-0.8, -0.7), const Alignment(0.8, 0.2), v)!,
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
    final web = SiteMode.isWeb(context);
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      final narrow = w < 480;
      final wide = w >= 760;
      final text = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Bilgisayarına USB bellek gerekmeden ikinci bir sistem kur.',
            style: TextStyle(
              color: kText,
              fontSize: narrow ? 30 : (wide ? 46 : 38),
              fontWeight: FontWeight.w800,
              height: 1.12,
              letterSpacing: -0.8,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'BesideOS diskinde yer açar ve kurulumu hazırlar; hazır olunca sen yeniden başlatırsın. '
            "Windows'un olduğu gibi yerinde kalır.",
            style: TextStyle(
                color: kMuted, fontSize: narrow ? 17 : 19, height: 1.6),
          ),
          const SizedBox(height: 30),
          SizedBox(
            height: narrow ? 58 : 64,
            width: narrow ? double.infinity : null,
            child: FilledButton.icon(
              // On the website the button gets the app; inside the app it opens the list of systems.
              onPressed: () => web
                  ? SiteMode.download(context)
                  : Navigator.pushNamed(context, '/distros'),
              icon: Icon(web ? Icons.download_rounded : Icons.touch_app_rounded,
                  size: narrow ? 24 : 28),
              label: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                    web ? 'İndirmek için tıklayın' : 'Başlamak için tıklayın'),
              ),
              style: FilledButton.styleFrom(
                padding: EdgeInsets.symmetric(horizontal: narrow ? 18 : 32),
                textStyle: TextStyle(
                    fontSize: narrow ? 18 : 21, fontWeight: FontWeight.w800),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
              ),
            ),
          ),
          const SizedBox(height: 26),
          const Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _Chip('Windows'),
              _Chip('Linux'),
              _Chip('Açık kaynak, MIT'),
            ],
          ),
        ],
      );
      return Padding(
        padding: EdgeInsets.only(top: narrow ? 8 : 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (wide)
            Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Expanded(child: text),
              const SizedBox(width: 56),
              const BesideMark(size: 240),
            ])
          else ...[
            BesideMark(size: narrow ? 72 : 96),
            SizedBox(height: narrow ? 18 : 24),
            text,
          ],
          const SizedBox(height: 36),
          const _DiskDemo(),
        ]),
      );
    });
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

class _DiskDemoState extends State<_DiskDemo>
    with SingleTickerProviderStateMixin {
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
    if (t < 0.85) {
      return 'Bir kez yeniden başlayınca yeni sistem eskisinin yanına kurulur.';
    }
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
          const Text(
              'Çizim. Gerçek plan, bir şey değişmeden önce sana tam olarak gösterilir.',
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
      Curves.easeInOutCubic
          .transform(((t - from) / (to - from)).clamp(0.0, 1.0));

  @override
  void paint(Canvas canvas, Size size) {
    final bar = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width, size.height),
        const Radius.circular(12));
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
                  color: Color(0xFF10131B),
                  fontSize: 14,
                  fontWeight: FontWeight.w700)),
          textDirection: TextDirection.ltr,
          maxLines: 1,
          ellipsis: '…',
        )..layout(maxWidth: rect.width - 16);
        painter.paint(canvas, Offset(rect.left + 10, (h - painter.height) / 2));
      }
    }

    segment(0, windows, const Color(0xFF8FA3C7), tr('Şimdiki sistem'));
    segment(1.0 - system - installer, installer, kAccent, tr('Kurulum'));
    segment(1.0 - system, system, kGreen, tr('Yeni sistem'));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_DiskPainter oldDelegate) => oldDelegate.t != t;
}

/// The systems BesideOS can set up, right on the home page (above the status note).
class _Showcase extends StatelessWidget {
  const _Showcase({required this.catalog});
  final Future<Catalog> catalog;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SectionHeader(
        eyebrow: 'Katalog',
        title: 'Hangi sistemleri kurabilirsin?',
        subtitle: 'Birini seç; nasıl göründüğünü ve nelerin gerektiğini gör.',
      ),
      FutureBuilder<Catalog>(
        future: catalog,
        builder: (context, snap) {
          if (snap.hasData) {
            return DistroSections(
              items: snap.data!.distros,
              onOpen: (d) => Navigator.pushNamed(context, '/distros/${d.id}'),
            );
          }
          if (snap.hasError) return const SizedBox.shrink();
          return const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()));
        },
      ),
    ]);
  }
}

class _Status extends StatelessWidget {
  const _Status();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [kWarn.withAlpha(40), kPanel],
        ),
        border: Border.all(color: kWarn.withAlpha(120)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
              color: kWarn.withAlpha(40),
              borderRadius: BorderRadius.circular(14)),
          child: const Icon(Icons.backup_rounded, color: kWarn, size: 26),
        ),
        const SizedBox(width: 16),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Kurmadan önce yedek al',
                  style: TextStyle(
                      color: kText, fontSize: 20, fontWeight: FontWeight.w800)),
              SizedBox(height: 8),
              Text(
                'BesideOS, yeni sistem için diskinde yer açar. Dosyaların silinmez, ama disk işlemlerinde nadiren de olsa sorun çıkabilir; '
                'önemli dosyalarını yedeklemeni öneririz. Vazgeçersen "Değişiklikleri geri al" ile eski haline dönebilirsin.',
                style: TextStyle(color: kMuted, fontSize: 16, height: 1.6),
              ),
            ],
          ),
        ),
      ]),
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
