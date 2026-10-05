import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_decision_assistant/consultation.dart';
import 'package:personal_decision_assistant/guide.dart';
import 'package:personal_decision_assistant/model_connection.dart';
import 'package:personal_decision_assistant/profile.dart';

class MemoryProfiles implements ProfileStore {
  MemoryProfiles(this.categories);
  final Map<ProfileCategory, String> categories;
  var loads = 0;
  @override
  Future<ProfileSnapshot> load() async {
    loads++;
    return ProfileSnapshot(categories, null);
  }

  @override
  Future<void> saveCategory(ProfileCategory category, String value) async {}
  @override
  Future<void> deleteCategory(ProfileCategory category) async {}
  @override
  Future<void> savePreferences(AnswerPreferences preferences) async {}
  @override
  Future<void> deletePreferences() async {}
}

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
  Future<List<ProfileClarification>> clarify(
          String question, GuidePackage guide) async =>
      [];
  @override
  Future<DecisionAnswer> answer(String question, GuidePackage guide,
          {Map<ProfileCategory, String> selectedProfile = const {},
          RiskRoute? route}) async =>
      throw const ModelCallException('服务暂时不可用');
}

class SuccessfulService extends ConsultationService {
  SuccessfulService()
      : super(ModelClient(FakeModelStore('https://example.com/v1')));
  @override
  Future<List<ProfileClarification>> clarify(
          String question, GuidePackage guide) async =>
      [];
  @override
  Future<DecisionAnswer> answer(String question, GuidePackage guide,
          {Map<ProfileCategory, String> selectedProfile = const {},
          RiskRoute? route}) async =>
      DecisionAnswer.parse(modelAnswer(), guide.entries);
}

class PendingClarificationService extends SuccessfulService {
  final result = Completer<List<ProfileClarification>>();

  @override
  Future<List<ProfileClarification>> clarify(
          String question, GuidePackage guide) =>
      result.future;
}

class InferenceService extends ConsultationService {
  InferenceService()
      : super(ModelClient(FakeModelStore('https://example.com/v1')));
  @override
  Future<List<ProfileClarification>> clarify(
          String question, GuidePackage guide) async =>
      [];
  @override
  Future<DecisionAnswer> answer(String question, GuidePackage guide,
          {Map<ProfileCategory, String> selectedProfile = const {},
          RiskRoute? route}) async =>
      const DecisionAnswer(
        conclusion: '先确认自己是否饥饿',
        nextStep: '按平时习惯安排一餐',
        reason: '没有适用指南，仅为一般建议',
        risk: '特殊情况需咨询专业人士',
        reviewDate: '2026-10-06',
        citations: [],
        unknown: '没有指南依据',
      );
}

class PersonalizedService extends ConsultationService {
  PersonalizedService()
      : super(ModelClient(FakeModelStore('https://example.com/v1')));
  Map<ProfileCategory, String>? received;
  @override
  Future<List<ProfileClarification>> clarify(
          String question, GuidePackage guide) async =>
      [const ProfileClarification(ProfileCategory.health, '是否有健康限制？')];
  @override
  Future<DecisionAnswer> answer(String question, GuidePackage guide,
      {Map<ProfileCategory, String> selectedProfile = const {},
      RiskRoute? route}) async {
    received = selectedProfile;
    return DecisionAnswer(
      conclusion: '先尝试轻量活动',
      nextStep: '今天散步',
      reason: '符合当前限制',
      risk: '注意不适',
      reviewDate: '2026-10-12',
      citations: const [],
      unknown: '指南未覆盖个人情况，仅为模型推断',
      usedProfileFields: selectedProfile.keys.toList(),
    );
  }
}

class MultipleClarificationsService extends PersonalizedService {
  @override
  Future<List<ProfileClarification>> clarify(
          String question, GuidePackage guide) async =>
      [
        const ProfileClarification(ProfileCategory.health, '是否有健康限制？'),
        const ProfileClarification(ProfileCategory.workAndFinance, '预算是多少？'),
        const ProfileClarification(ProfileCategory.goals, '当前目标是什么？'),
      ];
}

class InvalidClarificationService extends PersonalizedService {
  @override
  Future<List<ProfileClarification>> clarify(
          String question, GuidePackage guide) async =>
      throw const FormatException('澄清问题无法核查，请重试。');

