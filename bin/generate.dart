import 'dart:convert';
import 'dart:io';
import 'package:yaml/yaml.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> args) async {
  await generateLicenses(workingDirectory: Directory.current.path, args: args);
}

Future<void> generateLicenses({
  required String workingDirectory,
  required List<String> args,
}) async {
  // --- NEW: Display help menu ---
  if (args.contains('--help') || args.contains('-h')) {
    print('Usage: dart run static_licenses:generate [options]');
    print('');
    print(
      'Generates a Dart file containing all licenses of the used packages.',
    );
    print('');
    print('Options:');
    print(
      '  --out=<path>   Target directory for the generated file (e.g. --out=lib/src).',
    );
    print('                 Default: "lib"');
    print('  --help, -h     Displays this help.');
    return; // Exit script without generating anything
  }

  print('Reading pubspec.lock and filtering dev dependencies...');

  // 1. Read and parse pubspec.lock
  final lockFile = File(p.join(workingDirectory, 'pubspec.lock'));
  if (!lockFile.existsSync()) {
    print('Error: pubspec.lock not found. Please run "flutter pub get".');
    return;
  }

  final lockContent = await lockFile.readAsString();
  final yamlDoc = loadYaml(lockContent);
  final lockPackages = yamlDoc['packages'] as YamlMap;

  // Set of all package names we want to keep
  final Set<String> validPackages = {};

  for (final entry in lockPackages.entries) {
    final packageName = entry.key as String;
    final packageInfo = entry.value as YamlMap;
    final dependencyType = packageInfo['dependency'] as String;

    // We explicitly ignore pure development dependencies
    if (dependencyType != 'direct dev') {
      validPackages.add(packageName);
    }
  }

  print('Reading package_config.json for file paths...');
  final configFile = File(
    p.join(workingDirectory, '.dart_tool', 'package_config.json'),
  );
  final configContent = await configFile.readAsString();
  final config = jsonDecode(configContent);
  final allPackages = config['packages'] as List<dynamic>;

  final StringBuffer generatedCode = StringBuffer();
  generatedCode.writeln('// GENERATED CODE - DO NOT MODIFY BY HAND');
  generatedCode.writeln('// ignore_for_file: unnecessary_string_escapes\n');
  generatedCode.writeln('''
/// Represents a single Open Source license.
class PackageLicenseInfo {
  final String packageName;
  final String version;
  final String licenseText;

  const PackageLicenseInfo({
    required this.packageName,
    required this.version,
    required this.licenseText,
  });
}
''');
  generatedCode.writeln('const List<PackageLicenseInfo> allLicenses = [');

  // 2. Iterate through all packages and filter
  for (final package in allPackages) {
    final name = package['name'];

    // NEW: Check if the package is in our set of valid packages
    if (!validPackages.contains(name)) continue;

    // Ignore the project itself
    final rootUriStr = package['rootUri'] as String;
    if (rootUriStr == '../') continue;

    Uri rootUri = Uri.parse(rootUriStr);
    Directory packageDir;
    if (rootUri.isAbsolute) {
      packageDir = Directory.fromUri(rootUri);
    } else {
      // Resolve relative to the .dart_tool directory
      packageDir = Directory(
        p.normalize(p.join(configFile.parent.path, rootUriStr)),
      );
    }

    File? licenseFile;
    for (final fileName in [
      'LICENSE',
      'LICENSE.txt',
      'LICENSE.md',
      'LICENSE.md',
    ]) {
      final file = File(p.join(packageDir.path, fileName));
      if (file.existsSync()) {
        licenseFile = file;
        break;
      }
    }

    if (licenseFile != null) {
      final rawText = await licenseFile.readAsString();
      final escapedText = rawText
          .replaceAll('\\', '\\\\')
          .replaceAll('\$', '\\\$')
          .replaceAll('\'', '\\\'')
          .replaceAll('\r', '');

      // Optional: Get version directly from pubspec.lock
      final version = lockPackages[name]['version'] ?? 'unknown';

      generatedCode.writeln('''
  PackageLicenseInfo(
    packageName: '$name',
    version: '$version',
    licenseText: \'\'\'$escapedText\'\'\',
  ),''');
    }
  }

  generatedCode.writeln('];');

  // --- NEW: Evaluate arguments and determine path ---
  String outputDir = 'lib'; // Default directory if none is specified

  for (final arg in args) {
    if (arg.startsWith('--out=')) {
      outputDir = arg.substring(6); // Removes "--out="
    }
  }

  // Safe path construction (handles trailing slashes)
  final normalizedDir = outputDir.endsWith('/')
      ? outputDir.substring(0, outputDir.length - 1)
      : outputDir;

  final outputFile = File(
    p.join(workingDirectory, normalizedDir, 'licenses.g.dart'),
  );

  // IMPORTANT: Ensure the target directory exists, otherwise the script will crash!
  if (!await outputFile.parent.exists()) {
    await outputFile.parent.create(recursive: true);
  }

  // Save file
  await outputFile.writeAsString(generatedCode.toString());

  print('Formatting generated code...');

  // Executes the command "dart format <path>"
  final processResult = await Process.run('dart', [
    'format',
    outputFile.path,
  ], workingDirectory: workingDirectory);

  if (processResult.exitCode == 0) {
    // exitCode 0 means the terminal command was successful
    print('Successfully generated and formatted: ${outputFile.path}');
  } else {
    // If something goes wrong, print the error from the terminal
    print('File was generated, but formatting failed:');
    print(processResult.stderr);
  }
}
