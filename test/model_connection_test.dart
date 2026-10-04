import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_decision_assistant/model_connection.dart';

class MemorySecureStorage extends FlutterSecureStorage {
  final values = <String, String>{};

  @override
  Future<String?> read(
          {required String key,
          IOSOptions? iOptions,
          AndroidOptions? aOptions,
          LinuxOptions? lOptions,
          WebOptions? webOptions,
          MacOsOptions? mOptions,
          WindowsOptions? wOptions}) async =>
      values[key];

  @override
  Future<void> write(
      {required String key,
      required String? value,
      IOSOptions? iOptions,
      AndroidOptions? aOptions,
      LinuxOptions? lOptions,
      WebOptions? webOptions,
      MacOsOptions? mOptions,
      WindowsOptions? wOptions}) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<void> delete(
      {required String key,
      IOSOptions? iOptions,
      AndroidOptions? aOptions,
      LinuxOptions? lOptions,
      WebOptions? webOptions,
      MacOsOptions? mOptions,
      WindowsOptions? wOptions}) async {
    values.remove(key);
  }
}

void main() {
  test('密钥不进入设置快照，更新时可保留原密钥，删除后清空', () async {
    final storage = MemorySecureStorage();
    final store = SecureModelStore(storage: storage);
    await store.save('https://example.com/v1', 'model-a', 'secret', 3, 128);
    expect((await store.load()).hasApiKey, isTrue);
    expect((await store.load()).toString(), isNot(contains('secret')));
    await store.save('https://example.com/v1', 'model-b', null, 3, 128);
    expect(await store.readApiKey(), 'secret');
    await store.delete();
    expect(await store.readApiKey(), isNull);
    expect((await store.load()).baseUrl, isEmpty);
  });

  test('并发请求共享每日上限，次日自动重新计数', () async {
    final storage = MemorySecureStorage();
    var date = DateTime(2026, 10, 5);
    final store = SecureModelStore(storage: storage, now: () => date);
    await store.save('https://example.com/v1', 'model', 'secret', 2, 64);
    final results = await Future.wait([
      store.reserveRequest().then((_) => true).catchError((_) => false),
      store.reserveRequest().then((_) => true).catchError((_) => false),
      store.reserveRequest().then((_) => true).catchError((_) => false),
    ]);
    expect(results.where((allowed) => allowed).length, 2);
    expect((await store.load()).usedToday, 2);
    date = DateTime(2026, 10, 6);
    expect((await store.load()).usedToday, 0);
    expect(await store.reserveRequest(), 64);
  });

  test('连接测试只发送 ping，且受每日上限约束', () async {
    final previousOverrides = HttpOverrides.current;
    HttpOverrides.global = null;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final received = <String>[];
    server.listen((request) async {
      received.add('${request.headers.value(HttpHeaders.authorizationHeader)} '
          '${await utf8.decoder.bind(request).join()}');
      request.response.headers.contentType = ContentType.json;
      request.response.write('{"choices":[{"message":{"content":"ok"}}]}');
      await request.response.close();
    });
    try {
      final store = SecureModelStore(storage: MemorySecureStorage());
      await store.save(
          'http://localhost:${server.port}/v1', 'model', 'secret', 2, 64);
      await ModelClient(store).testConnection();
      expect(received.first, contains('Bearer secret'));
      expect(received.first, contains('"content":"ping"'));
      expect(
          jsonDecode(received.first.substring(received.first.indexOf('{')))[
              'max_tokens'],
          1);
      await ModelClient(store).complete(const [
        {'role': 'user', 'content': 'another request'}
      ], maxTokens: 100);
      expect(
          jsonDecode(received.last.substring(received.last.indexOf('{')))[
              'max_tokens'],
          64);
      await expectLater(ModelClient(store).testConnection(),
          throwsA(isA<ModelCallException>()));
      expect(received.length, 2);
    } finally {
      await server.close(force: true);
      HttpOverrides.global = previousOverrides;
    }
  });

  testWidgets('用户可保存和删除连接信息，密钥不回显', (tester) async {
    final store = SecureModelStore(storage: MemorySecureStorage());
    await tester
        .pumpWidget(MaterialApp(home: ModelConnectionScreen(store: store)));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Base URL'), 'https://example.com/v1');
    await tester.enterText(find.widgetWithText(TextField, '模型名'), 'model');
    await tester.enterText(find.widgetWithText(TextField, 'API Key'), 'secret');
    await tester.ensureVisible(find.text('保存'));
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('secret'), findsNothing);
    expect(find.text('连接信息已删除。'), findsNothing);
    await tester.scrollUntilVisible(find.text('删除连接信息'), 100,
        scrollable: find.byType(Scrollable).first);
    await tester.drag(find.byType(ListView), const Offset(0, -100));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除连接信息'));
    await tester.pumpAndSettle();
    expect(await store.readApiKey(), isNull);
    expect(find.text('连接信息已删除。'), findsOneWidget);
  });
}
