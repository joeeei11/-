import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'consultation.dart';
import 'guide.dart';
import 'profile.dart';

enum ReviewStatus { pending, continueDecision, changed, ended }

extension ReviewStatusLabel on ReviewStatus {
  String get label => switch (this) {
        ReviewStatus.pending => '待复查',
        ReviewStatus.continueDecision => '继续',
        ReviewStatus.changed => '修改',
        ReviewStatus.ended => '结束',
      };
}

class DecisionRecord {
  const DecisionRecord({
    required this.id,
    required this.question,
    required this.answer,
    required this.finalChoice,
    required this.guideVersion,
    required this.profileSnapshot,
    required this.savedAt,
    this.reviewDate,
    this.status = ReviewStatus.pending,
  });

  final String id;
  final String question;
  final DecisionAnswer answer;
  final String finalChoice;
  final String guideVersion;
  final Map<ProfileCategory, String> profileSnapshot;
  final DateTime savedAt;
  final DateTime? reviewDate;
  final ReviewStatus status;

  DecisionRecord copyWith(
          {String? finalChoice,
          DateTime? reviewDate,
          bool clearReviewDate = false,
          ReviewStatus? status}) =>
      DecisionRecord(
        id: id,
        question: question,
        answer: answer,
        finalChoice: finalChoice ?? this.finalChoice,
        guideVersion: guideVersion,
        profileSnapshot: profileSnapshot,
        savedAt: savedAt,
        reviewDate: clearReviewDate ? null : reviewDate ?? this.reviewDate,
        status: status ?? this.status,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'question': question,
        'finalChoice': finalChoice,
        'guideVersion': guideVersion,
        'profileSnapshot': {
          for (final item in profileSnapshot.entries) item.key.name: item.value,
        },
        'savedAt': savedAt.toIso8601String(),
        'reviewDate': reviewDate?.toIso8601String(),
        'status': status.name,
        'answer': {
          'conclusion': answer.conclusion,
          'nextStep': answer.nextStep,
          'reason': answer.reason,
          'risk': answer.risk,
          'reviewDate': answer.reviewDate,
          'unknown': answer.unknown,
          'route': answer.route.name,
          'usedProfileFields':
              answer.usedProfileFields.map((e) => e.name).toList(),
          'citations': answer.citations
              .map((e) => {
                    'id': e.id,
                    'chapter': e.chapter,
                    'title': e.title,
                    'summary': e.summary,
                    'benefit': e.benefit,
                    'cost': e.cost,
                    'evidence': e.evidence,
                    'source': e.source,
                    'note': e.note,
                    'sourcePath': e.sourcePath,
                  })
              .toList(),
        },
      };

  factory DecisionRecord.fromJson(Map<String, dynamic> data) {
    final rawAnswer = data['answer'] as Map<String, dynamic>;
    return DecisionRecord(
      id: data['id'] as String,
      question: data['question'] as String,
      finalChoice: data['finalChoice'] as String,
      guideVersion: data['guideVersion'] as String,
      profileSnapshot: (data['profileSnapshot'] as Map<String, dynamic>).map(
          (key, value) =>
              MapEntry(ProfileCategory.values.byName(key), value as String)),
      savedAt: DateTime.parse(data['savedAt'] as String),
      reviewDate: data['reviewDate'] == null
          ? null
          : DateTime.parse(data['reviewDate'] as String),
      status: ReviewStatus.values.byName(data['status'] as String),
      answer: DecisionAnswer(
        conclusion: rawAnswer['conclusion'] as String,
        nextStep: rawAnswer['nextStep'] as String,
        reason: rawAnswer['reason'] as String,
        risk: rawAnswer['risk'] as String,
        reviewDate: rawAnswer['reviewDate'] as String,
        unknown: rawAnswer['unknown'] as String,
        route: RiskRoute.values.byName(rawAnswer['route'] as String),
        usedProfileFields: (rawAnswer['usedProfileFields'] as List)
            .map((e) => ProfileCategory.values.byName(e as String))
            .toList(),
        citations: (rawAnswer['citations'] as List)
            .map((e) => GuideEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
      ),
    );
  }
}

abstract class DecisionRecordStore {
  Future<List<DecisionRecord>> load();
  Future<void> save(DecisionRecord record);
  Future<void> delete(String id);
  Future<bool> hasRequestedNotificationPermission();
  Future<void> markNotificationPermissionRequested();
}

class SecureDecisionRecordStore implements DecisionRecordStore {
  SecureDecisionRecordStore({FlutterSecureStorage? storage})
      : storage = storage ??
            const FlutterSecureStorage(
                aOptions: AndroidOptions(encryptedSharedPreferences: true));

