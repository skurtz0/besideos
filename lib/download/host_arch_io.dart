import 'dart:ffi' show Abi;

import '../catalog/distro.dart';

IsoArch? currentIsoArch() {
  final n = Abi.current().toString();
  if (n.endsWith('arm64')) return IsoArch.arm64;
  if (n.endsWith('x64')) return IsoArch.x86_64;
  return null;
}
