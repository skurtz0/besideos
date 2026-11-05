import 'dart:convert';
import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart';

import 'install_lang_stub.dart' if (dart.library.io) 'install_lang_io.dart';

/// One language the site and the app are shown in.
class AppLang {
  const AppLang(this.code, this.name, this.locale);

  /// File name of the language in assets/l10n/<code>.json (Turkish, the source language, has none).
  final String code;

  /// The language's own name, as the picker shows it.
  final String name;
  final Locale locale;
  bool get rtl => locale.languageCode == 'ar';
}

/// The 20 languages, in the order the picker lists them. Turkish is the source language of every text in the code.
const kLangs = <AppLang>[
  AppLang('tr', 'Türkçe', Locale('tr')),
  AppLang('en', 'English', Locale('en')),
  AppLang('de', 'Deutsch', Locale('de')),
  AppLang('fr', 'Français', Locale('fr')),
  AppLang('es', 'Español', Locale('es')),
  AppLang('it', 'Italiano', Locale('it')),
  AppLang('pt-BR', 'Português (Brasil)', Locale('pt', 'BR')),
  AppLang('ru', 'Русский', Locale('ru')),
  AppLang(
      'zh-CN',
      '简体中文',
      Locale.fromSubtags(
          languageCode: 'zh', scriptCode: 'Hans', countryCode: 'CN')),
  AppLang(
      'zh-TW',
      '繁體中文',
      Locale.fromSubtags(
          languageCode: 'zh', scriptCode: 'Hant', countryCode: 'TW')),
  AppLang('ja', '日本語', Locale('ja')),
  AppLang('ko', '한국어', Locale('ko')),
  AppLang('ar', 'العربية', Locale('ar')),
  AppLang('pl', 'Polski', Locale('pl')),
  AppLang('vi', 'Tiếng Việt', Locale('vi')),
  AppLang('ms', 'Bahasa Melayu', Locale('ms')),
  AppLang('fi', 'Suomi', Locale('fi')),
  AppLang('et', 'Eesti', Locale('et')),
  AppLang('uk', 'Українська', Locale('uk')),
  AppLang('hi', 'हिन्दी', Locale('hi')),
];

AppLang langByCode(String code) =>
    kLangs.firstWhere((l) => l.code == code, orElse: () => kLangs.first);

/// The language that fits the person's preferences best; English when none of the 20 matches.
AppLang detectLang(Iterable<Locale> preferred) {
  for (final p in preferred) {
    switch (p.languageCode) {
      case 'zh':
        final tw = p.scriptCode == 'Hant' ||
            const {'TW', 'HK', 'MO'}.contains(p.countryCode);
        return langByCode(tw ? 'zh-TW' : 'zh-CN');
      case 'pt':
        return langByCode('pt-BR');
      case 'nb' || 'nn' || 'no':
        continue;
      default:
        for (final l in kLangs) {
          if (l.locale.languageCode == p.languageCode) return l;
        }
    }
  }
  return langByCode('en');
}

/// Holds the current language and its texts. Texts are looked up by their Turkish wording; a text a language does not
/// have yet is shown in Turkish, so nothing ever shows up blank.
class L10n extends ChangeNotifier {
  L10n._();
  static final L10n instance = L10n._();

  AppLang _lang = kLangs.first;
  Map<String, String> _texts = const {};

  AppLang get lang => _lang;
  Locale get locale => _lang.locale;

  /// Picks the language: the one chosen in the installer when there is one, otherwise the system (or browser)
  /// preferences. Tests skip this and stay in Turkish.
  Future<void> init({Iterable<Locale>? preferred, String? installed}) {
    final fromInstaller = installed ?? installedLangCode();
    if (fromInstaller != null && kLangs.any((l) => l.code == fromInstaller)) {
      return select(langByCode(fromInstaller));
    }
    return select(detectLang(preferred ?? PlatformDispatcher.instance.locales));
  }

