import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../catalog/distro.dart';
import '../theme.dart';
import 'download_controller.dart';
import 'downloader.dart';
import 'host_arch_stub.dart' if (dart.library.io) 'host_arch_io.dart';

class DownloadSection extends StatefulWidget {
  const DownloadSection({
    super.key,
    required this.distro,
    this.controllerFactory,
    this.hostArch,
    this.isWeb,
  });
  final Distro distro;
  final DownloadController Function()? controllerFactory;
  final IsoArch? hostArch;
  final bool? isWeb;

  @override
  State<DownloadSection> createState() => _DownloadSectionState();
}

class _DownloadSectionState extends State<DownloadSection> {
  DownloadController? _ctl;
  final _path = TextEditingController();
  final _hash = TextEditingController();

  bool get _web => widget.isWeb ?? kIsWeb;

  // Lazy: on web there is no dart:io environment, so no controller is built.
  DownloadController get ctl => _ctl ??= (widget.controllerFactory ??
      () => DownloadController(downloader: Downloader(), targetDir: defaultDownloadDir()))();

  @override
  void dispose() {
    _ctl?.dispose();
    _path.dispose();
    _hash.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.distro;
    if (_web) {
      return _col([
        const FilledButton(onPressed: null, child: Text('İndir')),
        _note('Tarayıcıda indirme kapalı; masaüstü uygulamayı kullan.'),
      ]);
    }
    return ListenableBuilder(
      listenable: ctl,
      builder: (context, _) => d.userSuppliedIso ? _manual(context) : _auto(context),
    );
  }

  Widget _col(List<Widget> c) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (final w in c) Padding(padding: const EdgeInsets.only(bottom: 8), child: w)],
      );

  Widget _note(String t, {Color color = kMuted}) => Text(t, style: TextStyle(color: color, height: 1.5));

  bool get _busy {
    final p = ctl.phase;
    return p == DownloadPhase.fetchingChecksum || p == DownloadPhase.downloading || p == DownloadPhase.verifying;
  }

  Widget _auto(BuildContext context) {
    final arch = widget.hostArch ?? currentIsoArch();
    final iso = arch == null ? null : widget.distro.isoFor(arch);
    final canStart = iso != null && !_busy;
    return _col([
      FilledButton(
        onPressed: canStart ? () => ctl.start(iso) : null,
        child: Text(ctl.phase == DownloadPhase.idle ? 'İndir' : 'Tekrar indir'),
      ),
      if (iso == null) _note('Bu mimari için ISO yok.'),
      ..._status(),
    ]);
  }

  Widget _manual(BuildContext context) {
    return _col([
      TextField(
        controller: _path,
        style: const TextStyle(color: kText),
        decoration: const InputDecoration(labelText: 'ISO dosyasının yolu'),
      ),
      TextField(
        controller: _hash,
        style: const TextStyle(color: kText),
        decoration: const InputDecoration(labelText: 'SHA-256 (Microsoft sayfasındaki)'),
      ),
      FilledButton(
        onPressed: _busy
            ? null
            : () => ctl.startWithManualHash(File(_path.text.trim()), _hash.text),
        child: const Text('Doğrula'),
      ),
      ..._status(),
    ]);
  }

  List<Widget> _status() {
    final c = ctl;
    switch (c.phase) {
      case DownloadPhase.idle:
        return [];
      case DownloadPhase.fetchingChecksum:
        return [_note('Sağlama dosyası alınıyor…'), _cancel()];
      case DownloadPhase.downloading:
        final t = c.total;
        final mb = (c.received / (1024 * 1024)).toStringAsFixed(1);
        return [
          LinearProgressIndicator(value: t == null || t == 0 ? null : (c.received / t).clamp(0.0, 1.0)),
          _note(t == null || t == 0 ? '$mb MB indirildi' : '%${(c.received * 100 / t).floor()}'),
          _cancel(),
        ];
      case DownloadPhase.verifying:
        return [const LinearProgressIndicator(), _note('Doğrulanıyor…')];
      case DownloadPhase.verified:
        return [
          _note('İndirildi ve doğrulandı', color: kGreen),
          if (c.file != null) SelectableText(c.file!.path, style: const TextStyle(color: kText)),
        ];
      case DownloadPhase.mismatch:
        return [
          _note(c.error ?? 'Sağlama toplamı eşleşmedi.', color: Colors.redAccent),
          SelectableText('Beklenen: ${c.expectedHash ?? '-'}', style: const TextStyle(color: kText)),
          SelectableText('Bulunan: ${c.actualHash ?? '-'}', style: const TextStyle(color: kText)),
          _retry(),
        ];
      case DownloadPhase.failed:
        return [_note(c.error ?? 'İndirme başarısız.', color: Colors.redAccent), _retry()];
      case DownloadPhase.cancelled:
        return [_note('İptal edildi.')];
    }
  }

  Widget _cancel() => OutlinedButton(onPressed: ctl.cancel, child: const Text('İptal'));

  Widget _retry() {
    if (widget.distro.userSuppliedIso) {
      return OutlinedButton(
          onPressed: () => ctl.startWithManualHash(File(_path.text.trim()), _hash.text),
          child: const Text('Tekrar dene'));
    }
    final arch = widget.hostArch ?? currentIsoArch();
    final iso = arch == null ? null : widget.distro.isoFor(arch);
    return OutlinedButton(onPressed: iso == null ? null : () => ctl.start(iso), child: const Text('Tekrar dene'));
  }
}
