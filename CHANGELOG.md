## 1.0.0
* Initial release.
* Added CLI tool to generate a static, zero-dependency `licenses.g.dart` file.
* Supports filtering dependencies by type (`main`, `dev`, `both`).
* Custom output directory support via `--out`.
* Made the package pure Dart by removing the Flutter dependency to support server/CLI apps.