import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ModelSettings {
  const ModelSettings({
    required this.baseUrl,
    required this.model,
    required this.hasApiKey,
    required this.dailyLimit,
    required this.answerTokenLimit,
    required this.usedToday,
  });

  final String baseUrl;
  final String model;
  final bool hasApiKey;
  final int dailyLimit;
  final int answerTokenLimit;
  final int usedToday;
}

abstract class ModelStore {
  Future<ModelSettings> load();
  Future<void> save(String baseUrl, String model, String? newApiKey,
      int dailyLimit, int answerTokenLimit);
  Future<void> delete();
  Future<String?> readApiKey();
  Future<int> reserveRequest();
}

class SecureModelStore implements ModelStore {
  SecureModelStore({FlutterSecureStorage? storage, DateTime Function()? now})
      : storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            ),
        now = now ?? DateTime.now;

  final FlutterSecureStorage storage;
  final DateTime Function() now;
  static Future<void> _reservationQueue = Future.value();

  String get _today {
    final date = now();
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  @override
  Future<ModelSettings> load() async {
    final values = await Future.wait([
      storage.read(key: 'model.baseUrl'),
      storage.read(key: 'model.name'),
      storage.read(key: 'model.apiKey'),
      storage.read(key: 'model.dailyLimit'),
      storage.read(key: 'model.answerTokenLimit'),
      storage.read(key: 'model.usageDate'),
      storage.read(key: 'model.usageCount'),
    ]);
    return ModelSettings(
      baseUrl: values[0] ?? '',
      model: values[1] ?? '',
      hasApiKey: values[2]?.isNotEmpty ?? false,
      dailyLimit: int.tryParse(values[3] ?? '') ?? 20,
      answerTokenLimit: int.tryParse(values[4] ?? '') ?? 1024,
      usedToday: values[5] == _today ? int.tryParse(values[6] ?? '') ?? 0 : 0,
    );
  }

  @override
  Future<void> save(String baseUrl, String model, String? newApiKey,
      int dailyLimit, int answerTokenLimit) async {
    await storage.write(key: 'model.baseUrl', value: baseUrl);
    await storage.write(key: 'model.name', value: model);
    if (newApiKey != null) {
      await storage.write(key: 'model.apiKey', value: newApiKey);
    }
    await storage.write(key: 'model.dailyLimit', value: '$dailyLimit');
    await storage.write(
        key: 'model.answerTokenLimit', value: '$answerTokenLimit');
  }

  @override
  Future<void> delete() async {
    for (final key in [
      'model.baseUrl',
      'model.name',
      'model.apiKey',
      'model.dailyLimit',
      'model.answerTokenLimit',
      'model.usageDate',
      'model.usageCount',
    ]) {
      await storage.delete(key: key);
    }
  }

  @override
  Future<String?> readApiKey() => storage.read(key: 'model.apiKey');

  @override
  Future<int> reserveRequest() async {
    final previous = _reservationQueue;
    final done = Completer<void>();
    _reservationQueue = done.future;
    await previous;
    try {
      final settings = await load();
      if (settings.usedToday >= settings.dailyLimit) {
        throw const ModelCallException('已达到今日请求上限，请明天再试或调整上限。');
      }
      await storage.write(key: 'model.usageDate', value: _today);
      await storage.write(
          key: 'model.usageCount', value: '${settings.usedToday + 1}');
      return settings.answerTokenLimit;
    } finally {
      done.complete();
    }
  }
}

class ModelCallException implements Exception {
  const ModelCallException(this.message);
  final String message;
}

class ModelClient {
  const ModelClient(this.store);
  final ModelStore store;

  Future<Map<String, dynamic>> complete(List<Map<String, String>> messages,
      {int? maxTokens}) async {
    final settings = await store.load();
    final key = await store.readApiKey();
    if (validateModelUrl(settings.baseUrl) != null ||
        settings.model.isEmpty ||
        key == null ||
        key.isEmpty) {
      throw const ModelCallException('请先保存完整的连接信息。');
    }
    final limit = await store.reserveRequest();
    final uri = Uri.parse(
        '${settings.baseUrl.replaceFirst(RegExp(r'/$'), '')}/chat/completions');
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final request =
          await client.postUrl(uri).timeout(const Duration(seconds: 15));
      request.followRedirects = false;
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $key');
      request.write(jsonEncode({
        'model': settings.model,
        'messages': messages,
        'max_tokens': maxTokens == null ? limit : maxTokens.clamp(1, limit),
      }));
      final response =
          await request.close().timeout(const Duration(seconds: 30));
      final body = await utf8.decoder.bind(response).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ModelCallException(
            '连接失败（HTTP ${response.statusCode}），请检查地址、密钥和模型名。');
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic> ||
          decoded['choices'] is! List ||
          (decoded['choices'] as List).isEmpty) {
        throw const ModelCallException('服务响应不符合 OpenAI 聊天接口格式。');
      }
      return decoded;
    } on ModelCallException {
      rethrow;
    } on FormatException {
      throw const ModelCallException('服务响应不符合 OpenAI 聊天接口格式。');
    } catch (_) {
      throw const ModelCallException('连接失败，请检查网络和服务地址。');
    } finally {
      client.close(force: true);
    }
  }

  Future<void> testConnection() async {
    await complete(const [
      {'role': 'user', 'content': 'ping'}
    ], maxTokens: 1);
  }
}

String? validateModelUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      (uri.scheme != 'https' &&
          !(uri.scheme == 'http' && uri.host == 'localhost'))) {
    return '请输入 HTTPS 地址；本机 localhost 可使用 HTTP。';
  }
  return null;
}

class ModelConnectionScreen extends StatefulWidget {
  const ModelConnectionScreen({super.key, this.store});
  final ModelStore? store;

  @override
  State<ModelConnectionScreen> createState() => _ModelConnectionScreenState();
}

class _ModelConnectionScreenState extends State<ModelConnectionScreen> {
  late final ModelStore store = widget.store ?? SecureModelStore();
  late Future<ModelSettings> settings = store.load();
  final url = TextEditingController();
  final model = TextEditingController();
  final key = TextEditingController();
  final daily = TextEditingController();
  final answer = TextEditingController();
  bool initialized = false;
  bool hasKey = false;
  bool busy = false;
  String? message;

  @override
  void dispose() {
    for (final controller in [url, model, key, daily, answer]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    final urlValue = url.text.trim();
    final modelValue = model.text.trim();
    final keyValue = key.text.trim();
    final dailyValue = int.tryParse(daily.text.trim());
    final answerValue = int.tryParse(answer.text.trim());
    final urlError = validateModelUrl(urlValue);
    if (urlError != null ||
        modelValue.isEmpty ||
        (keyValue.isEmpty && !hasKey) ||
        dailyValue == null ||
        dailyValue < 1 ||
        answerValue == null ||
        answerValue < 1) {
      setState(() => message = urlError ?? '请填写模型名、密钥和大于 0 的整数上限。');
      return;
    }
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await store.save(urlValue, modelValue, keyValue.isEmpty ? null : keyValue,
          dailyValue, answerValue);
      key.clear();
      hasKey = true;
      if (mounted) {
        setState(() {
          message = '已保存。';
          settings = store.load();
        });
      }
    } catch (_) {
      if (mounted) setState(() => message = '保存失败，请重试。');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> test() async {
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await ModelClient(store).testConnection();
      if (mounted) setState(() => message = '连接成功。');
    } on ModelCallException catch (error) {
      if (mounted) setState(() => message = error.message);
    } catch (_) {
      if (mounted) setState(() => message = '连接失败，请重试。');
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          settings = store.load();
        });
      }
    }
  }

  Future<void> delete() async {
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await store.delete();
      url.clear();
      model.clear();
      key.clear();
      daily.text = '20';
      answer.text = '1024';
      hasKey = false;
      if (mounted) {
        setState(() {
          message = '连接信息已删除。';
          settings = store.load();
        });
      }
    } catch (_) {
      if (mounted) setState(() => message = '删除失败，请重试。');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('模型连接')),
        body: FutureBuilder<ModelSettings>(
          future: settings,
          builder: (context, result) {
            if (result.hasError) {
              return Center(
                  child: TextButton.icon(
                      onPressed: () => setState(() => settings = store.load()),
                      icon: const Icon(Icons.refresh),
                      label: const Text('读取失败，重试')));
            }
            if (!result.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final current = result.data!;
            if (!initialized) {
              url.text = current.baseUrl;
              model.text = current.model;
              daily.text = '${current.dailyLimit}';
              answer.text = '${current.answerTokenLimit}';
              hasKey = current.hasApiKey;
              initialized = true;
            }
            return ListView(padding: const EdgeInsets.all(16), children: [
              TextField(
                  controller: url,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                      labelText: 'Base URL',
                      hintText: 'https://example.com/v1',
                      border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(
                  controller: model,
                  decoration: const InputDecoration(
                      labelText: '模型名', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(
                  controller: key,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                      labelText: 'API Key',
                      hintText: hasKey ? '已保存；留空则保持原密钥' : '请输入密钥',
                      border: const OutlineInputBorder())),
              const SizedBox(height: 20),
              TextField(
                  controller: daily,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: '每日请求上限', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(
                  controller: answer,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: '单次答复上限（Token）',
                      border: OutlineInputBorder())),
              const SizedBox(height: 12),
              Text('今日已用 ${current.usedToday} 次'),
              if (message != null)
                Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(message!)),
              const SizedBox(height: 16),
              FilledButton.icon(
                  onPressed: busy ? null : save,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('保存')),
              OutlinedButton.icon(
                  onPressed: busy || !hasKey ? null : test,
                  icon: const Icon(Icons.wifi_tethering),
                  label: const Text('测试连接')),
              if (current.baseUrl.isNotEmpty || hasKey)
                TextButton.icon(
                    onPressed: busy ? null : delete,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('删除连接信息')),
            ]);
          },
        ),
      );
}
