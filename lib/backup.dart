import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'decision_records.dart';
import 'model_connection.dart';
import 'profile.dart';

class BackupData {
  const BackupData(this.profile, this.records);
  final ProfileSnapshot profile;
  final List<DecisionRecord> records;
}

class BackupCodec {
  static final _cipher = AesGcm.with256bits();
  static final _kdf =
      Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: 210000, bits: 256);

  static List<int> _random(int count) {
    final random = Random.secure();
    return List<int>.generate(count, (_) => random.nextInt(256));
  }

  static Future<List<int>> encode(BackupData data, String password) async {
    if (password.length < 8) throw const FormatException('密码至少需要 8 个字符。');
    final salt = _random(16);
    final key = await _kdf.deriveKey(
        secretKey: SecretKey(utf8.encode(password)), nonce: salt);
    final profile = data.profile;
    final plaintext = utf8.encode(jsonEncode({
      'profile': {
        for (final item in profile.categories.entries) item.key.name: item.value
      },
      'preferences': profile.preferences == null
          ? null
          : {
              'length': profile.preferences!.length,
              'tone': profile.preferences!.tone,
              'order': profile.preferences!.order,
            },
      'records': data.records.map((record) => record.toJson()).toList(),
    }));
    final box =
        await _cipher.encrypt(plaintext, secretKey: key, nonce: _random(12));
    return utf8.encode(jsonEncode({
      'format': 'personal-decision-backup',
      'version': 1,
      'salt': base64Encode(salt),
      'nonce': base64Encode(box.nonce),
      'ciphertext': base64Encode(box.cipherText),
      'mac': base64Encode(box.mac.bytes),
    }));
  }

  static Future<BackupData> decode(List<int> bytes, String password) async {
    try {
      if (bytes.length > 20 * 1024 * 1024) throw const FormatException();
      final envelope = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      if (envelope['format'] != 'personal-decision-backup' ||
          envelope['version'] != 1) {
        throw const FormatException();
      }
      final salt = base64Decode(envelope['salt'] as String);
      final nonce = base64Decode(envelope['nonce'] as String);
      final mac = base64Decode(envelope['mac'] as String);
      if (salt.length != 16 || nonce.length != 12 || mac.length != 16) {
        throw const FormatException();
      }
      final key = await _kdf.deriveKey(
          secretKey: SecretKey(utf8.encode(password)), nonce: salt);
      final plain = await _cipher.decrypt(
        SecretBox(base64Decode(envelope['ciphertext'] as String),
            nonce: nonce, mac: Mac(mac)),
        secretKey: key,
      );
      final data = jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
      final categories = (data['profile'] as Map<String, dynamic>).map(
          (key, value) =>
              MapEntry(ProfileCategory.values.byName(key), value as String));
      final rawPreferences = data['preferences'];
      final preferences = rawPreferences == null
          ? null
          : AnswerPreferences(
              length:
                  (rawPreferences as Map<String, dynamic>)['length'] as String,
              tone: rawPreferences['tone'] as String,
              order: rawPreferences['order'] as String,
            );
      final records = (data['records'] as List)
          .map((item) => DecisionRecord.fromJson(item as Map<String, dynamic>))
          .toList();
      if (records.map((e) => e.id).toSet().length != records.length) {
        throw const FormatException();
      }
      return BackupData(ProfileSnapshot(categories, preferences), records);
    } catch (_) {
      throw const FormatException('无法打开备份：密码错误、文件损坏或格式不受支持。');
    }
  }
}

class BackupService {
  const BackupService(this.profiles, this.records, this.models, this.reminders);
  final ProfileStore profiles;
  final DecisionRecordStore records;
  final ModelStore models;
  final ReviewReminder reminders;

  Future<List<int>> export(String password) async => BackupCodec.encode(
      BackupData(await profiles.load(), await records.load()), password);

  Future<BackupData> inspect(List<int> bytes, String password) =>
      BackupCodec.decode(bytes, password);

  Future<bool> restore(BackupData data) async {
    final old = BackupData(await profiles.load(), await records.load());
    try {
      await _replace(data);
      await models.delete();
    } catch (_) {
      await _replace(old);
      rethrow;
    }
    var remindersRestored = true;
    for (final record in old.records) {
      try {
        await reminders.cancel(record.id);
      } catch (_) {
        remindersRestored = false;
      }
    }
    for (final record in data.records) {
      if (record.reviewDate != null && record.status != ReviewStatus.ended) {
        try {
          if (!await syncReviewReminder(record, records, reminders)) {
            remindersRestored = false;
          }
        } catch (_) {
          remindersRestored = false;
        }
      }
    }
    return remindersRestored;
  }

  Future<void> _replace(BackupData data) async {
    final current = await profiles.load();
    for (final category in ProfileCategory.values) {
      final value = data.profile.categories[category];
      if (value == null) {
        if (current.categories.containsKey(category)) {
          await profiles.deleteCategory(category);
        }
      } else {
        await profiles.saveCategory(category, value);
      }
    }
    if (data.profile.preferences == null) {
      await profiles.deletePreferences();
    } else {
      await profiles.savePreferences(data.profile.preferences!);
    }
    for (final record in await records.load()) {
      await records.delete(record.id);
    }
    for (final record in data.records.reversed) {
      await records.save(record);
    }
  }
}

