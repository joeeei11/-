import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'model_connection.dart';

enum ProfileCategory {
  basics('基本情况'),
  workAndFinance('职业与财务'),
  health('健康限制'),
  family('家庭与责任'),
  goals('目标与偏好'),
  energy('当前压力与精力');

  const ProfileCategory(this.label);
  final String label;
}

class AnswerPreferences {
  const AnswerPreferences(
      {required this.length, required this.tone, required this.order});

  final String length;
  final String tone;
  final String order;

  static const defaults = AnswerPreferences(
    length: '简短',
    tone: '直接',
    order: '先看结论',
  );
}

class ProfileSnapshot {
  const ProfileSnapshot(this.categories, this.preferences);
  final Map<ProfileCategory, String> categories;
  final AnswerPreferences? preferences;
}

abstract class ProfileStore {
  Future<ProfileSnapshot> load();
  Future<void> saveCategory(ProfileCategory category, String value);
  Future<void> deleteCategory(ProfileCategory category);
  Future<void> savePreferences(AnswerPreferences preferences);
  Future<void> deletePreferences();
}

class SecureProfileStore implements ProfileStore {
  SecureProfileStore({FlutterSecureStorage? storage})
      : storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  final FlutterSecureStorage storage;

  String _categoryKey(ProfileCategory category) => 'profile.${category.name}';

  @override
  Future<ProfileSnapshot> load() async {
    final categories = <ProfileCategory, String>{};
    for (final category in ProfileCategory.values) {
      final value = await storage.read(key: _categoryKey(category));
      if (value != null && value.isNotEmpty) categories[category] = value;
    }
    final length = await storage.read(key: 'preferences.length');
    final tone = await storage.read(key: 'preferences.tone');
    final order = await storage.read(key: 'preferences.order');
    final preferences = length == null && tone == null && order == null
        ? null
        : AnswerPreferences(
            length: length ?? AnswerPreferences.defaults.length,
            tone: tone ?? AnswerPreferences.defaults.tone,
            order: order ?? AnswerPreferences.defaults.order,
          );
    return ProfileSnapshot(categories, preferences);
  }

  @override
  Future<void> saveCategory(ProfileCategory category, String value) =>
      storage.write(key: _categoryKey(category), value: value);

  @override
  Future<void> deleteCategory(ProfileCategory category) =>
      storage.delete(key: _categoryKey(category));

  @override
  Future<void> savePreferences(AnswerPreferences preferences) async {
    await storage.write(key: 'preferences.length', value: preferences.length);
    await storage.write(key: 'preferences.tone', value: preferences.tone);
    await storage.write(key: 'preferences.order', value: preferences.order);
  }

  @override
  Future<void> deletePreferences() async {
    await storage.delete(key: 'preferences.length');
    await storage.delete(key: 'preferences.tone');
    await storage.delete(key: 'preferences.order');
  }
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, this.store, this.modelStore});

  final ProfileStore? store;
  final ModelStore? modelStore;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final ProfileStore store = widget.store ?? SecureProfileStore();
  late Future<ProfileSnapshot> snapshot = store.load();

  void refresh() {
    final updated = store.load();
    setState(() {
      snapshot = updated;
    });
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<ProfileSnapshot>(
        future: snapshot,
        builder: (context, result) {
          if (result.hasError) {
            return Center(
              child: TextButton.icon(
                onPressed: refresh,
                icon: const Icon(Icons.refresh),
                label: const Text('资料读取失败，重试'),
              ),
            );
          }
          if (!result.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final profile = result.data!;
          return ListView(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 20, 16, 8),
                child: Text('个人资料'),
              ),
              for (final category in ProfileCategory.values)
                ListTile(
                  title: Text(category.label),
                  subtitle: Text(
                    profile.categories[category] ?? '未填写',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final changed = await Navigator.push<bool>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => _CategoryEditor(
                          store: store,
                          category: category,
                          initialValue: profile.categories[category] ?? '',
                        ),
                      ),
                    );
                    if (changed == true && mounted) refresh();
                  },
                ),
              const Divider(),
              ListTile(
                title: const Text('答复偏好'),
                subtitle: Text(profile.preferences == null
                    ? '未设置'
                    : '${profile.preferences!.length} · ${profile.preferences!.tone} · ${profile.preferences!.order}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final changed = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => _PreferencesEditor(
                        store: store,
                        initialValue: profile.preferences,
                      ),
                    ),
                  );
                  if (changed == true && mounted) refresh();
                },
              ),
              const Divider(),
              ListTile(
                title: const Text('模型连接'),
                subtitle: const Text('地址、密钥与调用上限'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        ModelConnectionScreen(store: widget.modelStore),
                  ),
                ),
              ),
            ],
          );
        },
      );
}

