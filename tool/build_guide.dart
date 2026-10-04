import 'dart:convert';
import 'dart:io';

const sourceCommit = 'b4048d14960fec19c0367f8c0e6891f2b038c7ef';

void main(List<String> args) {
  if (args.length != 2) {
    stderr.writeln(
        'Usage: dart run tool/build_guide.dart <source book dir> <output json>');
    exitCode = 64;
    return;
  }

  final book = Directory(args[0]);
  final files = book
      .listSync()
      .whereType<File>()
      .where((file) => file.path.endsWith('.md'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  final entries = <Map<String, String>>[];
  final heading = RegExp(r'^### (\d+)\. (.+)$');
  final chapterHeading = RegExp(r'^# (\d+)\. (.+)$');
  final field = RegExp(r'^- (成本|说人话|收益|证据等级|来源|备注)：(.+)$');

  for (final file in files) {
    final lines = file.readAsLinesSync();
    final chapterLine = lines.firstWhere(
      (line) => chapterHeading.hasMatch(line),
      orElse: () => throw FormatException('No chapter heading: ${file.path}'),
    );
    final chapterMatch = chapterHeading.firstMatch(chapterLine)!;
    final chapter = '${chapterMatch[1]}. ${chapterMatch[2]}';
    final chapterNumber = int.parse(chapterMatch[1]!);
    Map<String, String>? entry;

    void finishEntry() {
      final current = entry;
      if (current == null) return;
      for (final key in ['cost', 'evidence', 'source', 'summary']) {
        if ((current[key] ?? '').trim().isEmpty) {
          throw FormatException(
              'Missing $key in ${current['id']} (${file.path})');
        }
      }
      entries.add(current);
    }

    for (final line in lines) {
      final match = heading.firstMatch(line);
      if (match != null) {
        finishEntry();
        final number = int.parse(match[1]!);
        entry = {
          'id': '$chapterNumber-$number',
          'chapter': chapter,
          'title': match[2]!.trim(),
          'sourcePath': 'book/${file.uri.pathSegments.last}',
        };
        continue;
      }
      if (entry == null) continue;
      final value = field.firstMatch(line);
      if (value == null) continue;
      final key = switch (value[1]) {
        '成本' => 'cost',
        '说人话' => 'summary',
        '收益' => 'benefit',
        '证据等级' => 'evidence',
        '来源' => 'source',
        '备注' => 'note',
        _ => throw StateError('Unknown field'),
      };
      entry[key] = value[2]!.trim();
    }
    finishEntry();
  }

  if (entries.length != 657 ||
      entries.map((e) => e['id']).toSet().length != entries.length) {
    throw FormatException(
        'Expected 657 unique entries, found ${entries.length}');
  }

  final output = File(args[1]);
  output.parent.createSync(recursive: true);
  output.writeAsStringSync(jsonEncode({
    'version': sourceCommit,
    'updatedAt': '2026-10-04',
    'project': 'HowToLiveBetter',
    'projectUrl': 'https://github.com/eternity4719/HowToLiveBetter',
    'license': 'CC BY 4.0',
    'licenseUrl': 'https://creativecommons.org/licenses/by/4.0/',
    'entries': entries,
  }));
  stdout.writeln('Wrote ${entries.length} entries to ${output.path}');
}
