import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';

import 'package:besideos_site/l10n/l10n.dart';

final _ph = RegExp(r'\{[A-Za-z0-9_]+\}');

void main() {
  test('the language follows the preferred locales; English when none of the 20 matches', () {
    expect(detectLang(const [Locale('tr', 'TR')]).code, 'tr');
    expect(detectLang(const [Locale('de', 'AT')]).code, 'de');
    expect(detectLang(const [Locale('pt', 'PT')]).code, 'pt-BR');
    expect(detectLang(const [Locale('ar', 'EG')]).code, 'ar');
    expect(detectLang(const [Locale('sv'), Locale('fi')]).code, 'fi'); // first language that is offered
    expect(detectLang(const [Locale('sv')]).code, 'en');
    expect(detectLang(const []).code, 'en');
  });

  test('Chinese goes to the traditional text for Taiwan, Hong Kong, Macau and Hant, otherwise simplified', () {
    expect(detectLang(const [Locale('zh', 'TW')]).code, 'zh-TW');
    expect(detectLang(const [Locale('zh', 'HK')]).code, 'zh-TW');
    expect(detectLang([Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant')]).code, 'zh-TW');
    expect(detectLang(const [Locale('zh', 'CN')]).code, 'zh-CN');
    expect(detectLang(const [Locale('zh')]).code, 'zh-CN');
  });

  test('the 20 languages are listed once, with Arabic as the only right-to-left one', () {
    expect(kLangs.length, 20);
    expect(kLangs.map((l) => l.code).toSet().length, 20);
    expect(kLangs.where((l) => l.rtl).map((l) => l.code), ['ar']);
  });

  test('every language except the Turkish source has a text file', () {
    for (final l in kLangs.where((l) => l.code != 'tr')) {
      expect(File('assets/l10n/${l.code}.json').existsSync(), isTrue, reason: l.code);
    }
  });

  testWidgets('choosing a language swaps the texts, and Turkish brings the source back', (t) async {
    await t.runAsync(() => L10n.instance.select(langByCode('ja')));
    expect(tr('Ana sayfa'), 'ホーム');
    expect(tr('Disk {n}', {'n': 2}), 'ディスク 2');
    await t.runAsync(() => L10n.instance.select(langByCode('tr')));
    expect(tr('Ana sayfa'), 'Ana sayfa');
  });

  test('every shown text of the catalog is in the key list, so it can be translated', () {
    final cat = jsonDecode(File('assets/catalog/catalog.json').readAsStringSync()) as Map<String, dynamic>;
    final keys = File('tool/l10n_keys_catalog.txt').readAsLinesSync().toSet();
    void need(Object? s) {
      if (s is String && s.isNotEmpty) expect(keys, contains(s));
    }

    for (final d in (cat['distros'] as List).cast<Map<String, dynamic>>()) {
      for (final k in ['tagline', 'description', 'bestFor', 'look', 'license']) {
        need(d[k]);
      }
      (d['requirements'] as List).forEach(need);
      for (final s in (d['screens'] as List? ?? const []).cast<Map<String, dynamic>>()) {
        need(s['caption']);
      }
      for (final v in (d['variants'] as List? ?? const []).cast<Map<String, dynamic>>()) {
        need(v['label']);
        need(v['note']);
        for (final s in (v['screens'] as List? ?? const []).cast<Map<String, dynamic>>()) {
          need(s['caption']);
        }
      }
    }
  });

  test('marks are folded away for the plain-ASCII firmware menu', () {
    expect(foldToAscii('Instalación de Zorin'), 'Instalacion de Zorin');
    expect(foldToAscii('Çalıştır İyi Ğ ß'), 'Calistir Iyi G ss');
    expect(foldToAscii('Cài đặt Ubuntu'), 'Cai dat Ubuntu');
    expect(foldToAscii('Instalacja łódź'), 'Instalacja lodz');
    expect(foldToAscii('日本語'), '日本語');
  });

  testWidgets('boot menu names follow the language: ASCII for the firmware, English where the letters do not fit', (t) async {
    Future<(String, String, String, String)> names(String code) async {
      await t.runAsync(() => L10n.instance.select(langByCode(code)));
      return (
        bootEntryTitle('Debian', ascii: true),
        bootEntryTitle('Debian', ascii: false),
        backToWindowsLabel(ascii: true),
        backToWindowsLabel(ascii: false),
      );
    }

    expect(await names('tr'), ('Debian kurulumu', 'Debian kurulumu', 'Windows (kurulumdan vazgec)', 'Windows (kurulumdan vazgeç)'));
    expect(await names('fr'), ('Installation de Debian', 'Installation de Debian', "Windows (annuler l'installation)", "Windows (annuler l'installation)"));
    expect((await names('es')).$3, 'Windows (cancelar la instalacion)');
    // Cyrillic and CJK: GRUB can draw them, the firmware menu cannot
    final ru = await names('ru');
    expect(ru.$1, 'Debian installer');
    expect(ru.$2, 'Установка Debian');
    expect(ru.$3, 'Windows (cancel installation)');
    expect((await names('ja')).$2, 'Debian のインストール');
    // Arabic and Hindi need shaping GRUB's font does not do: English there too
    expect((await names('ar')).$2, 'Debian installer');
    expect((await names('hi')).$4, 'Windows (cancel installation)');
    await t.runAsync(() => L10n.instance.select(langByCode('tr')));
  });

  test('Turkish is the source: texts come back unchanged and placeholders are filled', () {
    expect(tr('Seç'), 'Seç');
    expect(tr('{n} GB boş', {'n': 5}), '5 GB boş');
  });

  final keys = [
    ...File('tool/l10n_keys.txt').readAsLinesSync().where((l) => l.isNotEmpty),
    ...File('tool/l10n_keys_catalog.txt').readAsLinesSync().where((l) => l.isNotEmpty),
  ];
  for (final f in Directory('assets/l10n').listSync().whereType<File>().where((f) => f.path.endsWith('.json'))) {
    final code = f.uri.pathSegments.last.replaceAll('.json', '');
    test('$code has every text, none empty, and keeps the {placeholders}', () {
      final m = (jsonDecode(f.readAsStringSync()) as Map<String, dynamic>).cast<String, String>();
      expect(m.keys.toList(), keys);
      for (final k in keys) {
        expect(m[k]!.trim(), isNotEmpty, reason: k);
        final want = (_ph.allMatches(k).map((x) => x[0]!).toList()..sort()).join();
        final got = (_ph.allMatches(m[k]!).map((x) => x[0]!).toList()..sort()).join();
        expect(got, want, reason: '$code: $k');
      }
    });
  }
}
