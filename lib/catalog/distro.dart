import 'dart:convert';

enum DistroFamily { linux, windows }

class CatalogException implements Exception {
  final String message;
  CatalogException(this.message);
  @override
  String toString() => 'CatalogException: $message';
}

class GuideStep {
  final String title;
  final String body;
  const GuideStep({required this.title, required this.body});
}

/// A bundled picture of what the system looks like, with where it came from.
class ScreenShot {
  final String file;
  final String caption;
  final String credit;
  final String? source;
  const ScreenShot({required this.file, required this.caption, required this.credit, this.source});
}

/// One choice inside a distro (edition, desktop, live or installer image). Picked on the distro page,
/// so the catalog stays one card per distro.
class DistroVariant {
  final String id;
  final String label;
  final String note;
  final List<IsoAsset> isos;
  final List<ScreenShot> screens;
  const DistroVariant({
    required this.id,
    required this.label,
    required this.note,
    required this.isos,
    this.screens = const [],
  });
}

enum IsoArch { x86_64, arm64 }

class IsoAsset {
  final IsoArch arch;
  final String url;
  final String checksumUrl;
  final String fileName;
  final int? sizeBytes;
  const IsoAsset({
    required this.arch,
    required this.url,
    required this.checksumUrl,
    required this.fileName,
    this.sizeBytes,
  });
}

const _validHosts = {'windows', 'linux'};

class Distro {
  final String id;
  final String name;
  final DistroFamily family;
  final String tagline;
  final String description;
  final String bestFor;
  final String? desktop;
  final String? basedOn;
  final String look;
  final int accent;
  final List<GuideStep> guide;
  final List<String> requirements;
  final List<String> hosts;
  final String downloadPage;
  final bool userSuppliedIso;
  final String license;
  final List<IsoAsset> isos;
  final List<ScreenShot> screens;

  /// Choices shown on the distro page; empty = nothing to choose. [isos] mirrors the first one.
  final List<DistroVariant> variants;

  const Distro({
    required this.id,
    required this.name,
    required this.family,
    required this.tagline,
    required this.description,
    required this.bestFor,
    this.desktop,
    this.basedOn,
    required this.look,
    required this.accent,
    required this.guide,
    required this.requirements,
    required this.hosts,
    required this.downloadPage,
    required this.userSuppliedIso,
    required this.license,
    this.isos = const [],
    this.screens = const [],
    this.variants = const [],
  });

  /// This distro as it is when [v] is picked: that variant's images and, if it has any, its pictures.
  Distro withVariant(DistroVariant v) => Distro(
        id: id,
        name: name,
        family: family,
        tagline: tagline,
        description: description,
        bestFor: bestFor,
        desktop: desktop,
        basedOn: basedOn,
        look: look,
        accent: accent,
        guide: guide,
        requirements: requirements,
        hosts: hosts,
        downloadPage: downloadPage,
        userSuppliedIso: userSuppliedIso,
        license: license,
        isos: v.isos,
        screens: v.screens.isEmpty ? screens : v.screens,
        variants: variants,
      );

  IsoAsset? isoFor(IsoArch arch) => isos.where((i) => i.arch == arch).firstOrNull;

  factory Distro.fromJson(Object? raw, int index) {
    if (raw is! Map) throw CatalogException('distros[$index]: not an object');
    final rawId = raw['id'];
    if (rawId is! String || rawId.isEmpty) {
      throw CatalogException('distros[$index]: id must be a non-empty string');
    }
    final id = rawId;
    T get<T>(String f) {
      final v = raw[f];
      if (v is! T) throw CatalogException('$id: $f must be $T');
      return v;
    }

    List<String> strings(String f) {
      final l = get<List>(f);
      if (l.any((e) => e is! String)) throw CatalogException('$id: $f must be a list of strings');
      return l.cast<String>();
    }

    final familyName = get<String>('family');
    final family = DistroFamily.values.where((e) => e.name == familyName).firstOrNull;
    if (family == null) throw CatalogException('$id: family "$familyName" unknown');

    final hosts = strings('hosts');
    for (final h in hosts) {
      if (!_validHosts.contains(h)) throw CatalogException('$id: hosts has unknown value "$h"');
    }

    final desktop = raw['desktop'];
    if (desktop != null && desktop is! String) {
      throw CatalogException('$id: desktop must be String or null');
    }

    final basedOn = raw['basedOn'];
    if (basedOn != null && basedOn is! String) {
      throw CatalogException('$id: basedOn must be String or null');
    }

    final guide = get<List>('guide').map((s) {
      if (s is! Map || s['title'] is! String || s['body'] is! String) {
        throw CatalogException('$id: guide steps need string title and body');
      }
      return GuideStep(title: s['title'] as String, body: s['body'] as String);
    }).toList();

    final isos = _parseIsos(raw['isos'], id);
    final screens = _parseScreens(raw['screens'], id);

    final rawVariants = raw['variants'] ?? const [];
    if (rawVariants is! List) throw CatalogException('$id: variants must be a list');
    final variants = <DistroVariant>[];
    for (var i = 0; i < rawVariants.length; i++) {
      final e = rawVariants[i];
      final at = '$id: variants[$i]';
      if (e is! Map) throw CatalogException('$at: not an object');
      String str(String f) {
        final v = e[f];
        if (v is! String || v.isEmpty) throw CatalogException('$at.$f must be a non-empty String');
        return v;
      }

      final vid = str('id');
      if (variants.any((x) => x.id == vid)) throw CatalogException('$at.id "$vid" duplicated');
      variants.add(DistroVariant(
        id: vid,
        label: str('label'),
        note: str('note'),
        isos: List.unmodifiable(_parseIsos(e['isos'], at)),
        screens: List.unmodifiable(_parseScreens(e['screens'], at)),
      ));
    }

    return Distro(
      id: id,
      name: get<String>('name'),
      family: family,
      tagline: get<String>('tagline'),
      description: get<String>('description'),
      bestFor: get<String>('bestFor'),
      desktop: desktop as String?,
      basedOn: basedOn as String?,
      look: get<String>('look'),
      accent: get<int>('accent'),
      guide: guide,
      requirements: strings('requirements'),
      hosts: hosts,
      downloadPage: get<String>('downloadPage'),
      userSuppliedIso: get<bool>('userSuppliedIso'),
      license: get<String>('license'),
      isos: List.unmodifiable(isos),
      screens: List.unmodifiable(screens),
      variants: List.unmodifiable(variants),
    );
  }
}

