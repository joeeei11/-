import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'guide.dart';

const _releaseApi =
    'https://api.github.com/repos/eternity4719/HowToLiveBetter/releases/latest';
const _maxPackageBytes = 10 * 1024 * 1024;

class GuideRelease {
  const GuideRelease(this.version, this.downloadUrl);

  final String version;
  final Uri downloadUrl;
}

class NoCompatibleGuideRelease implements Exception {
  const NoCompatibleGuideRelease();
}

class GuideUpdater {
  GuideUpdater(
      {HttpClient? client,
      Directory? storage,
      Future<List<int>> Function(Uri)? fetch})
      : _client = client ?? HttpClient(),
        _storage = storage,
        _fetch = fetch;

  final HttpClient _client;
  final Directory? _storage;
  final Future<List<int>> Function(Uri)? _fetch;

  Future<List<int>> _get(Uri uri, {int limit = _maxPackageBytes}) async {
    if (_fetch != null) {
      final bytes = await _fetch(uri);
      if (bytes.length > limit) {
        throw const FormatException('Guide package too large');
      }
      return bytes;
    }
    final request =
        await _client.getUrl(uri).timeout(const Duration(seconds: 15));
    request.headers
        .set(HttpHeaders.userAgentHeader, 'PersonalDecisionAssistant');
    request.headers
        .set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
    final response = await request.close().timeout(const Duration(seconds: 15));
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw HttpException('HTTP ${response.statusCode}', uri: uri);
    }
    final bytes = <int>[];
    await for (final chunk in response.timeout(const Duration(seconds: 30))) {
      bytes.addAll(chunk);
      if (bytes.length > limit) {
        throw const FormatException('Guide package too large');
      }
    }
    return bytes;
  }

  Future<GuideRelease> checkLatest() async {
    final response = jsonDecode(
            utf8.decode(await _get(Uri.parse(_releaseApi), limit: 1024 * 1024)))
        as Map<String, dynamic>;
    final version = response['tag_name'] as String;
    final assets = response['assets'] as List<dynamic>;
    for (final item in assets) {
      final asset = item as Map<String, dynamic>;
      if (asset['name'] != 'guide.json') continue;
      final url = Uri.parse(asset['browser_download_url'] as String);
      if (version.isEmpty ||
          url.scheme != 'https' ||
          url.host != 'github.com' ||
          url.pathSegments.length != 6 ||
          url.pathSegments[0] != 'eternity4719' ||
          url.pathSegments[1] != 'HowToLiveBetter' ||
          url.pathSegments[2] != 'releases' ||
          url.pathSegments[3] != 'download' ||
          url.pathSegments[4] != version ||
          url.pathSegments[5] != 'guide.json') {
        throw const FormatException('Invalid official release asset');
      }
      return GuideRelease(version, url);
    }
    throw const NoCompatibleGuideRelease();
  }

  Future<GuidePackage> install(GuideRelease release) async {
    final contents = utf8.decode(await _get(release.downloadUrl));
    final guide = GuidePackage.parse(contents);
    if (guide.version != release.version) {
      throw const FormatException('Guide version does not match release tag');
    }
    final directory = _storage ?? await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    final target = File('${directory.path}/guide.json');
    final pending = File('${directory.path}/guide.json.pending');
    try {
      await pending.writeAsString(contents, flush: true);
      await pending.rename(target.path);
    } finally {
      if (await pending.exists()) await pending.delete();
    }
    return guide;
  }
}
