# static_licenses

A minimalistic Dart/Flutter tool to statically extract and compile Open Source licenses from your project's dependencies into a generated Dart file at build-time.

## The Problem with Traditional License Parsing

Flutter provides built-in mechanisms like `showLicensePage()` and the `LicenseRegistry`. However, these approaches evaluate and parse licenses **at runtime**, which causes two primary issues:

1. **Performance Overhead**: Parsing licenses on the device consumes CPU and blocks the UI thread if not handled carefully, negatively impacting the user experience when opening the licenses page.
2. **Dynamic Generation Limits**: On constrained or highly optimized builds, relying on dynamic runtime registry extraction can be unpredictable and hard to customize if you want full control over your application's UI.

## The Advantage of `static_licenses`

`static_licenses` shifts the workload from runtime (on the user's device) to **build-time** (on your CI/CD or local machine).

- **Zero Runtime Parsing**: Licenses are pre-compiled as simple Dart strings within a generated `licenses.g.dart` file. Displaying them is as fast as rendering a static `List`.
- **Full UI Control**: You get a clean `List<PackageLicenseInfo>` containing the package name, version, and license text. You can build exactly the UI you want without fighting against the default Material/Cupertino dialogs.
- **No Dev Dependencies**: The generator automatically reads your `pubspec.lock`, filtering out `dev_dependencies`. Only the licenses of packages shipped in your app are included.
- **Testable & Reliable**: The tool interacts safely with `.dart_tool` to locate the exact license files cached on your system.

## Disadvantages of this Package
To be honest and open about disadvantages:
- **Build-time overhead**: The generator needs to read all license files, which can take some time on large projects.
- **Generated file size**: The generated file can be large on large projects.
- **Not a drop-in replacement**: This is not a drop-in replacement for the default license page. You need to build your own UI.
- **No Flutter integration**: This package does not provide any Flutter integration. You need to generate the licenses manually or integrate it into your build process.

## Getting Started

### 1. Add the Dependency

Add `static_licenses` to your `pubspec.yaml` dependencies:

```yaml
dependencies:
  static_licenses: #latest
```

### 2. Run the Generator

Run the provided script to generate the licenses file. 

```bash
dart run static_licenses:generate
```

By default, this creates a `lib/licenses.g.dart` file in your project.

**Options:**
- `--out=<path>`: Change the output directory (e.g., `--out=lib/src`). Defaults to `lib`.
- `--help` or `-h`: Shows the help menu.

### 3. Use in Your App

The generated file exposes a constant list called `allLicenses`. Simply import it and build your own UI!

```dart
import 'package:flutter/material.dart';
import 'licenses.g.dart';

class MyLicensePage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: allLicenses.length,
      itemBuilder: (context, index) {
        final license = allLicenses[index];
        return ListTile(
          title: Text(license.packageName),
          subtitle: Text('Version: ${license.version}'),
          onTap: () {
            // Show license.licenseText in a new page!
          },
        );
      },
    );
  }
}
```

Check out the `example/` folder in this repository for a complete, runnable demonstration.
