import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_decision_assistant/main.dart';
import 'package:personal_decision_assistant/profile.dart';

class MemoryProfileStore implements ProfileStore {
  final categories = <ProfileCategory, String>{};
  AnswerPreferences? preferences;

  @override
  Future<ProfileSnapshot> load() async =>
      ProfileSnapshot(Map.of(categories), preferences);

  @override
  Future<void> saveCategory(ProfileCategory category, String value) async {
    categories[category] = value;
  }

  @override
  Future<void> deleteCategory(ProfileCategory category) async {
    categories.remove(category);
  }

  @override
  Future<void> savePreferences(AnswerPreferences value) async {
    preferences = value;
  }

  @override
  Future<void> deletePreferences() async {
    preferences = null;
  }
}

void main() {
  testWidgets('六类资料可留空、修改并删除', (tester) async {
    final store = MemoryProfileStore();
    await tester.pumpWidget(DecisionGuideApp(profileStore: store));
    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pumpAndSettle();

    for (final category in ProfileCategory.values) {
      expect(find.text(category.label), findsOneWidget);
    }
    expect(store.categories, isEmpty);

    await tester.tap(find.text('健康限制'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '避免剧烈运动');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(store.categories[ProfileCategory.health], '避免剧烈运动');
    expect(find.text('避免剧烈运动'), findsOneWidget);

    await tester.tap(find.text('健康限制'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '需要规律休息');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(store.categories[ProfileCategory.health], '需要规律休息');

    await tester.tap(find.text('健康限制'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除这类资料'));
    await tester.pumpAndSettle();
    expect(store.categories, isEmpty);
    expect(find.text('未填写'), findsNWidgets(6));
  });

  testWidgets('答复偏好可保存并删除', (tester) async {
    final store = MemoryProfileStore();
    await tester.pumpWidget(DecisionGuideApp(profileStore: store));
    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('答复偏好'), 200,
        scrollable: find.descendant(
          of: find.byType(ProfileScreen), matching: find.byType(Scrollable),
        ).first);
    await tester.tap(find.text('答复偏好'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('简短').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('详细').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(store.preferences?.length, '详细');

    await tester.scrollUntilVisible(find.text('答复偏好'), 200,
        scrollable: find.descendant(
          of: find.byType(ProfileScreen), matching: find.byType(Scrollable),
        ).first);
    await tester.tap(find.text('答复偏好'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除答复偏好'));
    await tester.pumpAndSettle();
    expect(store.preferences, isNull);
    expect(find.text('未设置'), findsOneWidget);
  });
}
