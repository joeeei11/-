import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_decision_assistant/consultation.dart';
import 'package:personal_decision_assistant/guide.dart';
import 'package:personal_decision_assistant/model_connection.dart';

class FakeModelStore implements ModelStore {
  FakeModelStore(this.url);
  final String url;
  var calls = 0;

  @override
  Future<ModelSettings> load() async => ModelSettings(
      baseUrl: url,
      model: 'test',
      hasApiKey: true,
      dailyLimit: 10,
      answerTokenLimit: 500,
      usedToday: calls);
  @override
  Future<String?> readApiKey() async => 'secret';
  @override
  Future<int> reserveRequest() async {
    calls++;
    return 500;
  }

  @override
  Future<void> save(String a, String b, String? c, int d, int e) async {}
  @override
  Future<void> delete() async {}
}

class MemoryDrafts implements QuestionDraftStore {
  String? value;
  @override
  Future<String?> load() async => value;
  @override
  Future<void> save(String question) async {
    value = question;
  }

  @override
  Future<void> delete() async {
    value = null;
  }
}

class FailingService extends ConsultationService {
  FailingService()
      : super(ModelClient(FakeModelStore('https://example.com/v1')));
  @override
  Future<DecisionAnswer> answer(String question, GuidePackage guide) async =>
      throw const ModelCallException('服务暂时不可用');
}

class SuccessfulService extends ConsultationService {
  SuccessfulService() : super(ModelClient(FakeModelStore('https://example.com/v1')));
  @override
  Future<DecisionAnswer> answer(String question, GuidePackage guide) async =>
      DecisionAnswer.parse(modelAnswer(), guide.entries);
}

class InferenceService extends ConsultationService {
  InferenceService() : super(ModelClient(FakeModelStore('https://example.com/v1')));
  @override
  Future<DecisionAnswer> answer(String question, GuidePackage guide) async =>
      const DecisionAnswer(
        conclusion: '先确认自己是否饥饿', nextStep: '按平时习惯安排一餐',
        reason: '没有适用指南，仅为一般建议', risk: '特殊情况需咨询专业人士',
        reviewDate: '2026-10-06', citations: [], unknown: '没有指南依据',
      );
}

const guide = GuidePackage(
    version: 'v1',
    updatedAt: '2026-10-05',
    project: 'HowToLiveBetter',
    projectUrl: 'https://example.com',
    license: 'CC BY 4.0',
    licenseUrl: 'https://example.com',
    entries: [
      GuideEntry(
          id: 'sleep-1',
          chapter: '睡眠',
          title: '下午不要喝咖啡',
          summary: '下午喝咖啡可能影响睡眠',
          benefit: '改善睡眠',
          cost: '少喝咖啡',
          evidence: '中',
          source: '研究',
          note: '',
          sourcePath: 'sleep.md'),
    ]);

Map<String, dynamic> modelAnswer(
        {String? citation = 'sleep-1', String route = 'ordinary'}) =>
    {
      'choices': [
        {
          'message': {
            'content': jsonEncode({
              'risk_route': route,
              'conclusion': '下午少喝咖啡',
              'next_step': '今天下午改喝水',
              'reason': '指南提到睡眠影响',
              'risk': '可能短时疲惫',
              'review_date': '2026-10-12',
              'citations': citation == null ? <String>[] : [citation],
              'unknown': '个体反应未知',
            })
          }
        }
      ]
    };