class Catalog {
  final List<Distro> distros;
  const Catalog(this.distros);

  static Catalog parse(String json) {
    final Object? root;
    try {
      root = jsonDecode(json);
    } on FormatException catch (e) {
      throw CatalogException('invalid JSON: ${e.message}');
    }
    final list = root is Map ? root['distros'] : null;
    if (list is! List) throw CatalogException('distros must be a list');
    final distros = <Distro>[];
    final seen = <String>{};
    for (var i = 0; i < list.length; i++) {
      final d = Distro.fromJson(list[i], i);
      if (!seen.add(d.id)) throw CatalogException('${d.id}: duplicate id');
      distros.add(d);
    }
    return Catalog(List.unmodifiable(distros));
  }

  Distro? byId(String id) => distros.where((d) => d.id == id).firstOrNull;
}

List<IsoAsset> _parseIsos(Object? raw, String id) {
  final rawIsos = raw ?? const [];
  if (rawIsos is! List) throw CatalogException('$id: isos must be a list');
  final isos = <IsoAsset>[];
  for (var i = 0; i < rawIsos.length; i++) {
    final e = rawIsos[i];
    final at = '$id: isos[$i]';
    if (e is! Map) throw CatalogException('$at: not an object');
    String str(String f) {
      final v = e[f];
      if (v is! String) throw CatalogException('$at.$f must be String');
      return v;
    }

    String https(String f) {
      final v = str(f);
      final u = Uri.tryParse(v);
      if (u == null || u.scheme != 'https' || u.host.isEmpty) {
        throw CatalogException('$at.$f must be an https URL');
      }
      return v;
    }

    final archName = str('arch');
    final arch = IsoArch.values.where((a) => a.name == archName).firstOrNull;
    if (arch == null) throw CatalogException('$at.arch "$archName" unknown');
    final fileName = str('fileName');
    if (fileName.isEmpty || fileName.contains('/') || fileName.contains(r'\') || fileName.contains('..')) {
      throw CatalogException('$at.fileName is not a safe file name');
    }
    final size = e['sizeBytes'];
    if (size != null && (size is! int || size <= 0)) {
      throw CatalogException('$at.sizeBytes must be a positive int or null');
    }
    if (isos.any((x) => x.arch == arch)) throw CatalogException('$at.arch "$archName" duplicated');
    isos.add(IsoAsset(
      arch: arch,
      url: https('url'),
      checksumUrl: https('checksumUrl'),
      fileName: fileName,
      sizeBytes: size as int?,
    ));
  }
  return isos;
}

List<ScreenShot> _parseScreens(Object? raw, String id) {
  final rawScreens = raw ?? const [];
  if (rawScreens is! List) throw CatalogException('$id: screens must be a list');
  final screens = <ScreenShot>[];
  for (var i = 0; i < rawScreens.length; i++) {
    final e = rawScreens[i];
    final at = '$id: screens[$i]';
    if (e is! Map) throw CatalogException('$at: not an object');
    String str(String f) {
      final v = e[f];
      if (v is! String || v.isEmpty) throw CatalogException('$at.$f must be a non-empty String');
      return v;
    }

    final file = str('file');
    if (!file.startsWith('assets/screens/') || file.contains('..') || file.contains(r'\')) {
      throw CatalogException('$at.file must be under assets/screens/');
    }
    final source = e['source'];
    if (source != null && (source is! String || !source.startsWith('https://'))) {
      throw CatalogException('$at.source must be an https URL or null');
    }
    screens.add(ScreenShot(file: file, caption: str('caption'), credit: str('credit'), source: source as String?));
  }
  return screens;
}