import 'package:flutter/material.dart';

import 'guide.dart';

void main() => runApp(const DecisionGuideApp());

class DecisionGuideApp extends StatelessWidget {
  const DecisionGuideApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: '个人决策助手',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF176B55),
            surface: const Color(0xFFF7F8F6),
          ),
          scaffoldBackgroundColor: const Color(0xFFF7F8F6),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFFF7F8F6),
            centerTitle: false,
          ),
        ),
        home: const HomeScreen(),
      );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int selectedIndex = 3;

  @override
  Widget build(BuildContext context) {
    const labels = ['咨询', '记录', '资料', '指南'];
    return Scaffold(
      appBar: AppBar(title: Text(labels[selectedIndex])),
      body: IndexedStack(
        index: selectedIndex,
        children: const [
          _PendingPage(icon: Icons.chat_bubble_outline, title: '咨询'),
          _PendingPage(icon: Icons.bookmark_outline, title: '记录'),
          _PendingPage(icon: Icons.person_outline, title: '资料'),
          GuideScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) => setState(() => selectedIndex = index),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.chat_bubble_outline), label: '咨询'),
          NavigationDestination(
              icon: Icon(Icons.bookmark_outline), label: '记录'),
          NavigationDestination(icon: Icon(Icons.person_outline), label: '资料'),
          NavigationDestination(
              icon: Icon(Icons.menu_book_outlined), label: '指南'),
        ],
      ),
    );
  }
}

class _PendingPage extends StatelessWidget {
  const _PendingPage({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 36, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text('$title即将开放', style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      );
}

class GuideScreen extends StatefulWidget {
  const GuideScreen({super.key});

  @override
  State<GuideScreen> createState() => _GuideScreenState();
}

class _GuideScreenState extends State<GuideScreen> {
  late final Future<GuidePackage> package = GuidePackage.load();
  final queryController = TextEditingController();
  String? chapter;

  @override
  void dispose() {
    queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<GuidePackage>(
        future: package,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('指南包无法读取，请重新安装应用。'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final guide = snapshot.data!;
          final chapters =
              guide.entries.map((entry) => entry.chapter).toSet().toList();
          final results = guide.search(queryController.text, chapter: chapter);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: queryController,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: '搜索指南条目',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: queryController.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: '清除搜索',
                                icon: const Icon(Icons.close),
                                onPressed: () {
                                  queryController.clear();
                                  setState(() {});
                                },
                              ),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.filter_list, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String?>(
                              value: chapter,
                              isExpanded: true,
                              hint: const Text('全部章节'),
                              items: [
                                const DropdownMenuItem<String?>(
                                  value: null,
                                  child: Text('全部章节'),
                                ),
                                ...chapters
                                    .map((name) => DropdownMenuItem<String?>(
                                          value: name,
                                          child: Text(name,
                                              overflow: TextOverflow.ellipsis),
                                        )),
                              ],
                              onChanged: (value) =>
                                  setState(() => chapter = value),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text('${results.length} 条',
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: results.isEmpty
                    ? const Center(child: Text('没有找到匹配的指南条目'))
                    : ListView.separated(
                        itemCount: results.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, indent: 16),
                        itemBuilder: (context, index) {
                          final entry = results[index];
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 4),
                            title: Text(entry.title,
                                maxLines: 2, overflow: TextOverflow.ellipsis),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                  '${entry.chapter} · 第 ${entry.id.split('-').last} 条 · 证据 ${entry.evidence}'),
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.of(context)
                                .push(MaterialPageRoute<void>(
                              builder: (_) =>
                                  GuideEntryScreen(entry: entry, guide: guide),
                            )),
                          );
                        },
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                child: Text(
                  '${guide.project} · ${guide.license} · 版本 ${guide.version.substring(0, 7)}',
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          );
        },
      );
}

class GuideEntryScreen extends StatelessWidget {
  const GuideEntryScreen({super.key, required this.entry, required this.guide});

  final GuideEntry entry;
  final GuidePackage guide;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('第 ${entry.id.split('-').last} 条')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            Text(entry.chapter, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 10),
            Text(entry.title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 24),
            _Detail(label: '建议', value: entry.summary),
            if (entry.benefit.isNotEmpty)
              _Detail(label: '收益与依据', value: entry.benefit),
            _Detail(label: '成本', value: entry.cost),
            _Detail(label: '证据等级', value: entry.evidence),
            _Detail(label: '来源', value: entry.source),
            if (entry.note.isNotEmpty) _Detail(label: '备注', value: entry.note),
            _Detail(
                label: '指南版本',
                value: '${guide.version}\n更新日期：${guide.updatedAt}'),
            _Detail(
                label: '项目与许可',
                value:
                    '${guide.project}\n${guide.projectUrl}\n${guide.license} · ${guide.licenseUrl}'),
          ],
        ),
      );
}

class _Detail extends StatelessWidget {
  const _Detail({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            SelectableText(value,
                style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      );
}
