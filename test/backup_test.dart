import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_decision_assistant/backup.dart';
import 'package:personal_decision_assistant/consultation.dart';
import 'package:personal_decision_assistant/decision_records.dart';
import 'package:personal_decision_assistant/model_connection.dart';
import 'package:personal_decision_assistant/profile.dart';

class _Profiles implements ProfileStore {
  final values = <ProfileCategory, String>{};
  AnswerPreferences? preferences;
  @override
  Future<ProfileSnapshot> load() async =>
      ProfileSnapshot(Map.of(values), preferences);
  @override
  Future<void> saveCategory(ProfileCategory category, String value) async {
    values[category] = value;
  }

  @override
  Future<void> deleteCategory(ProfileCategory category) async {
    values.remove(category);
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

class _Records implements DecisionRecordStore {
  final values = <DecisionRecord>[];
  @override
  Future<List<DecisionRecord>> load() async => List.of(values);
  @override
  Future<void> save(DecisionRecord record) async {
    values.removeWhere((e) => e.id == record.id);
    values.insert(0, record);
  }

  @override
  Future<void> delete(String id) async {
    values.removeWhere((e) => e.id == id);
  }

  @override
  Future<bool> hasRequestedNotificationPermission() async => true;
  @override
  Future<void> markNotificationPermissionRequested() async {}
}

class _Models implements ModelStore {
  bool cleared = false;
  @override
  Future<void> delete() async {
    cleared = true;
  }

  @override
  Future<ModelSettings> load() => throw UnimplementedError();
  @override
  Future<String?> readApiKey() async => 'secret-api-key';
  @override
  Future<int> reserveRequest() => throw UnimplementedError();
  @override
  Future<void> save(String baseUrl, String model, String? newApiKey,
          int dailyLimit, int answerTokenLimit) =>
      throw UnimplementedError();
}

class _Reminder implements ReviewReminder {
  @override
  Future<void> cancel(String id) async {}
  @override
  Future<bool> openedFromReminder() async => false;
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<bool> schedule(String id, DateTime date) async => true;
}

class _Picker extends BackupDocumentPicker {
  const _Picker(this.bytes);
  final List<int> bytes;
  @override
  Future<List<int>?> open() async => bytes;
}

class _FastBackupService extends BackupService {
  const _FastBackupService(
      super.profiles, super.records, super.models, super.reminders);

  @override
  Future<BackupData> inspect(List<int> bytes, String password) async =>
      const BackupData(
          ProfileSnapshot({ProfileCategory.health: '备份资料'}, null), []);
}

DecisionRecord _record() => DecisionRecord(
      id: 'r1',
      question: '如何安排休息？',
      answer: const DecisionAnswer(
        conclusion: '提前休息',
        nextStep: '今晚早睡',
        reason: '保证睡眠',
        risk: '留意疲劳',
        reviewDate: '2030-10-12',
        citations: [],
        unknown: '无',
        usedProfileFields: [ProfileCategory.health],
      ),
      finalChoice: '今晚早睡',
      guideVersion: 'v1',
      profileSnapshot: const {ProfileCategory.health: '需要休息'},
      savedAt: DateTime(2026, 10, 5),
      reviewDate: DateTime(2030, 10, 12),
    );

void main() {
  test('备份加密往返包含资料、偏好、决策记录，且不含 API Key', () async {
    final profiles = _Profiles()..values[ProfileCategory.health] = '需要休息';
    profiles.preferences =
        const AnswerPreferences(length: '简短', tone: '直接', order: '先看结论');
    final records = _Records()..values.add(_record());
    final models = _Models();
    final service = BackupService(profiles, records, models, _Reminder());
    final bytes = await service.export('strong-password');
    expect(utf8.decode(bytes), isNot(contains('需要休息')));
    expect(utf8.decode(bytes), isNot(contains('secret-api-key')));
    await expectLater(
        service.inspect(bytes, 'wrong-password'), throwsFormatException);
    expect(profiles.values[ProfileCategory.health], '需要休息');
    expect(models.cleared, isFalse);

    profiles.values[ProfileCategory.health] = '旧资料';
    profiles.values[ProfileCategory.family] = '应被覆盖';
    records.values.clear();
    await service.restore(await service.inspect(bytes, 'strong-password'));
    expect(profiles.values, {ProfileCategory.health: '需要休息'});
    expect(profiles.preferences?.length, '简短');
    expect(
        records.values.single.profileSnapshot[ProfileCategory.health], '需要休息');
    expect(models.cleared, isTrue);
  });

  testWidgets('导入需要明确确认，取消时不覆盖', (tester) async {
    final profiles = _Profiles()..values[ProfileCategory.health] = '当前资料';
    final models = _Models();
    await tester.pumpWidget(MaterialApp(
        home: BackupScreen(
      service: _FastBackupService(profiles, _Records(), models, _Reminder()),
      picker: _Picker(utf8.encode('encrypted file')),
    )));
    await tester.tap(find.text('导入加密备份'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'strong-password');
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();
    expect(find.text('覆盖当前本地数据？'), findsOneWidget);
    expect(profiles.values[ProfileCategory.health], '当前资料');
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(profiles.values[ProfileCategory.health], '当前资料');
    expect(models.cleared, isFalse);
  });
}