class _CategoryEditor extends StatefulWidget {
  const _CategoryEditor({
    required this.store,
    required this.category,
    required this.initialValue,
  });

  final ProfileStore store;
  final ProfileCategory category;
  final String initialValue;

  @override
  State<_CategoryEditor> createState() => _CategoryEditorState();
}

class _CategoryEditorState extends State<_CategoryEditor> {
  late final controller = TextEditingController(text: widget.initialValue);
  bool busy = false;
  String? error;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> persist({required bool delete}) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final value = controller.text.trim();
      if (delete || value.isEmpty) {
        await widget.store.deleteCategory(widget.category);
      } else {
        await widget.store.saveCategory(widget.category, value);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) setState(() => error = '保存失败，请重试。');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.category.label)),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: controller,
              minLines: 5,
              maxLines: 12,
              decoration: InputDecoration(
                hintText: '按需填写，可留空',
                border: const OutlineInputBorder(),
                labelText: widget.category.label,
                alignLabelWithHint: true,
              ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: busy ? null : () => persist(delete: false),
              icon: const Icon(Icons.save_outlined),
              label: const Text('保存'),
            ),
            if (widget.initialValue.isNotEmpty)
              TextButton.icon(
                onPressed: busy ? null : () => persist(delete: true),
                icon: const Icon(Icons.delete_outline),
                label: const Text('删除这类资料'),
              ),
          ],
        ),
      );
}

class _PreferencesEditor extends StatefulWidget {
  const _PreferencesEditor({required this.store, required this.initialValue});
  final ProfileStore store;
  final AnswerPreferences? initialValue;

  @override
  State<_PreferencesEditor> createState() => _PreferencesEditorState();
}

class _PreferencesEditorState extends State<_PreferencesEditor> {
  late String length =
      (widget.initialValue ?? AnswerPreferences.defaults).length;
  late String tone = (widget.initialValue ?? AnswerPreferences.defaults).tone;
  late String order = (widget.initialValue ?? AnswerPreferences.defaults).order;
  bool busy = false;
  String? error;

  Future<void> persist({required bool delete}) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (delete) {
        await widget.store.deletePreferences();
      } else {
        await widget.store.savePreferences(
          AnswerPreferences(length: length, tone: tone, order: order),
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) setState(() => error = '保存失败，请重试。');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('答复偏好')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _Choice(
              label: '答复长度',
              value: length,
              options: const ['简短', '适中', '详细'],
              onChanged: (value) => setState(() => length = value),
            ),
            _Choice(
              label: '答复语气',
              value: tone,
              options: const ['直接', '温和'],
              onChanged: (value) => setState(() => tone = value),
            ),
            _Choice(
              label: '呈现顺序',
              value: order,
              options: const ['先看结论', '先看理由'],
              onChanged: (value) => setState(() => order = value),
            ),
            if (error != null)
              Text(error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: busy ? null : () => persist(delete: false),
              icon: const Icon(Icons.save_outlined),
              label: const Text('保存'),
            ),
            if (widget.initialValue != null)
              TextButton.icon(
                onPressed: busy ? null : () => persist(delete: true),
                icon: const Icon(Icons.delete_outline),
                label: const Text('删除答复偏好'),
              ),
          ],
        ),
      );
}

class _Choice extends StatelessWidget {
  const _Choice(
      {required this.label,
      required this.value,
      required this.options,
      required this.onChanged});
  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: DropdownButtonFormField<String>(
          value: value,
          decoration: InputDecoration(
              labelText: label, border: const OutlineInputBorder()),
          items: options
              .map((option) => DropdownMenuItem(
                    value: option,
                    child: Text(option),
                  ))
              .toList(),
          onChanged: (value) {
            if (value != null) onChanged(value);
          },
        ),
      );
}
