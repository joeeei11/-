import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_decision_assistant/consultation.dart';
import 'package:personal_decision_assistant/decision_records.dart';
import 'package:personal_decision_assistant/guide.dart';
import 'package:personal_decision_assistant/model_connection.dart';
import 'package:personal_decision_assistant/profile.dart';

class MemoryRecords implements DecisionRecordStore {
  final entries = <DecisionRecord>[];
  bool asked = false;

  @override
  Future<List<DecisionRecord>> load() async => List.of(entries);
  @override
  Future<void> save(DecisionRecord record) async {
    entries.removeWhere((item) => item.id == record.id);
    entries.insert(0, record);
  }

  @override
  Future<void> delete(String id) async =>
      entries.removeWhere((item) => item.id == id);
  @override
  Future<bool> hasRequestedNotificationPermission() async => asked;
  @override
  Future<void> markNotificationPermissionRequested() async {
    asked = true;
  }
}

class MemoryReminder implements ReviewReminder {
  int permissionCalls = 0;
  final scheduled = <String, DateTime>{};
  @override
  Future<bool> requestPermission() async {
    permissionCalls++;
    return true;
  }

  @override
  Future<bool> schedule(String id, DateTime date) async {
    scheduled[id] = date;
    return true;
  }

  @override
  Future<void> cancel(String id) async {
    scheduled.remove(id);
  }

  @override
  Future<bool> openedFromReminder() async => false;
}

class MemoryProfiles implements ProfileStore {
  @override
  Future<ProfileSnapshot> load() async =>
      const ProfileSnapshot({ProfileCategory.health: '避免剧烈运动'}, null);
  @override
  Future<void> saveCategory(ProfileCategory category, String value) async {}
  @override
  Future<void> deleteCategory(ProfileCategory category) async {}
  @override
  Future<void> savePreferences(AnswerPreferences preferences) async {}
  @override
  Future<void> deletePreferences() async {}
}

class MemoryDraft implements QuestionDraftStore {
  @override
  Future<String?> load() async => null;
  @override
  Future<void> save(String question) async {}
  @override
  Future<void> delete() async {}
}

class PersonalizedAnswer extends ConsultationService {
  PersonalizedAnswer() : super(ModelClient(SecureModelStore()));
  @override
  Future<List<ProfileClarification>> clarify(
          String question, GuidePackage guide) async =>
      [const ProfileClarification(ProfileCategory.health, '是否有健康限制？')];
  @override
  Future<DecisionAnswer> answer(String question, GuidePackage guide,
          {Map<ProfileCategory, String> selectedProfile = const {},
          RiskRoute? route}) async =>
      DecisionAnswer(
          conclusion: '先散步',
          nextStep: '今天散步十分钟',
          reason: '按当前限制调整',
          risk: '不适时停止',
          reviewDate: '2030-10-12',
          citations: const [],
          unknown: '没有指南依据',
          usedProfileFields: selectedProfile.keys.toList());
}

const guide = GuidePackage(
    version: 'v1',
    updatedAt: '2026-10-05',
    project: 'HowToLiveBetter',
    projectUrl: '',
    license: 'CC BY 4.0',
    licenseUrl: '',
    entries: []);

DecisionRecord sampleRecord({DateTime? date}) => DecisionRecord(
    id: '1',
    question: '我该如何运动？',
    answer: const DecisionAnswer(
        conclusion: '先散步',
        nextStep: '今天散步',
        reason: '适度活动',
        risk: '注意不适',
        reviewDate: '2030-10-12',
        citations: [],
        unknown: '没有指南依据',
        usedProfileFields: [ProfileCategory.health]),
    finalChoice: '先散步',
    guideVersion: 'v1',
    profileSnapshot: const {ProfileCategory.health: '避免剧烈运动'},
    savedAt: DateTime(2026, 10, 5),
    reviewDate: date);

void main() {
  test('决策记录序列化保留当次资料，删除记录后快照一起消失', () async {
    final store = MemoryRecords();
    final restored = DecisionRecord.fromJson(sampleRecord().toJson());
    expect(restored.profileSnapshot, {ProfileCategory.health: '避免剧烈运动'});
    expect(restored.answer.usedProfileFields, [ProfileCategory.health]);
    await store.save(restored);
    await store.delete(restored.id);
    expect(await store.load(), isEmpty);
  });

  test('仅首次保存带日期的记录请求权限，结束时取消提醒', () async {
    final store = MemoryRecords();
    final reminder = MemoryReminder();
    final noDate = sampleRecord();
    expect(await syncReviewReminder(noDate, store, reminder), isTrue);
    expect(reminder.permissionCalls, 0);
    final dated = sampleRecord(date: DateTime(2030, 10, 12));
    expect(await syncReviewReminder(dated, store, reminder), isTrue);
    expect(
        await syncReviewReminder(
            dated.copyWith(reviewDate: DateTime(2030, 10, 13)),
            store,
            reminder),
        isTrue);
    expect(reminder.permissionCalls, 1);
    expect(reminder.scheduled['1'], DateTime(2030, 10, 13));
    await syncReviewReminder(
        dated.copyWith(status: ReviewStatus.ended), store, reminder);
    expect(reminder.scheduled, isEmpty);
  });

  testWidgets('从个性化答复保存后可在记录中复查并删除', (tester) async {
    final store = MemoryRecords();
    final reminder = MemoryReminder();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ConsultationScreen(
      guide: guide,
      service: PersonalizedAnswer(),
      profileStore: MemoryProfiles(),
      draftStore: MemoryDraft(),
      recordStore: store,
      reminder: reminder,
      onBrowseGuide: () {},
      onOpenEntry: (_, __) {},
    ))));
    await tester.enterText(find.byType(TextField).first, '我该如何运动？');
    await tester.tap(find.text('开始分析'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('继续获得答复'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('保存为决策记录'), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('保存为决策记录'));
    await tester.pumpAndSettle();
    expect(find.text('2030-10-12'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '保存').last);
    await tester.pumpAndSettle();
    expect(store.entries.single.profileSnapshot,
        {ProfileCategory.health: '避免剧烈运动'});
    expect(reminder.permissionCalls, 1);

    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: RecordsScreen(store: store, reminder: reminder))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('我该如何运动？'));
    await tester.pumpAndSettle();
    expect(find.text('避免剧烈运动'), findsNothing);
    await tester.ensureVisible(find.text('当次已用资料'));
    await tester.tap(find.text('当次已用资料'));
    await tester.pumpAndSettle();
    expect(find.text('避免剧烈运动'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('结束'), 300,
        scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text('结束'));
    await tester.pumpAndSettle();
    expect(store.entries.single.status, ReviewStatus.ended);
    expect(reminder.scheduled, isEmpty);
    await tester.tap(find.byTooltip('删除记录'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除').last);
    await tester.pumpAndSettle();
    expect(store.entries, isEmpty);
  });
}
