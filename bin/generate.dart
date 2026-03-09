// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';
import 'package:yaml/yaml.dart';
import 'package:path/path.dart' as p;
import 'package:args/args.dart';

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Shows the usage and exits the script',
    )
    ..addOption(
      'out',
      abbr: 'o',
      defaultsTo: 'lib',
      help: 'Target directory for the generated file',
    )
    ..addOption(
      'type',
      abbr: 't',
      allowed: ['main', 'dev', 'both'],
      defaultsTo: 'main',
      help: 'Filters which dependencies are exported',
    );

  final ArgResults argResults;
  try {
    argResults = parser.parse(args);
  } on FormatException catch (e) {
    print(e.message);
    print('');
    print('Usage: dart run static_licenses:generate [options]');
    print(parser.usage);
    exit(64);
  }

  if (argResults.flag('help')) {
    print('Usage: dart run static_licenses:generate [options]');
    print('');
    print(
      'Generates a Dart file containing all licenses of the used packages.',
    );
    print('');
    print('Options:');
    print(parser.usage);
    exit(0);
  }

  final outputDir = argResults.option('out') as String;
  final dependencyType = argResults.option('type') as String;

  await generateLicenses(
    workingDirectory: Directory.current.path,
    outputDir: outputDir,
    dependencyType: dependencyType,
  );
}

Future<void> generateLicenses({
  required String workingDirectory,
  required String outputDir,
  required String dependencyType,
}) async {
  print('Reading pubspec.lock and filtering dependencies...');

  // 1. Read and parse pubspec.lock
  final lockFile = File(p.join(workingDirectory, 'pubspec.lock'));
  if (!lockFile.existsSync()) {
    print('Error: pubspec.lock not found. Please run "flutter pub get".');
    exit(64);
  }

  final lockContent = await lockFile.readAsString();
  final yamlDoc = loadYaml(lockContent);
  final lockPackages = yamlDoc['packages'] as YamlMap;

  // Set of all package names we want to keep
  final Set<String> validPackages = {};

  for (final entry in lockPackages.entries) {
    final packageName = entry.key as String;
    final packageInfo = entry.value as YamlMap;
    final typeInLockfile = packageInfo['dependency'] as String;

    bool keep = true;
    if (dependencyType == 'main') {
      keep = typeInLockfile != 'direct dev';
    } else if (dependencyType == 'dev') {
      keep = typeInLockfile != 'direct main';
    }

    if (keep) {
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

    // First try standard names
    for (final fileName in ['LICENSE', 'LICENSE.txt', 'LICENSE.md']) {
      final file = File(p.join(packageDir.path, fileName));
      if (file.existsSync()) {
        licenseFile = file;
        break;
      }
    }

    // fallback: list directory and find file starting with "license" (case-insensitive)
    if (licenseFile == null && packageDir.existsSync()) {
      try {
        final entities = packageDir.listSync();
        for (final entity in entities) {
          if (entity is File) {
            final basename = p.basename(entity.path).toLowerCase();
            if (basename.startsWith('license')) {
              licenseFile = entity;
              break;
            }
          }
        }
      } catch (_) {
        // Ignore read errors
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
