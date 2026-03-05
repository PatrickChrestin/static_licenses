import 'dart:io';
import 'package:test/test.dart';
import 'package:path/path.dart' as p;

import '../bin/generate.dart' as generate;

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('static_licenses_test_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('generates expected licenses.g.dart based on mock packages', () async {
    final workingDirectory = tempDir.path;

    // 1. Create pubspec.lock
    final pubspecLock = File(p.join(workingDirectory, 'pubspec.lock'));
    await pubspecLock.writeAsString('''
packages:
  package_a:
    dependency: "direct main"
    version: "1.0.0"
  package_dev:
    dependency: "direct dev"
    version: "2.0.0"
''');

    // 2. Create mock packages and licenses
    final pkgADir = Directory(
      p.join(workingDirectory, 'mock_packages', 'package_a'),
    );
    await pkgADir.create(recursive: true);
    await File(p.join(pkgADir.path, 'LICENSE')).writeAsString('License A text');

    final pkgDevDir = Directory(
      p.join(workingDirectory, 'mock_packages', 'package_dev'),
    );
    await pkgDevDir.create(recursive: true);
    await File(
      p.join(pkgDevDir.path, 'LICENSE'),
    ).writeAsString('License Dev text');

    // 3. Create .dart_tool/package_config.json
    final dartToolDir = Directory(p.join(workingDirectory, '.dart_tool'));
    await dartToolDir.create();
    final packageConfig = File(p.join(dartToolDir.path, 'package_config.json'));

    // rootUri is relative to .dart_tool folder
    await packageConfig.writeAsString('''
{
  "configVersion": 2,
  "packages": [
    {
      "name": "package_a",
      "rootUri": "../mock_packages/package_a",
      "packageUri": "lib/",
      "languageVersion": "2.12"
    },
    {
      "name": "package_dev",
      "rootUri": "../mock_packages/package_dev",
      "packageUri": "lib/",
      "languageVersion": "2.12"
    }
  ]
}
''');

    // 4. Run the generator script
    await generate.generateLicenses(
      workingDirectory: workingDirectory,
      args: ['--out=lib/src'],
    );

    // 5. Verify the generated output
    final generatedFile = File(
      p.join(workingDirectory, 'lib/src', 'licenses.g.dart'),
    );
    expect(
      generatedFile.existsSync(),
      isTrue,
      reason: 'Generated file should exist',
    );

    final content = await generatedFile.readAsString();

    // Check if the model is injected
    expect(content, contains('class PackageLicenseInfo {'));
    expect(content, contains('final String packageName;'));
    expect(content, contains('final String version;'));
    expect(content, contains('final String licenseText;'));

    expect(content, contains('PackageLicenseInfo('));
    expect(content, contains("packageName: 'package_a'"));
    expect(content, contains("version: '1.0.0'"));
    expect(content, contains("License A text"));

    // It should omit dev dependencies
    expect(content, isNot(contains("packageName: 'package_dev'")));
    expect(content, isNot(contains("License Dev text")));
  });
}