  Future<void> select(AppLang lang) async {
    _texts = lang.code == 'tr' ? const {} : await _load(lang.code);
    _lang = lang;
    notifyListeners();
    _rebuildAll();
  }

  Future<Map<String, String>> _load(String code) async {
    try {
      final raw =
          jsonDecode(await rootBundle.loadString('assets/l10n/$code.json'))
              as Map<String, dynamic>;
      return raw.map((k, v) => MapEntry(k, '$v'));
    } catch (_) {
      return const {};
    }
  }

  String t(String key, [Map<String, Object?>? args]) {
    var s = _texts[key] ?? key;
    if (args != null) {
      args.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
    }
    return s;
  }

  // Const widgets do not rebuild on their own when the language changes; rebuild everything once.
  void _rebuildAll() {
    final binding = WidgetsBinding.instance;
    binding.addPostFrameCallback((_) {
      void visit(Element e) {
        e.markNeedsBuild();
        e.visitChildren(visit);
      }

      binding.rootElement?.visitChildren(visit);
    });
    binding.scheduleFrame();
  }
}

/// Text in the current language. [key] is the Turkish wording; {name} placeholders are filled from [args].
String tr(String key, [Map<String, Object?>? args]) =>
    L10n.instance.t(key, args);

const _foldGroups = <String, String>{
  'a': 'àáâãäåāăąạảấầẩẫậắằẳẵặ',
  'c': 'çćč',
  'd': 'đď',
  'e': 'èéêëēęěẹẻẽếềểễệ',
  'g': 'ğ',
  'i': 'ìíîïīıịỉĩ',
  'l': 'ł',
  'n': 'ñńň',
  'o': 'òóôõöøōơọỏốồổỗộớờởỡợ',
  'r': 'ř',
  's': 'śšşș',
  't': 'ťţț',
  'u': 'ùúûüūůưụủũứừửữự',
  'y': 'ýÿỳỵỷỹ',
  'z': 'źżž',
};

final _fold = <String, String>{
  for (final e in _foldGroups.entries)
    for (final ch in e.value.split('')) ch: e.key,
  'ß': 'ss',
};

/// Letters with marks (ü, ç, ł, ế ...) written as plain ASCII letters. Anything else is left as it is.
String foldToAscii(String s) {
  final b = StringBuffer();
  for (final ch in s.split('')) {
    if (ch == 'İ') {
      b.write('I');
      continue;
    }
    final lower = ch.toLowerCase();
    final f = _fold[lower];
    if (f == null) {
      b.write(ch);
    } else {
      b.write(lower == ch ? f : f.toUpperCase());
    }
  }
  return b.toString();
}

bool _isAscii(String s) => s.runes.every((r) => r >= 0x20 && r <= 0x7E);

/// Arabic and the Indic scripts need shaping that GRUB's own font does not do, so GRUB shows English there.
bool _grubCannotShow(AppLang l) => l.code == 'ar' || l.code == 'hi';

/// The name of the installer entry in a boot menu, e.g. "Debian Installation". The firmware (UEFI) menu, and the Windows
/// script that writes it, only take plain ASCII ([ascii]): the language's wording with marks folded away, or English
/// when its letters do not fit. GRUB takes any text its font can draw.
String bootEntryTitle(String name, {required bool ascii}) {
  final english = '$name installer';
  final local = tr('{name} kurulumu', {'name': name});
  if (ascii) {
    final f = foldToAscii(local);
    return _isAscii(f) ? f : foldToAscii(english);
  }
  return _grubCannotShow(L10n.instance.lang) ? english : local;
}

/// The entry in the installer's GRUB menu that goes back to Windows, written the same way as [bootEntryTitle].
String backToWindowsLabel({required bool ascii}) {
  final local = tr('Windows (kurulumdan vazgeç)');
  const english = 'Windows (cancel installation)';
  if (ascii) {
    final f = foldToAscii(local);
    return _isAscii(f) ? f : english;
  }
  return _grubCannotShow(L10n.instance.lang) ? english : local;
}