void main() {
  test('敏感信息本地识别，引用只能指向本次检索条目', () {
    expect(sensitiveInputReason('密码：abc123'), isNotNull);
    expect(sensitiveInputReason('验证码 123456'), isNotNull);
    expect(sensitiveInputReason('身份证号 11010519491231002X'), isNotNull);
    expect(sensitiveInputReason('银行卡 4111 1111 1111 1111'), isNotNull);
    expect(sensitiveInputReason('下午喝咖啡好吗'), isNull);
    final retrieved = retrieveGuideEntries(guide, '下午喝咖啡好吗');
    expect(retrieved.single.id, 'sleep-1');
    expect(DecisionAnswer.parse(modelAnswer(), retrieved).citations.single.id,
        'sleep-1');
    expect(() => DecisionAnswer.parse(modelAnswer(citation: 'fake'), retrieved),
        throwsFormatException);
    expect(() => DecisionAnswer.parse(modelAnswer(route: 'urgent'), retrieved),
        throwsFormatException);
    expect(() => DecisionAnswer.parse(modelAnswer(), []),
        throwsFormatException);
    final fenced = modelAnswer();
    fenced['choices'][0]['message']['content'] =
        '```json\n${fenced['choices'][0]['message']['content']}\n```';
    expect(DecisionAnswer.parse(fenced, retrieved).citations.single.id,
        'sleep-1');
  });

  test('今天该不该吃饭不会牵强匹配指南', () async {
    final bundled = GuidePackage.parse(
        await File('assets/guide.json').readAsString());
    expect(retrieveGuideEntries(bundled, '今天该不该吃饭'), isEmpty);
    expect(retrieveGuideEntries(bundled, '咖啡好吗'), isNotEmpty);
    expect(DecisionAnswer.parse(modelAnswer(citation: null), []).citations,
        isEmpty);
  });

  test('没有指南依据时仍调用模型，且空引用答复可通过校验', () async {
    final previousOverrides = HttpOverrides.current;
    HttpOverrides.global = null;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    Map<String, dynamic>? requestBody;
    server.listen((request) async {
      requestBody = jsonDecode(await utf8.decoder.bind(request).join());
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(modelAnswer(citation: null)));
      await request.response.close();
    });
    try {
      final bundled = GuidePackage.parse(
          await File('assets/guide.json').readAsString());
      final store = FakeModelStore('http://localhost:${server.port}/v1');
      final answer = await ConsultationService(ModelClient(store))
          .answer('今天该不该吃饭', bundled);
      expect(answer.citations, isEmpty);
      expect(store.calls, 1);
      final payload = jsonDecode((requestBody!['messages'] as List).last['content']);
      expect(payload['guide_entries'], isEmpty);
    } finally {
      await server.close(force: true);
      HttpOverrides.global = previousOverrides;
    }
  });

  test('调用只发送问题与候选指南，不发送个人资料', () async {
    final previousOverrides = HttpOverrides.current;
    HttpOverrides.global = null;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    Map<String, dynamic>? requestBody;
    server.listen((request) async {
      requestBody = jsonDecode(await utf8.decoder.bind(request).join());
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(modelAnswer()));
      await request.response.close();
    });
    try {
      final store = FakeModelStore('http://localhost:${server.port}/v1');
      final service = ConsultationService(ModelClient(store));
      final answer = await service.answer('下午喝咖啡好吗', guide);
      expect(answer.nextStep, '今天下午改喝水');
      final messages = requestBody!['messages'] as List;
      expect(messages.first['role'], 'system');
      expect(messages.last['content'], contains('sleep-1'));
      expect(messages.last['content'], isNot(contains('profile')));
      expect(store.calls, 1);
      await expectLater(
          service.answer('密码：abc123', guide), throwsFormatException);
      expect(store.calls, 1);
    } finally {
      await server.close(force: true);
      HttpOverrides.global = previousOverrides;
    }
  });

  testWidgets('失败保留加密草稿入口，重进咨询页仍可重试', (tester) async {
    final drafts = MemoryDrafts();
    final service = FailingService();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ConsultationScreen(
      guide: guide,
      service: service,
      draftStore: drafts,
      onBrowseGuide: () {},
      onOpenEntry: (_, __) {},
    ))));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '下午喝咖啡好吗');
    await tester.tap(find.text('提交问题'));
    await tester.pumpAndSettle();
    expect(drafts.value, '下午喝咖啡好吗');
    expect(find.text('浏览离线指南'), findsOneWidget);
    expect(find.text('结论'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ConsultationScreen(
      guide: guide,
      service: service,
      draftStore: drafts,
      onBrowseGuide: () {},
      onOpenEntry: (_, __) {},
    ))));
    await tester.pumpAndSettle();
    expect(find.text('下午喝咖啡好吗'), findsOneWidget);
  });

  testWidgets('答复默认只展开前两项，引用可展开查看', (tester) async {
    final drafts = MemoryDrafts()..value = '下午喝咖啡好吗';
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ConsultationScreen(
      guide: guide, service: SuccessfulService(), draftStore: drafts,
      onBrowseGuide: () {}, onOpenEntry: (_, __) {},
    ))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('提交问题'));
    await tester.pumpAndSettle();
    expect(find.text('下午少喝咖啡'), findsOneWidget);
    expect(find.text('今天下午改喝水'), findsOneWidget);
    expect(find.text('指南提到睡眠影响'), findsNothing);
    expect(drafts.value, isNull);
    await tester.tap(find.text('理由或证据'));
    await tester.pumpAndSettle();
    expect(find.text('指南提到睡眠影响'), findsOneWidget);
    await tester.ensureVisible(find.text('指南引用与未知信息'));
    await tester.tap(find.text('指南引用与未知信息'));
    await tester.pumpAndSettle();
    expect(find.text('下午不要喝咖啡'), findsOneWidget);
    expect(find.textContaining('版本 v1'), findsOneWidget);
  });

  testWidgets('无指南依据的答复直接标明模型推断', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ConsultationScreen(
      guide: guide, service: InferenceService(), draftStore: MemoryDrafts(),
      onBrowseGuide: () {}, onOpenEntry: (_, __) {},
    ))));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '今天该不该吃饭');
    await tester.tap(find.text('提交问题'));
    await tester.pumpAndSettle();
    expect(find.text('没有适用的指南依据'), findsOneWidget);
    expect(find.text('本次答复为模型推断，请自行核查。'), findsOneWidget);
    expect(find.text('先确认自己是否饥饿'), findsOneWidget);
  });
}
