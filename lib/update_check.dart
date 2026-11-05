/// Keep equal to `version:` in pubspec.yaml (a test checks it); the release workflow checks it against the tag.
const kAppVersion = '0.1.1';
const kReleasesPage = 'https://github.com/skurtz0/besideos/releases/latest';

/// True when [latest] ("v1.2.3" or "1.2.3") is a higher x.y.z than [current].
bool isNewer(String latest, String current) {
  List<int>? p(String s) {
    final m = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)').firstMatch(s.trim());
    return m == null ? null : [for (var i = 1; i <= 3; i++) int.parse(m[i]!)];
  }

  final a = p(latest), b = p(current);
  if (a == null || b == null) return false;
  for (var i = 0; i < 3; i++) {
    if (a[i] != b[i]) return a[i] > b[i];
  }
  return false;
}

