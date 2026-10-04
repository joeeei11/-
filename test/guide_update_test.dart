import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_decision_assistant/guide.dart';
import 'package:personal_decision_assistant/guide_update.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final official = Uri.parse(
      'https://github.com/eternity4719/HowToLiveBetter/releases/download/v2/guide.json');

  test('只接受官方 Release 中的指南包资产', () async {
    final updater = GuideUpdater(
        fetch: (_) async => utf8.encode(jsonEncode({
              'tag_name': 'v2',
              'assets': [
                {
                  'name': 'guide.json',
                  'browser_download_url': official.toString()
                }
              ],
            })));
    expect((await updater.checkLatest()).downloadUrl, official);

    final other = GuideUpdater(
        fetch: (_) async => utf8.encode(jsonEncode({
              'tag_name': 'v2',
              'assets': [
                {
                  'name': 'guide.json',
                  'browser_download_url': 'https://example.com/guide.json'
                }
              ],
            })));
    await expectLater(other.checkLatest(), throwsFormatException);

    final missing = GuideUpdater(fetch: (_) async => utf8.encode(jsonEncode({
          'tag_name': 'epub-latest',
          'assets': [
            {'name': 'HowToLiveBetter.epub'}
          ],
        })));
    await expectLater(missing.checkLatest(), throwsA(isA<NoCompatibleGuideRelease>()));
  });

  test('无效更新不会替换原有指南包', () async {
    final storage = await Directory.systemTemp.createTemp('guide-update-test-');
    addTearDown(() => storage.delete(recursive: true));
    final installed = File('${storage.path}/guide.json');
    await installed.writeAsString('original');
    final invalid = GuideUpdater(
      storage: storage,
      fetch: (_) async => utf8.encode('{"version":"v2","entries":[]}'),
    );
    await expectLater(
        invalid.install(GuideRelease('v2', official)), throwsFormatException);
    expect(await installed.readAsString(), 'original');

    final wrongVersion = GuideUpdater(
      storage: storage,
      fetch: (_) async => utf8.encode(jsonEncode({
        'version': 'v1',
        'updatedAt': '2026-10-05',
        'project': 'HowToLiveBetter',
        'projectUrl': 'https://github.com/eternity4719/HowToLiveBetter',
        'license': 'CC BY 4.0',
        'licenseUrl': 'https://creativecommons.org/licenses/by/4.0/',
        'entries': [
          {
            'id': '1-1',
            'chapter': '1',
            'title': 'title',
            'summary': 'summary',
            'cost': 'cost',
            'evidence': 'A',
            'source': 'source',
            'sourcePath': 'book/1.md'
          }
        ],
      })),
    );
    await expectLater(wrongVersion.install(GuideRelease('v2', official)),
        throwsFormatException);
    expect(await installed.readAsString(), 'original');
  });

  test('确认后的有效版本写入本地并可读取', () async {
    final storage = await Directory.systemTemp.createTemp('guide-install-test-');
    addTearDown(() => storage.delete(recursive: true));
    final data = jsonDecode(await rootBundle.loadString('assets/guide.json'))
        as Map<String, dynamic>;
    data['version'] = 'v2';
    final updater = GuideUpdater(
      storage: storage,
      fetch: (_) async => utf8.encode(jsonEncode(data)),
    );
    final guide = await updater.install(GuideRelease('v2', official));
    expect(guide.entries.length, 657);
    expect(guide.version, 'v2');
    expect(
        GuidePackage.parse(await File('${storage.path}/guide.json').readAsString())
            .version,
        'v2');
  });
}
