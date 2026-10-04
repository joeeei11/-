import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_decision_assistant/guide.dart';
import 'package:personal_decision_assistant/main.dart';

void main() {
  late Directory storage;

  setUpAll(() async {
    storage = await Directory.systemTemp.createTemp('guide-test-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => storage.path,
    );
  });

  tearDownAll(() async {
    await storage.delete(recursive: true);
  });

  testWidgets('离线搜索后可阅读带出处的指南条目', (tester) async {
    final guide = (await tester.runAsync(GuidePackage.load))!;
    expect(guide.entries.length, 657);
    expect(
        guide.entries.every((entry) =>
            entry.chapter.isNotEmpty &&
            entry.cost.isNotEmpty &&
            entry.evidence.isNotEmpty &&
            entry.source.isNotEmpty),
        isTrue);

    await tester.pumpWidget(DecisionGuideApp(guide: guide));
    await tester.pumpAndSettle();
    expect(find.text('咨询'), findsWidgets);
    expect(find.text('记录'), findsWidgets);
    expect(find.text('资料'), findsWidgets);
    expect(find.text('指南'), findsWidgets);

    await tester.enterText(find.byType(TextField), '下午两点以后不碰咖啡因');
    await tester.pumpAndSettle();
    expect(find.text('1 条'), findsOneWidget);
    await tester.tap(find.widgetWithText(ListTile, '下午两点以后不碰咖啡因'));
    await tester.pumpAndSettle();
    expect(find.text('成本'), findsOneWidget);
    expect(find.text('证据等级'), findsOneWidget);
    expect(find.text('来源'), findsOneWidget);
    expect(find.textContaining('Drake'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('指南版本'),
      300,
      scrollable: find
          .descendant(
            of: find.byType(GuideEntryScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('指南版本'), findsOneWidget);
  });

  testWidgets('指南页可核查完整署名与许可', (tester) async {
    final guide = (await tester.runAsync(GuidePackage.load))!;
    await tester.pumpWidget(DecisionGuideApp(guide: guide));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.info_outline));
    await tester.pumpAndSettle();
    expect(find.text('指南包信息'), findsOneWidget);
    expect(find.text('更新日期'), findsOneWidget);
    expect(find.text('HowToLiveBetter'), findsOneWidget);
    expect(find.text('CC BY 4.0'), findsOneWidget);
    expect(find.text('检查官方更新'), findsOneWidget);
  });
}
