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

const _validHosts = {'windows', 'linux', 'mac-m1m2'};

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
  });

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

    final rawIsos = raw['isos'] ?? const [];
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
