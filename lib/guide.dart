import 'dart:convert';

import 'package:flutter/services.dart';

class GuidePackage {
  const GuidePackage({
    required this.version,
    required this.updatedAt,
    required this.project,
    required this.projectUrl,
    required this.license,
    required this.licenseUrl,
    required this.entries,
  });

  final String version;
  final String updatedAt;
  final String project;
  final String projectUrl;
  final String license;
  final String licenseUrl;
  final List<GuideEntry> entries;

  static Future<GuidePackage> load() async {
    final bytes = await rootBundle.load('assets/guide.json');
    final data = jsonDecode(utf8.decode(bytes.buffer.asUint8List()))
        as Map<String, dynamic>;
    return GuidePackage(
      version: data['version'] as String,
      updatedAt: data['updatedAt'] as String,
      project: data['project'] as String,
      projectUrl: data['projectUrl'] as String,
      license: data['license'] as String,
      licenseUrl: data['licenseUrl'] as String,
      entries: (data['entries'] as List<dynamic>)
          .map((item) => GuideEntry.fromJson(item as Map<String, dynamic>))
          .toList(growable: false),
    );
  }

  List<GuideEntry> search(String query, {String? chapter}) {
    final terms = query.trim().toLowerCase().split(RegExp(r'\s+'));
    return entries.where((entry) {
      if (chapter != null && entry.chapter != chapter) return false;
      if (query.trim().isEmpty) return true;
      final searchable = [
        entry.title,
        entry.chapter,
        entry.summary,
        entry.benefit,
        entry.cost,
        entry.source,
      ].join(' ').toLowerCase();
      return terms.every(searchable.contains);
    }).toList(growable: false);
  }
}

class GuideEntry {
  const GuideEntry({
    required this.id,
    required this.chapter,
    required this.title,
    required this.summary,
    required this.benefit,
    required this.cost,
    required this.evidence,
    required this.source,
    required this.note,
    required this.sourcePath,
  });

  final String id;
  final String chapter;
  final String title;
  final String summary;
  final String benefit;
  final String cost;
  final String evidence;
  final String source;
  final String note;
  final String sourcePath;

  factory GuideEntry.fromJson(Map<String, dynamic> data) => GuideEntry(
        id: data['id'] as String,
        chapter: data['chapter'] as String,
        title: data['title'] as String,
        summary: data['summary'] as String,
        benefit: data['benefit'] as String? ?? '',
        cost: data['cost'] as String,
        evidence: data['evidence'] as String,
        source: data['source'] as String,
        note: data['note'] as String? ?? '',
        sourcePath: data['sourcePath'] as String,
      );
}