  final FlutterSecureStorage storage;
  static const _recordsKey = 'decisions.records';
  static const _permissionKey = 'decisions.notificationPermissionRequested';

  @override
  Future<List<DecisionRecord>> load() async {
    final raw = await storage.read(key: _recordsKey);
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .map((item) => DecisionRecord.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> save(DecisionRecord record) async {
    final records = await load();
    records.removeWhere((item) => item.id == record.id);
    records.insert(0, record);
    await storage.write(
        key: _recordsKey,
        value: jsonEncode(records.map((item) => item.toJson()).toList()));
  }

  @override
  Future<void> delete(String id) async {
    final records = await load();
    records.removeWhere((item) => item.id == id);
    await storage.write(
        key: _recordsKey,
        value: jsonEncode(records.map((item) => item.toJson()).toList()));
  }

  @override
  Future<bool> hasRequestedNotificationPermission() async =>
      await storage.read(key: _permissionKey) == 'true';

  @override
  Future<void> markNotificationPermissionRequested() =>
      storage.write(key: _permissionKey, value: 'true');
}

abstract class ReviewReminder {
  Future<bool> requestPermission();
  Future<bool> schedule(String id, DateTime date);
  Future<void> cancel(String id);
  Future<bool> openedFromReminder();
}

class AndroidReviewReminder implements ReviewReminder {
  static const channel =
      MethodChannel('personal_decision_assistant/review_reminders');

  @override
  Future<bool> requestPermission() async =>
      await channel.invokeMethod<bool>('requestPermission') ?? false;

  @override
  Future<bool> schedule(String id, DateTime date) async =>
      await channel.invokeMethod<bool>('schedule', {
        'id': id,
        'at':
            DateTime(date.year, date.month, date.day, 9).millisecondsSinceEpoch,
      }) ??
      false;

  @override
  Future<void> cancel(String id) =>
      channel.invokeMethod<void>('cancel', {'id': id});

  @override
  Future<bool> openedFromReminder() async =>
      await channel.invokeMethod<bool>('openedFromReminder') ?? false;
}

Future<bool> syncReviewReminder(DecisionRecord record,
    DecisionRecordStore store, ReviewReminder reminder) async {
  if (record.reviewDate == null || record.status == ReviewStatus.ended) {
    await reminder.cancel(record.id);
    return true;
  }
  final now = DateTime.now();
  if (record.reviewDate!.isBefore(DateTime(now.year, now.month, now.day))) {
    await reminder.cancel(record.id);
    return true;
  }
  if (!await store.hasRequestedNotificationPermission()) {
    await store.markNotificationPermissionRequested();
    if (!await reminder.requestPermission()) return false;
  }
  return reminder.schedule(record.id, record.reviewDate!);
}

class RecordsScreen extends StatefulWidget {
  const RecordsScreen({super.key, required this.store, required this.reminder});
  final DecisionRecordStore store;
  final ReviewReminder reminder;

  @override
  State<RecordsScreen> createState() => _RecordsScreenState();
}

class _RecordsScreenState extends State<RecordsScreen> {
  late Future<List<DecisionRecord>> records = widget.store.load();

  void refresh() {
    final updated = widget.store.load();
    setState(() {
      records = updated;
    });
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<DecisionRecord>>(
        future: records,
        builder: (context, result) {
          if (result.hasError) {
            return Center(
                child: TextButton.icon(
                    onPressed: refresh,
                    icon: const Icon(Icons.refresh),
                    label: const Text('记录读取失败，重试')));
          }
          if (!result.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (result.data!.isEmpty) {
            return const Center(child: Text('还没有保存的决策'));
          }
          return RefreshIndicator(
            onRefresh: () async {
              refresh();
              await records;
            },
            child: ListView.builder(
              itemCount: result.data!.length,
              itemBuilder: (context, index) {
                final record = result.data![index];
                return ListTile(
                  title: Text(record.question,
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                      '${record.status.label} · ${record.reviewDate == null ? '未设复查日期' : formatReviewDate(record.reviewDate!)}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                            builder: (_) => RecordDetailScreen(
                                record: record,
                                store: widget.store,
                                reminder: widget.reminder)));
                    if (mounted) refresh();
                  },
                );
              },
            ),
          );
        },
      );
}

String formatReviewDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

class RecordDetailScreen extends StatefulWidget {
  const RecordDetailScreen(
      {super.key,
      required this.record,
      required this.store,
      required this.reminder});
  final DecisionRecord record;
  final DecisionRecordStore store;
  final ReviewReminder reminder;

