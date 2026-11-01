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
          'Install another operating system beside this one. No USB stick.',
          style: t.displaySmall?.copyWith(color: kText, fontWeight: FontWeight.w700, height: 1.15),
        ),
        const SizedBox(height: 16),
        Text(
          'BesideOS makes room on your disk, puts the installer there, and restarts into it. '
          'Your current system stays where it is.',
          style: t.titleMedium?.copyWith(color: kMuted, height: 1.5),
        ),
        const SizedBox(height: 24),
        const Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _Chip('Windows'),
            _Chip('Linux'),
            _Chip('Mac → Linux (M1/M2, guided)'),
            _Chip('Open source, MIT'),
          ],
        ),
        const SizedBox(height: 16),
        TextButton(
          onPressed: () => Navigator.pushNamed(context, '/distros'),
          child: const Text('Dağıtımlara göz at'),
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
    if (t < 0.2) return 'Your disk, as it is.';
    if (t < 0.4) return 'Make room: one partition shrinks.';
    if (t < 0.55) return 'The installer is staged on the same disk.';
    if (t < 0.85) return 'After one restart, the new system installs beside the old one.';
    return 'Two systems, one disk. No USB stick.';
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
          const Text('Illustration. Real plans are shown to you in full before anything changes.',
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

    segment(0, windows, const Color(0xFF8FA3C7), 'Current system');
    segment(1.0 - system - installer, installer, kAccent, 'Installer');
    segment(1.0 - system, system, kGreen, 'New system');
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
        _Heading('How it works'),
        _CardGrid(cards: [
          _CardData('1. Make room',
              'Shrinks a partition to free space, after you have seen the plan and confirmed that your data is backed up.'),
          _CardData('2. Stage the installer',
              'Puts the ISO on a small partition of the same disk and adjusts its boot menu, so no USB stick is needed.'),
          _CardData('3. Restart once',
              'Adds a one-time boot entry. The next restart opens the installer; after that the machine boots as usual.'),
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
        _Heading('Platforms'),
        _CardGrid(cards: [
          _CardData('Windows to Linux',
              'The first target. Needs UEFI. Behaviour follows hop, which this project is based on.'),
          _CardData('Linux to Windows', 'Planned next. You supply the Windows ISO.'),
          _CardData('macOS',
              'Planned last and honest about limits. Apple Silicon has no UEFI or Boot Camp, so BesideOS only guides the official Asahi installer there, on the Macs it supports.'),
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
        _Heading('Safety first'),
        _CardGrid(width: 220, cards: [
          _CardData('Dry run by default', 'You see every step before anything touches the disk.'),
          _CardData('Backup warning', 'Required before any partition is shrunk.'),
          _CardData('Confirm each step', 'Every destructive step asks you first.'),
          _CardData('Rollback',
              'If a step fails or you decline, applied steps are undone in reverse.'),
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
          Text('Status: early development',
              style: TextStyle(color: kText, fontSize: 18, fontWeight: FontWeight.w700)),
          SizedBox(height: 8),
          Text(
            'There is no download yet. The current builds do not change any disk. '
            'This page will link to signed releases when they exist.',
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
        'BesideOS is open source under the MIT license. It is based on hop by Arjun Ingole, '
        'also MIT. Other operating-system names belong to their owners and are used only to '
        'say what BesideOS can install.',
        style: TextStyle(color: kMuted, fontSize: 13, height: 1.5),
      ),
    );
  }
}