class BackupDocumentPicker {
  const BackupDocumentPicker();
  static const _channel =
      MethodChannel('personal_decision_assistant/backup_files');

  Future<bool> save(List<int> bytes) async {
    final dir = await getTemporaryDirectory();
    final file = File(
        '${dir.path}/decision-backup-${DateTime.now().millisecondsSinceEpoch}.pdbak');
    try {
      await file.writeAsBytes(bytes, flush: true);
      return await _channel.invokeMethod<bool>('save', {
            'path': file.path,
            'name':
                'decision-backup-${DateTime.now().toIso8601String().substring(0, 10)}.pdbak',
          }) ??
          false;
    } finally {
      if (await file.exists()) await file.delete();
    }
  }

  Future<List<int>?> open() async {
    final path = await _channel.invokeMethod<String>('open');
    if (path == null) return null;
    final file = File(path);
    try {
      if (await file.length() > 20 * 1024 * 1024) {
        throw const FormatException('备份文件超过 20 MB。');
      }
      return await file.readAsBytes();
    } finally {
      if (await file.exists()) await file.delete();
    }
  }
}

class BackupScreen extends StatefulWidget {
  const BackupScreen(
      {super.key, required this.service, BackupDocumentPicker? picker})
      : picker = picker ?? const BackupDocumentPicker();
  final BackupService service;
  final BackupDocumentPicker picker;

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool busy = false;
  String? message;

  Future<String?> _password({required bool creating}) async {
    var entered = '';
    var confirmed = '';
    String? error;
    final value = await showDialog<String>(
        context: context,
        builder: (context) => StatefulBuilder(
            builder: (context, update) => AlertDialog(
                  title: Text(creating ? '设置备份密码' : '输入备份密码'),
                  content: Column(mainAxisSize: MainAxisSize.min, children: [
                    TextField(
                        onChanged: (value) => entered = value,
                        obscureText: true,
                        decoration:
                            const InputDecoration(labelText: '密码（至少 8 个字符）')),
                    if (creating)
                      TextField(
                          onChanged: (value) => confirmed = value,
                          obscureText: true,
                          decoration:
                              const InputDecoration(labelText: '再次输入密码')),
                    if (error != null)
                      Text(error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                  ]),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('取消')),
                    FilledButton(
                        onPressed: () {
                          if (entered.length < 8 ||
                              (creating && entered != confirmed)) {
                            update(() => error =
                                creating ? '密码至少 8 个字符，且两次输入一致。' : '请输入备份密码。');
                          } else {
                            Navigator.pop(context, entered);
                          }
                        },
                        child: const Text('继续')),
                  ],
                )));
    return value;
  }

  Future<void> _export() async {
    final password = await _password(creating: true);
    if (password == null || !mounted) return;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      final saved =
          await widget.picker.save(await widget.service.export(password));
      if (saved && mounted) {
        setState(() => message = '加密备份已导出。请妥善保管密码，遗失后无法恢复。');
      }
    } catch (_) {
      if (mounted) setState(() => message = '导出未完成，请重试。');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _import() async {
    setState(() {
      busy = true;
      message = null;
    });
    try {
      final bytes = await widget.picker.open();
      if (bytes == null || !mounted) return;
      setState(() => busy = false);
      final password = await _password(creating: false);
      if (password == null || !mounted) return;
      setState(() => busy = true);
      final data = await widget.service.inspect(bytes, password);
      if (!mounted) return;
      setState(() => busy = false);
      final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                title: const Text('覆盖当前本地数据？'),
                content: Text(
                    '将用备份中的 ${data.profile.categories.length} 类个人资料、答复偏好和 ${data.records.length} 条决策记录替换当前数据。模型连接将清除，恢复后需要重新填写。'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('取消')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('确认恢复')),
                ],
              ));
      if (confirmed != true || !mounted) return;
      setState(() => busy = true);
      final remindersRestored = await widget.service.restore(data);
      if (mounted) {
        setState(() => message = remindersRestored
            ? '恢复完成。请重新填写模型连接。'
            : '数据已恢复。请重新填写模型连接，并检查复查提醒权限。');
      }
    } on FormatException catch (error) {
      if (mounted) setState(() => message = error.message);
    } catch (_) {
      if (mounted) setState(() => message = '恢复失败，请重试并检查当前数据。');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('备份与恢复')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          const Text('加密备份包含个人资料、答复偏好和决策记录。API Key 与模型连接不会进入备份。'),
          const SizedBox(height: 20),
          FilledButton.icon(
              onPressed: busy ? null : _export,
              icon: const Icon(Icons.file_upload_outlined),
              label: const Text('导出加密备份')),
          OutlinedButton.icon(
              onPressed: busy ? null : _import,
              icon: const Icon(Icons.file_download_outlined),
              label: const Text('导入加密备份')),
          if (busy)
            const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator())),
          if (message != null)
            Padding(
                padding: const EdgeInsets.only(top: 16), child: Text(message!)),
        ]),
      );
}