  @override
  Future<DecisionAnswer> answer(String question, GuidePackage guide,
      {Map<ProfileCategory, String> selectedProfile = const {},
      RiskRoute? route}) async {
    received = selectedProfile;
    return const DecisionAnswer(
      conclusion: '先确认是否需要休息',
      nextStep: '今天按作息安排睡眠',
      reason: '当前信息不足',
      risk: '若持续失眠应寻求帮助',
      reviewDate: '2026-10-06',
      citations: [],
      unknown: '睡眠需求未知',
    );
  }
}

class HighRiskService extends ConsultationService {
  HighRiskService()
      : super(ModelClient(FakeModelStore('https://example.com/v1')));
  var clarifications = 0;
  RiskRoute? receivedRoute;

  @override
  Future<List<ProfileClarification>> clarify(
      String question, GuidePackage guide) async {
    clarifications++;
    return [];
  }

  @override
  Future<DecisionAnswer> answer(String question, GuidePackage guide,
      {Map<ProfileCategory, String> selectedProfile = const {},
      RiskRoute? route}) async {
    receivedRoute = route;
    return DecisionAnswer(
      conclusion: '此问题需要专业人员结合具体情况判断。',
      nextStep: route!.professionalStep,
      reason: '目前没有适用指南依据，仅能列出一般注意事项。',
      risk: '个体差异和治疗风险未知。',
      reviewDate: '2026-10-06',
      citations: const [],
      unknown: '具体病情未知，仅为模型推断。',
      route: route,
    );
  }
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
  test('紧急风险优先于其他类别，普通问题仍为普通分流', () {
    expect(classifyRisk('胸痛还要不要买股票'), RiskRoute.urgent);
    expect(classifyRisk('我想自杀怎么办'), RiskRoute.urgent);
    expect(classifyRisk('旁边起大火了怎么办'), RiskRoute.urgent);
    expect(classifyRisk('隔壁有浓烟怎么办'), RiskRoute.urgent);
    expect(classifyRisk('这份合同可以签吗'), RiskRoute.legal);
    expect(classifyRisk('我的症状需要用药吗'), RiskRoute.medical);
    expect(classifyRisk('该买哪只基金'), RiskRoute.investment);
    expect(classifyRisk('下午喝咖啡好吗'), RiskRoute.ordinary);
    expect(classifyRisk('今晚吃火锅好吗'), RiskRoute.ordinary);
  });

