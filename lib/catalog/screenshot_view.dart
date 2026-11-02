import 'package:flutter/material.dart';

import '../theme.dart';
import 'distro.dart';

/// A bundled screenshot with its caption and credit. Tap to see it large.
class ScreenShotView extends StatelessWidget {
  const ScreenShotView({super.key, required this.shot});
  final ScreenShot shot;

  Widget _image(BoxFit fit) => Image.asset(
        shot.file,
        fit: fit,
        semanticLabel: shot.caption,
        errorBuilder: (_, __, ___) => const Center(
          child: Icon(Icons.image_not_supported_outlined, color: kMuted, size: 36),
        ),
      );

  void _open(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: kBg,
        insetPadding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Flexible(child: InteractiveViewer(maxScale: 5, child: _image(BoxFit.contain))),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(children: [
              Expanded(child: Text(shot.caption, style: const TextStyle(color: kText, fontWeight: FontWeight.w600))),
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Kapat')),
            ]),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Material(
          color: kPanel2,
          child: InkWell(
            onTap: () => _open(context),
            mouseCursor: SystemMouseCursors.zoomIn,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 460),
              child: AspectRatio(aspectRatio: 16 / 9, child: _image(BoxFit.contain)),
            ),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Text(shot.caption, style: const TextStyle(color: kText, fontWeight: FontWeight.w600, height: 1.4)),
      const SizedBox(height: 2),
      Text('${shot.credit}  ·  Büyütmek için resme tıkla',
          style: const TextStyle(color: kMuted, fontSize: 12, height: 1.4)),
      if (shot.source != null)
        SelectableText(shot.source!, style: const TextStyle(color: kMuted, fontSize: 12, height: 1.4)),
    ]);
  }
}
