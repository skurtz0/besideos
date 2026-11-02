import 'package:flutter/material.dart';

const kBg = Color(0xFF181C26);
const kPanel = Color(0xFF212736);
const kPanel2 = Color(0xFF2A3042);
const kText = Color(0xFFF5F7FA);
const kMuted = Color(0xFFAEB7C8);
const kAccent = Color(0xFF60A5FF);
const kGreen = Color(0xFF4ADE80);
const kWarn = Color(0xFFFBBF24);
const kDanger = Color(0xFFF87171);

/// A rounded card. [tint] colours the border and a soft gradient (e.g. a distro's accent).
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.tint, this.padding = const EdgeInsets.all(20)});
  final Widget child;
  final Color? tint;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final t = tint;
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: kPanel,
        gradient: t == null
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [t.withAlpha(60), kPanel],
              ),
        border: Border.all(color: t == null ? const Color(0x14FFFFFF) : t.withAlpha(150)),
      ),
      // Tiles inside (checkbox, expansion) paint ink on the nearest Material; without this the
      // decoration above would hide it.
      child: Material(type: MaterialType.transparency, child: child),
    );
  }
}

/// A round badge with the first letter of [name], in [color]. Stands in for a logo.
class LetterBadge extends StatelessWidget {
  const LetterBadge({super.key, required this.name, required this.color, this.size = 56});
  final String name;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      child: Text(
        name.isEmpty ? '?' : name.characters.first.toUpperCase(),
        style: TextStyle(color: Colors.white, fontSize: size * 0.48, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.icon});
  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        if (icon != null) ...[Icon(icon, color: kAccent, size: 22), const SizedBox(width: 8)],
        Expanded(child: Text(text, style: const TextStyle(color: kText, fontSize: 18, fontWeight: FontWeight.w700))),
      ]),
    );
  }
}