  testWidgets('紧急问题立即显示行动和求助号码，不加载指南或调用模型', (tester) async {
    final store = FakeModelStore('https://example.com/v1');
    final profiles = MemoryProfiles({});
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ConsultationScreen(
      guide: guide,
      service: ConsultationService(ModelClient(store)),
      profileStore: profiles,
      draftStore: MemoryDrafts(),
      onBrowseGuide: () {},
      onOpenEntry: (_, __) {},
    ))));
    await tester.enterText(find.byType(TextField), '我胸痛、呼吸困难，现在怎么办');
    await tester.tap(find.text('开始分析'));
    await tester.pump();
    expect(find.text('分流结果：紧急风险'), findsOneWidget);
    expect(find.text('拨打 120 急救'), findsOneWidget);
    expect(find.text('拨打 110 报警'), findsOneWidget);
    expect(find.text('拨打 119 消防'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.bySemanticsLabel('欢迎小章鱼'), findsNothing);
    expect(find.bySemanticsLabel('思考中的小章鱼'), findsNothing);
    expect(find.bySemanticsLabel('完成的小章鱼'), findsNothing);
    expect(tester.getTopLeft(find.text('分流结果：紧急风险')).dy,
        lessThan(tester.getTopLeft(find.text('修改问题')).dy));
    expect(
        tester
            .getSize(find.ancestor(
              of: find.text('拨打 120 急救'),
              matching:
                  find.byWidgetPredicate((widget) => widget is FilledButton),
            ))
            .height,
        greaterThanOrEqualTo(48));
    expect(store.calls, 0);
    expect(profiles.loads, 0);

    await tester.tap(find.text('修改问题'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '旁边起大火了怎么办');
    await tester.tap(find.text('开始分析'));
    await tester.pump();
    expect(find.text('分流结果：紧急风险'), findsOneWidget);
    expect(find.textContaining('不要乘坐电梯'), findsOneWidget);
    expect(
        find.ancestor(
            of: find.text('拨打 119 消防'),
            matching:
                find.byWidgetPredicate((widget) => widget is FilledButton)),
        findsOneWidget);
    expect(store.calls, 0);
    expect(profiles.loads, 0);
  });

  testWidgets('减少动效时等待状态有文字且不推动页面内容', (tester) async {
    final service = PendingClarificationService();
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: Scaffold(
        body: ConsultationScreen(
          guide: guide,
          service: service,
          draftStore: MemoryDrafts(),
          onBrowseGuide: () {},
          onOpenEntry: (_, __) {},
        ),
      ),
    ));
    final examplesPosition = tester.getTopLeft(find.text('试试这样提问')).dy;
    await tester.enterText(find.byType(TextField), '下午喝咖啡好吗');
    await tester.tap(find.text('开始分析'));
    await tester.pump();
    expect(find.text('正在分析'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.getTopLeft(find.text('试试这样提问')).dy, examplesPosition);
    service.result.complete([]);
    await tester.pumpAndSettle();
    expect(find.text('给你的建议'), findsOneWidget);
  });

  testWidgets('小屏大字时紧急行动避开安全区并可滚动到求助按钮', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          padding: const EdgeInsets.only(top: 24, bottom: 24),
          textScaler: const TextScaler.linear(1.8),
        ),
        child: child!,
      ),
      home: Scaffold(
        body: ConsultationScreen(
          guide: guide,
          service: SuccessfulService(),
          draftStore: MemoryDrafts(),
          onBrowseGuide: () {},
          onOpenEntry: (_, __) {},
        ),
      ),
    ));
    await tester.enterText(find.byType(TextField), '我胸痛、呼吸困难，现在怎么办');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.scrollUntilVisible(find.text('开始分析'), 100,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始分析'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.getTopLeft(find.text('分流结果：紧急风险')).dy,
        greaterThanOrEqualTo(24));
    await tester.scrollUntilVisible(find.text('拨打 119 消防'), 100,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.getBottomLeft(find.text('拨打 119 消防')).dy,
        lessThanOrEqualTo(616));
  });

  testWidgets('医疗问题显示专业求助方向并跳过普通澄清', (tester) async {
    final service = HighRiskService();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ConsultationScreen(
      guide: guide,
      service: service,
      draftStore: MemoryDrafts(),
      onBrowseGuide: () {},
      onOpenEntry: (_, __) {},
    ))));
    await tester.enterText(find.byType(TextField), '我的症状需要用药吗');
    await tester.tap(find.text('开始分析'));
    await tester.pumpAndSettle();
    expect(service.receivedRoute, RiskRoute.medical);
    expect(service.clarifications, 0);
    expect(find.text('分流结果：医疗问题'), findsOneWidget);
    expect(find.textContaining('正规医疗机构评估'), findsOneWidget);
    expect(find.textContaining('不代替专业人员'), findsOneWidget);
    expect(find.text('补充信息'), findsNothing);
  });

  test('高风险答复校验分流，固定专业求助方向和引用边界', () async {
    final previousOverrides = HttpOverrides.current;
    HttpOverrides.global = null;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    Map<String, dynamic>? requestBody;
    var responseRoute = 'medical';
    server.listen((request) async {
      requestBody = jsonDecode(await utf8.decoder.bind(request).join());
      request.response.headers.contentType = ContentType.json;
      request.response
          .write(jsonEncode(modelAnswer(citation: null, route: responseRoute)));
      await request.response.close();
    });
    try {
      final store = FakeModelStore('http://localhost:${server.port}/v1');
      final service = ConsultationService(ModelClient(store));
      final answer = await service.answer('我的症状需要用药吗', guide);
      expect(answer.route, RiskRoute.medical);
      expect(answer.conclusion, '此问题需要专业人员结合具体情况判断。');
      expect(answer.nextStep, contains('医生'));
      expect(answer.citations, isEmpty);
      final payload =
          jsonDecode((requestBody!['messages'] as List).last['content']);
      expect(payload['expected_risk_route'], 'medical');
      expect((requestBody!['messages'] as List).first['content'],
          contains('risk_route 的值固定为 "medical"'));
      responseRoute = 'ordinary';
      await expectLater(
          service.answer('我的症状需要用药吗', guide), throwsFormatException);
      expect(store.calls, 2);
    } finally {
      await server.close(force: true);
      HttpOverrides.global = previousOverrides;
    }
  });

  testWidgets('澄清格式错误时仍答复且标注未确认的个人情况', (tester) async {
    final profiles = MemoryProfiles({});
    final service = InvalidClarificationService();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ConsultationScreen(
      guide: guide,
      service: service,
      profileStore: profiles,
      draftStore: MemoryDrafts(),
      onBrowseGuide: () {},
      onOpenEntry: (_, __) {},
    ))));
    await tester.enterText(find.byType(TextField), '我现在该不该睡觉');
    await tester.tap(find.text('开始分析'));
    await tester.pumpAndSettle();
    expect(find.text('先确认是否需要休息'), findsOneWidget);
    expect(find.text('澄清问题无法核查，请重试。'), findsNothing);
    expect(service.received, isEmpty);
    expect(profiles.loads, 0);
    await tester.drag(find.byType(ListView).first, const Offset(0, -400));
    await tester.pumpAndSettle();
    await tester.tap(find.text('指南引用与未知信息'));
    await tester.pumpAndSettle();
    expect(find.textContaining('个人情况是否改变结论尚不确定'), findsOneWidget);
  });

  test('澄清输出最多三个且类别和影响理由必须有效', () {
    Map<String, dynamic> response(List items) => {
          'choices': [
            {
              'message': {
                'content': jsonEncode({'clarifications': items})
              }
            }
          ]
        };
    final valid = {
      'category': 'health',
      'question': '有健康限制吗？',
      'impact': '会影响活动强度'
    };
    expect(parseClarifications(response([valid])).single.category,
        ProfileCategory.health);
    final fenced = response([valid]);
    fenced['choices'][0]['message']['content'] =
        '```json\n${fenced['choices'][0]['message']['content']}\n```';
    expect(parseClarifications(fenced).single.category, ProfileCategory.health);
    expect(() => parseClarifications(response([valid, valid])),
        throwsFormatException);
    expect(() => parseClarifications(response(List.filled(4, valid))),
        throwsFormatException);
    expect(
        () => parseClarifications(response([
              {'category': 'health', 'question': '问题', 'impact': ''}
            ])),
        throwsFormatException);
  });

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
    expect(
        () => DecisionAnswer.parse(modelAnswer(), []), throwsFormatException);
    final fenced = modelAnswer();
    fenced['choices'][0]['message']['content'] =
        '```json\n${fenced['choices'][0]['message']['content']}\n```';
    expect(
        DecisionAnswer.parse(fenced, retrieved).citations.single.id, 'sleep-1');
  });

  test('缺失模型分流字段时使用本地分流，冲突和截断仍拒绝', () {
    final noRoute = modelAnswer();
    final content = jsonDecode(noRoute['choices'][0]['message']['content']);
    content.remove('risk_route');
    noRoute['choices'][0]['message']['content'] = jsonEncode(content);
    expect(
        DecisionAnswer.parse(noRoute, guide.entries).route, RiskRoute.ordinary);
    expect(
        () =>
            DecisionAnswer.parse(modelAnswer(route: 'medical'), guide.entries),
        throwsA(isA<FormatException>()
            .having((error) => error.message, 'message', contains('分流'))));

    final truncated = <String, dynamic>{
      'choices': [
        {
          'finish_reason': 'length',
          'message': {'content': '{"risk_route":'}
        }
      ]
    };
    expect(
        () => DecisionAnswer.parse(truncated, guide.entries),
        throwsA(isA<FormatException>().having(
            (error) => error.message, 'message', contains('Token 上限'))));
  });

  test('今天该不该吃饭不会牵强匹配指南', () async {
    final bundled =
        GuidePackage.parse(await File('assets/guide.json').readAsString());
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
      final response = modelAnswer(citation: null);
      final content = jsonDecode(response['choices'][0]['message']['content']);
      content.remove('risk_route');
      response['choices'][0]['message']['content'] = jsonEncode(content);
      request.response.write(jsonEncode(response));
      await request.response.close();
    });
    try {
      final bundled =
          GuidePackage.parse(await File('assets/guide.json').readAsString());
      final store = FakeModelStore('http://localhost:${server.port}/v1');
      final answer = await ConsultationService(ModelClient(store))
          .answer('今天该不该吃饭', bundled);
      expect(answer.citations, isEmpty);
      expect(store.calls, 1);
      final payload =
          jsonDecode((requestBody!['messages'] as List).last['content']);
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
      expect(
          messages.first['content'], contains('risk_route 的值固定为 "ordinary"'));
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

  test('澄清阶段不发送资料，答复阶段只发送用户选中的字段', () async {
    final previousOverrides = HttpOverrides.current;
    HttpOverrides.global = null;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requests = <Map<String, dynamic>>[];
    server.listen((request) async {
      requests.add(jsonDecode(await utf8.decoder.bind(request).join()));
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(requests.length == 1
          ? {
              'choices': [
                {
                  'message': {
                    'content': jsonEncode({
                      'clarifications': [
                        {
                          'category': 'health',
                          'question': '是否有限制？',
                          'impact': '影响建议强度'
                        }
                      ]
                    })
                  }
                }
              ]
            }
          : modelAnswer()));
      await request.response.close();
    });
    try {
      final service = ConsultationService(
          ModelClient(FakeModelStore('http://localhost:${server.port}/v1')));
      final clarification = await service.clarify('下午喝咖啡好吗', guide);
      expect(clarification.single.category, ProfileCategory.health);
      final first =
          jsonDecode((requests.first['messages'] as List).last['content']);
      expect(first.containsKey('selected_profile'), isFalse);
      expect(jsonEncode(requests.first), isNot(contains('私人健康内容')));
      final answer = await service.answer('下午喝咖啡好吗', guide,
          selectedProfile: {ProfileCategory.health: '私人健康内容'});
      final second =
          jsonDecode((requests.last['messages'] as List).last['content']);
      expect(second['selected_profile'], {'health': '私人健康内容'});
      expect(jsonEncode(requests.last), isNot(contains('职业与财务')));
      expect(answer.usedProfileFields, [ProfileCategory.health]);
    } finally {
      await server.close(force: true);
      HttpOverrides.global = previousOverrides;
    }
  });

  testWidgets('澄清可跳过，勾选后仅已用字段进入依据轨迹', (tester) async {
    final profiles = MemoryProfiles({
      ProfileCategory.health: '避免剧烈运动',
      ProfileCategory.workAndFinance: '私人财务内容',
    });
    final service = PersonalizedService();
    Future<void> mount() => tester.pumpWidget(MaterialApp(
            home: Scaffold(
                body: ConsultationScreen(
          key: UniqueKey(),
          guide: guide,
          service: service,
          profileStore: profiles,
          draftStore: MemoryDrafts(),
          onBrowseGuide: () {},
          onOpenEntry: (_, __) {},
        ))));
    await mount();
    await tester.enterText(find.byType(TextField).first, '我该如何运动？');
    await tester.tap(find.text('开始分析'));
    await tester.pumpAndSettle();
    expect(find.text('是否有健康限制？'), findsOneWidget);
    expect(find.bySemanticsLabel('思考中的小章鱼'), findsOneWidget);
    expect(find.text('原问题'), findsOneWidget);
    expect(find.text('我该如何运动？'), findsOneWidget);
    expect(find.text('第 1 题，共 1 题'), findsOneWidget);
    expect(find.text('避免剧烈运动'), findsNothing);
    await tester.tap(find.text('暂不提供'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('继续获得答复'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('继续获得答复'));
    await tester.pumpAndSettle();
    expect(service.received, isEmpty);
    await tester.drag(find.byType(ListView).first, const Offset(0, -400));
    await tester.pumpAndSettle();
    await tester.tap(find.text('指南引用与未知信息'));
    await tester.pumpAndSettle();
    expect(find.textContaining('未提供健康限制'), findsOneWidget);

    await mount();
    await tester.enterText(find.byType(TextField).first, '我该如何运动？');
    await tester.tap(find.text('开始分析'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('提供资料'));
    await tester.pumpAndSettle();
    expect(find.text('避免剧烈运动'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('继续获得答复'), 100,
        scrollable: find.byType(Scrollable).first);
    await tester.drag(find.byType(ListView).first, const Offset(0, -120));
    await tester.pumpAndSettle();
    await tester.tap(find.text('继续获得答复'));
    await tester.pumpAndSettle();
    expect(service.received, {ProfileCategory.health: '避免剧烈运动'});
    await tester.drag(find.byType(ListView).first, const Offset(0, -400));
    await tester.pumpAndSettle();
    await tester.tap(find.text('指南引用与未知信息'));
    await tester.pumpAndSettle();
    expect(find.textContaining('指南未覆盖个人情况'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('本次使用的资料'), 100,
        scrollable: find.byType(Scrollable).first);
    await tester.drag(find.byType(ListView).first, const Offset(0, -200));
    await tester.pumpAndSettle();
    await tester.tap(find.text('本次使用的资料'));
    await tester.pumpAndSettle();
    expect(find.text('健康限制'), findsOneWidget);
  });

  testWidgets('澄清逐题显示进度，未选资料不会发送', (tester) async {
    final service = MultipleClarificationsService();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ConsultationScreen(
      guide: guide,
      service: service,
      profileStore: MemoryProfiles({ProfileCategory.health: '避免剧烈运动'}),
      draftStore: MemoryDrafts(),
      onBrowseGuide: () {},
      onOpenEntry: (_, __) {},
    ))));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '我该如何运动？');
    await tester.tap(find.text('开始分析'));
    await tester.pumpAndSettle();
    expect(find.text('第 1 题，共 3 题'), findsOneWidget);
    expect(find.text('预算是多少？'), findsNothing);
    await tester.scrollUntilVisible(find.text('下一题'), 100,
        scrollable: find.byType(Scrollable).first);
    await tester.drag(find.byType(ListView).first, const Offset(0, -120));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下一题'));
    await tester.pumpAndSettle();
    expect(find.text('请选择是否提供这项资料。'), findsOneWidget);
    await tester.tap(find.text('提供资料'));
    await tester.pumpAndSettle();
    expect(find.text('避免剧烈运动'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('下一题'), 100,
        scrollable: find.byType(Scrollable).first);
    await tester.drag(find.byType(ListView).first, const Offset(0, -120));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下一题'));
    await tester.pumpAndSettle();
    expect(find.text('第 2 题，共 3 题'), findsOneWidget);
    expect(find.text('预算是多少？'), findsOneWidget);
    await tester.ensureVisible(find.text('上一题'));
    await tester.drag(find.byType(ListView).first, const Offset(0, -120));
    await tester.pumpAndSettle();
    await tester.tap(find.text('上一题'));
    await tester.pumpAndSettle();
    expect(find.text('第 1 题，共 3 题'), findsOneWidget);
    expect(find.text('避免剧烈运动'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('下一题'), 100,
        scrollable: find.byType(Scrollable).first);
    await tester.drag(find.byType(ListView).first, const Offset(0, -120));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下一题'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('暂不提供'));
    await tester.scrollUntilVisible(find.text('下一题'), 100,
        scrollable: find.byType(Scrollable).first);
    await tester.drag(find.byType(ListView).first, const Offset(0, -120));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下一题'));
    await tester.pumpAndSettle();
    expect(find.text('第 3 题，共 3 题'), findsOneWidget);
    await tester.tap(find.text('暂不提供'));
    await tester.scrollUntilVisible(find.text('继续获得答复'), 100,
        scrollable: find.byType(Scrollable).first);
    await tester.drag(find.byType(ListView).first, const Offset(0, -120));
    await tester.pumpAndSettle();
    await tester.tap(find.text('继续获得答复'));
    await tester.pumpAndSettle();
    expect(service.received, {ProfileCategory.health: '避免剧烈运动'});
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
    await tester.tap(find.text('开始分析'));
    await tester.pumpAndSettle();
    expect(drafts.value, '下午喝咖啡好吗');
    expect(find.textContaining('问题已保存在本机，可直接重试'), findsOneWidget);
    expect(find.text('下午喝咖啡好吗'), findsOneWidget);
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
    expect(find.text('已恢复上次未完成的问题，可继续编辑。'), findsOneWidget);
  });

  testWidgets('欢迎页示例可填写、编辑并提交', (tester) async {
    final drafts = MemoryDrafts();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ConsultationScreen(
      guide: guide,
      service: FailingService(),
      draftStore: drafts,
      onBrowseGuide: () {},
      onOpenEntry: (_, __) {},
    ))));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('欢迎小章鱼'), findsOneWidget);
    expect(find.text('今天，想清楚什么？'), findsOneWidget);
    expect(find.text('问题会发送给你设置的模型；仅发送本次选择的个人资料。'), findsOneWidget);
    for (final example in const [
      '要不要换一份工作？',
      '这笔钱该不该花？',
      '接下来三个月怎么安排？',
    ]) {
      await tester.scrollUntilVisible(find.text(example), 80,
          scrollable: find.byType(Scrollable).first);
      expect(find.text(example), findsOneWidget);
    }
    await tester.scrollUntilVisible(find.text('要不要换一份工作？'), -80,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('要不要换一份工作？'));
    await tester.pumpAndSettle();
    expect(find.text('要不要换一份工作？'), findsNWidgets(2));
    await tester.enterText(find.byType(TextField), '要不要换一份远程工作？');
    await tester.ensureVisible(find.text('开始分析'));
    await tester.tap(find.text('开始分析'));
    await tester.pumpAndSettle();
    expect(drafts.value, '要不要换一份远程工作？');
  });

  testWidgets('答复优先展示结论与行动，详情默认折叠并可查看', (tester) async {
    final drafts = MemoryDrafts()..value = '下午喝咖啡好吗';
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ConsultationScreen(
      guide: guide,
      service: SuccessfulService(),
      draftStore: drafts,
      onBrowseGuide: () {},
      onOpenEntry: (_, __) {},
    ))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始分析'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('完成的小章鱼'), findsOneWidget);
    expect(find.text('给你的建议'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('下午少喝咖啡'), findsOneWidget);
    expect(find.text('今天下午改喝水'), findsOneWidget);
    expect(find.text('保存这个决定'), findsOneWidget);
    expect(find.text('修改问题'), findsOneWidget);
    expect(tester.getTopLeft(find.text('结论')).dy,
        lessThan(tester.getTopLeft(find.text('保存这个决定')).dy));
    expect(find.text('指南提到睡眠影响'), findsNothing);
    expect(find.text('未知信息'), findsNothing);
    expect(drafts.value, isNull);
    await tester.tap(find.text('理由或证据'));
    await tester.pumpAndSettle();
    expect(find.text('指南提到睡眠影响'), findsOneWidget);
    await tester.ensureVisible(find.text('指南引用与未知信息'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).first, const Offset(0, -120));
    await tester.pumpAndSettle();
    await tester.tap(find.text('指南引用与未知信息'));
    await tester.pumpAndSettle();
    expect(find.text('下午不要喝咖啡'), findsOneWidget);
    expect(find.textContaining('版本 v1'), findsOneWidget);
    expect(find.text('未知信息'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('本次使用的资料'), 100,
        scrollable: find.byType(Scrollable).first);
    await tester.drag(find.byType(ListView).first, const Offset(0, -200));
    await tester.pumpAndSettle();
    await tester.tap(find.text('本次使用的资料'));
    await tester.pumpAndSettle();
    expect(find.text('无'), findsOneWidget);
  });

  testWidgets('答复页可返回修改原问题', (tester) async {
    final drafts = MemoryDrafts()..value = '下午喝咖啡好吗';
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ConsultationScreen(
      guide: guide,
      service: SuccessfulService(),
      draftStore: drafts,
      onBrowseGuide: () {},
      onOpenEntry: (_, __) {},
    ))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始分析'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('修改问题'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, '你的问题'), findsOneWidget);
    expect(find.text('下午喝咖啡好吗'), findsOneWidget);
    expect(find.text('给你的建议'), findsNothing);
  });

  testWidgets('无指南依据的答复直接标明模型推断', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ConsultationScreen(
      guide: guide,
      service: InferenceService(),
      draftStore: MemoryDrafts(),
      onBrowseGuide: () {},
      onOpenEntry: (_, __) {},
    ))));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '今天该不该吃饭');
    await tester.tap(find.text('开始分析'));
    await tester.pumpAndSettle();
    expect(find.text('没有适用的指南依据'), findsOneWidget);
    expect(find.text('本次答复为模型推断，请自行核查。'), findsOneWidget);
    expect(find.text('先确认自己是否饥饿'), findsOneWidget);
  });
}