  @override
  State<RecordDetailScreen> createState() => _RecordDetailScreenState();
}

class _RecordDetailScreenState extends State<RecordDetailScreen> {
  late DecisionRecord record = widget.record;
  bool busy = false;
  String? message;

  Future<void> update(DecisionRecord next) async {
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await widget.store.save(next);
      if (mounted) setState(() => record = next);
      bool scheduled;
      try {
        scheduled =
            await syncReviewReminder(next, widget.store, widget.reminder);
      } catch (_) {
        scheduled = false;
      }
      if (mounted) {
        setState(() {
          if (!scheduled) message = '记录已保存；通知未开启，请在系统设置中允许通知。';
        });
      }
    } catch (_) {
      if (mounted) setState(() => message = '更新失败，请重试。');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> edit() async {
    final edited = await showDecisionEditor(context,
        initialChoice: record.finalChoice,
        initialDate: record.reviewDate,
        suggestedDate: record.answer.reviewDate);
    if (edited != null) {
      await update(record.copyWith(
          finalChoice: edited.$1,
          reviewDate: edited.$2,
          clearReviewDate: edited.$2 == null));
    }
  }

  Future<void> delete() async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('删除这条决策？'),
                content: const Text('答复和当次已用资料快照会一并删除。'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('取消')),
                  TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('删除'))
                ]));
    if (confirmed != true || !mounted) return;
    setState(() => busy = true);
    try {
      await widget.store.delete(record.id);
      await widget.reminder.cancel(record.id);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          message = '删除失败，请重试。';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('决策记录'), actions: [
          IconButton(
              onPressed: busy ? null : delete,
              tooltip: '删除记录',
              icon: const Icon(Icons.delete_outline)),
        ]),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Text(record.question, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Text('最终选择', style: Theme.of(context).textTheme.titleMedium),
          Text(record.finalChoice),
          const SizedBox(height: 12),
          Text(
              '复查日期：${record.reviewDate == null ? '未设置' : formatReviewDate(record.reviewDate!)}'),
          Text('状态：${record.status.label}'),
          TextButton.icon(
              onPressed: busy ? null : edit,
              icon: const Icon(Icons.edit_outlined),
              label: const Text('修改选择和日期')),
          if (message != null)
            Text(message!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          const Divider(),
          Text('原答复', style: Theme.of(context).textTheme.titleMedium),
          Text('结论：${record.answer.conclusion}'),
          Text('今天的下一步：${record.answer.nextStep}'),
          ExpansionTile(
              title: const Text('理由或证据'),
              children: [ListTile(title: Text(record.answer.reason))]),
          ExpansionTile(
              title: const Text('风险'),
              children: [ListTile(title: Text(record.answer.risk))]),
          ExpansionTile(title: const Text('指南引用与未知信息'), children: [
            for (final entry in record.answer.citations)
              ListTile(
                  title: Text(entry.title),
                  subtitle: Text(
                      '${entry.chapter} · 证据 ${entry.evidence} · ${entry.source} · 版本 ${record.guideVersion}')),
            ListTile(
                title: const Text('未知信息'),
                subtitle: Text(record.answer.unknown)),
          ]),
          ExpansionTile(title: const Text('当次已用资料'), children: [
            if (record.profileSnapshot.isEmpty)
              const ListTile(title: Text('无')),
            for (final item in record.profileSnapshot.entries)
              ListTile(title: Text(item.key.label), subtitle: Text(item.value)),
          ]),
          const SizedBox(height: 16),
          Text('复查结果', style: Theme.of(context).textTheme.titleMedium),
          Wrap(spacing: 8, children: [
            for (final status in [
              ReviewStatus.continueDecision,
              ReviewStatus.changed,
              ReviewStatus.ended
            ])
              ChoiceChip(
                  label: Text(status.label),
                  selected: record.status == status,
                  onSelected: busy
                      ? null
                      : (_) => update(record.copyWith(status: status))),
          ]),
        ]),
      );
}

