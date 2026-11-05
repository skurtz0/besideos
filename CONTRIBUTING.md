# Contributing

- `flutter pub get && dart run tool/build_l10n.dart && flutter analyze && flutter test` must pass.
- New user-visible strings go through `tr(...)`; run `dart run tool/build_l10n.dart` and commit `assets/l10n`.
- Catalog changes: edit `assets/catalog/catalog.json`, then `python3 tool/build_llms_full.py`. ISO links are refreshed by `python3 tool/update_catalog.py`.
- Never run `apply-plan.ps1 -Execute` on a machine you cannot afford to repair.
