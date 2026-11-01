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
  });

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