Future<(String, DateTime?)?> showDecisionEditor(BuildContext context,
    {required String initialChoice,
    required DateTime? initialDate,
    required String suggestedDate}) async {
  final controller = TextEditingController(text: initialChoice);
  DateTime? selectedDate = initialDate ?? DateTime.tryParse(suggestedDate);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  if (initialDate == null &&
      selectedDate != null &&
      (selectedDate.isBefore(today) ||
          selectedDate.isAfter(DateTime(now.year + 10)))) {
    selectedDate = null;
  }
  var hasDate = selectedDate != null;
  final result = await showDialog<(String, DateTime?)>(
      context: context,
      builder: (context) => StatefulBuilder(
          builder: (context, setState) => AlertDialog(
                title: const Text('保存决策'),
                content: SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                  TextField(
                      controller: controller,
                      maxLines: 3,
                      maxLength: 500,
                      decoration: const InputDecoration(
                          labelText: '我的最终选择', border: OutlineInputBorder())),
                  SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('设置复查日期'),
                      value: hasDate,
                      onChanged: (value) => setState(() => hasDate = value)),
                  if (hasDate)
                    ListTile(
                        title: Text(selectedDate == null
                            ? '选择日期'
                            : formatReviewDate(selectedDate!)),
                        subtitle: const Text('点击修改建议日期'),
                        trailing: const Icon(Icons.calendar_today_outlined),
                        onTap: () async {
                          final now = DateTime.now();
                          final chosen = await showDatePicker(
                              context: context,
                              initialDate: selectedDate != null &&
                                      !selectedDate!.isBefore(DateTime(
                                          now.year, now.month, now.day))
                                  ? selectedDate!
                                  : now,
                              firstDate: DateTime(now.year, now.month, now.day),
                              lastDate: DateTime(now.year + 10));
                          if (chosen != null) {
                            setState(() => selectedDate = chosen);
                          }
                        }),
                ])),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('取消')),
                  FilledButton(
                      onPressed: () {
                        final choice = controller.text.trim();
                        if (choice.isEmpty ||
                            (hasDate && selectedDate == null)) {
                          return;
                        }
                        Navigator.pop(
                            context, (choice, hasDate ? selectedDate : null));
                      },
                      child: const Text('保存')),
                ],
              )));
  controller.dispose();
  return result;
}
