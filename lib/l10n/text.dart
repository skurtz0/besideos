import 'package:flutter/material.dart' as m;
import 'package:flutter/widgets.dart';

import 'l10n.dart';

/// A drop-in for the framework's Text that shows its string in the current language (see [tr]); the Turkish
/// wording of the string is the key. Import it with `hide Text` on the material import.
class Text extends StatelessWidget {
  const Text(
    this.data, {
    super.key,
    this.style,
    this.textAlign,
    this.softWrap,
    this.overflow,
    this.maxLines,
    this.semanticsLabel,
    this.textScaler,
  }) : textSpan = null;

  const Text.rich(
    InlineSpan this.textSpan, {
    super.key,
    this.style,
    this.textAlign,
    this.softWrap,
    this.overflow,
    this.maxLines,
    this.semanticsLabel,
    this.textScaler,
  }) : data = null;

  final String? data;
  final InlineSpan? textSpan;
  final TextStyle? style;
  final TextAlign? textAlign;
  final bool? softWrap;
  final TextOverflow? overflow;
  final int? maxLines;
  final String? semanticsLabel;
  final TextScaler? textScaler;

  @override
  Widget build(BuildContext context) {
    if (textSpan != null) {
      return m.Text.rich(textSpan!,
          style: style,
          textAlign: textAlign,
          softWrap: softWrap,
          overflow: overflow,
          maxLines: maxLines,
          semanticsLabel: semanticsLabel,
          textScaler: textScaler);
    }
    return m.Text(tr(data!),
        style: style,
        textAlign: textAlign,
        softWrap: softWrap,
        overflow: overflow,
        maxLines: maxLines,
        semanticsLabel: semanticsLabel == null ? null : tr(semanticsLabel!),
        textScaler: textScaler);
  }
}
