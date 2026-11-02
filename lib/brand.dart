import 'package:flutter/material.dart';

import 'site_mode.dart';
import 'theme.dart';

/// The BesideOS mark: one disk (rounded square) holding two systems side by side.
class BesideMark extends StatelessWidget {
  const BesideMark({super.key, this.size = 40});
  final double size;

  @override
  Widget build(BuildContext context) =>
      SizedBox(width: size, height: size, child: CustomPaint(painter: _MarkPainter()));
}

class _MarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    RRect r(double l, double t, double r, double b, double rad) =>
        RRect.fromRectAndRadius(Rect.fromLTRB(l * s, t * s, r * s, b * s), Radius.circular(rad * s));

    final disk = r(0, 0, 1, 1, 0.24);
    canvas.drawRRect(
      disk,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF30395A), Color(0xFF1B2132)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawRRect(
      disk.deflate(s * 0.01),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.02
        ..color = const Color(0x24FFFFFF),
    );

    Paint grad(Rect rect, Color a, Color b) => Paint()
      ..shader = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [a, b]).createShader(rect);

    final left = r(0.15, 0.15, 0.53, 0.85, 0.10);
    canvas.drawRRect(left, grad(left.outerRect, const Color(0xFF8CC4FF), const Color(0xFF3B82F6)));
    final topRight = r(0.59, 0.15, 0.85, 0.46, 0.10);
    canvas.drawRRect(topRight, grad(topRight.outerRect, const Color(0xFF7CF0AE), const Color(0xFF22C55E)));
    final bottomRight = r(0.59, 0.54, 0.85, 0.85, 0.10);
    canvas.drawRRect(bottomRight, grad(bottomRight.outerRect, const Color(0xFF5FE39A), const Color(0xFF16A34A)));
  }

  @override
  bool shouldRepaint(_MarkPainter oldDelegate) => false;
}

/// Mark plus the word "BesideOS". Tapping it goes to the home page when [onTap] is set.
class BesideLogo extends StatelessWidget {
  const BesideLogo({super.key, this.height = 36, this.onTap, this.showWord = true});
  final double height;
  final VoidCallback? onTap;
  final bool showWord;

  @override
  Widget build(BuildContext context) {
    final logo = Row(mainAxisSize: MainAxisSize.min, children: [
      BesideMark(size: height),
      if (showWord) ...[
        SizedBox(width: height * 0.3),
        Semantics(
          label: 'BesideOS',
          excludeSemantics: true,
          child: Text.rich(
            TextSpan(children: [
              const TextSpan(text: 'Beside', style: TextStyle(color: kText)),
              TextSpan(text: 'OS', style: TextStyle(color: kAccent.withAlpha(255))),
            ]),
            style: TextStyle(fontSize: height * 0.62, fontWeight: FontWeight.w800, letterSpacing: -0.4, height: 1),
          ),
        ),
      ],
    ]);
    if (onTap == null) return logo;
    return Tooltip(
      message: 'Ana sayfa',
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        mouseCursor: SystemMouseCursors.click,
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4), child: logo),
      ),
    );
  }
}

/// Top bar shared by every page: logo (home link), an optional page name and the website's download button.
/// Its content sits in the same centred column as the page below ([maxWidth], [padding]) so the logo and the
/// right-hand buttons line up with the content instead of the window edges. Adapts down to 320 px wide.
class SiteBar extends StatelessWidget implements PreferredSizeWidget {
  const SiteBar({
    super.key,
    this.page,
    this.leading,
    this.showCatalog = false,
    this.maxWidth = 1180,
    this.padding = 24,
  });
  final String? page;
  final Widget? leading;

  /// Adds a "Dağıtımlar" link (the home page uses it).
  final bool showCatalog;
  final double maxWidth;
  final double padding;

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final compact = w < 680;
    // Little room: keep only the mark (the page name or the buttons matter more than the word).
    final showWord = w >= 400 && !(page != null && w < 520);
    final web = SiteMode.isWeb(context);
    final side = w < 400 ? 12.0 : padding;
    return Material(
      color: kBg,
      child: Container(
        height: 64,
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0x1FFFFFFF)))),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: side),
              child: Row(children: [
                if (leading != null) ...[leading!, const SizedBox(width: 4)],
                BesideLogo(
                  height: 34,
                  showWord: showWord,
                  onTap: () => Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false),
                ),
                if (page != null) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.chevron_right_rounded, color: kMuted),
                  const SizedBox(width: 2),
                  Flexible(
                    child: Text(page!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: kText, fontSize: 18, fontWeight: FontWeight.w700)),
                  ),
                ],
                const Spacer(),
                if (showCatalog)
                  compact
                      ? IconButton(
                          onPressed: () => Navigator.pushNamed(context, '/distros'),
                          tooltip: 'Dağıtımlar',
                          icon: const Icon(Icons.apps_rounded),
                        )
                      : TextButton.icon(
                          onPressed: () => Navigator.pushNamed(context, '/distros'),
                          icon: const Icon(Icons.apps_rounded, size: 20),
                          label: const Text('Dağıtımlar'),
                        ),
                // The desktop app (not the website) can choose which installed system starts.
                if (showCatalog && !web)
                  compact
                      ? IconButton(
                          onPressed: () => Navigator.pushNamed(context, '/boot'),
                          tooltip: 'Açılış sistemi',
                          icon: const Icon(Icons.power_settings_new_rounded),
                        )
                      : TextButton.icon(
                          onPressed: () => Navigator.pushNamed(context, '/boot'),
                          icon: const Icon(Icons.power_settings_new_rounded, size: 20),
                          label: const Text('Açılış sistemi'),
                        ),
                if (web) ...[
                  const SizedBox(width: 6),
                  if (compact)
                    IconButton.filled(
                      onPressed: () => SiteMode.download(context),
                      tooltip: 'İndir',
                      icon: const Icon(Icons.download_rounded),
                    )
                  else
                    FilledButton.icon(
                      onPressed: () => SiteMode.download(context),
                      icon: const Icon(Icons.download_rounded, size: 20),
                      label: const Text('İndir'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
/// A page body that scrolls with the scrollbar pinned to the far right edge of the window
/// (always visible), while the content sits in a centred column of at most [maxWidth].
class PageScroll extends StatefulWidget {
  const PageScroll({super.key, required this.child, this.maxWidth, this.padding = EdgeInsets.zero});
  final Widget child;
  final double? maxWidth;
  final EdgeInsets padding;

  @override
  State<PageScroll> createState() => _PageScrollState();
}

class _PageScrollState extends State<PageScroll> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.maxWidth;
    return ScrollbarTheme(
      data: ScrollbarThemeData(
        thickness: WidgetStateProperty.all(11),
        radius: const Radius.circular(8),
        thumbColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.hovered) || s.contains(WidgetState.dragged) ? const Color(0xFF8A96AD) : const Color(0xFF5B6680)),
        trackColor: WidgetStateProperty.all(const Color(0x14FFFFFF)),
        trackBorderColor: WidgetStateProperty.all(const Color(0x00000000)),
      ),
      child: Scrollbar(
        controller: _controller,
        thumbVisibility: true,
        trackVisibility: true,
        interactive: true,
        child: SingleChildScrollView(
          controller: _controller,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: w ?? double.infinity),
              child: Padding(padding: widget.padding, child: widget.child),
            ),
          ),
        ),
      ),
    );
  }
}
