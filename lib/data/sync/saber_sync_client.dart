// 🤖 Generated wholely or partially with GPT-5 Codex; OpenAI
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:logging/logging.dart';
import 'package:nextcloud/core.dart';
import 'package:nextcloud/nextcloud.dart';
import 'package:nextcloud/provisioning_api.dart';
import 'package:nextcloud/webdav.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/nextcloud/errors.dart';
import 'package:saber/data/nextcloud/nextcloud_client_extension.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/version.dart';
import 'package:xml/xml.dart';

enum SyncBackend { nextcloud, webdav }

class SaberRemoteFile {
  const SaberRemoteFile({
    required this.path,
    required this.isDirectory,
    this.size,
    this.lastModified,
  });

  final String path;
  final bool isDirectory;
  final int? size;
  final DateTime? lastModified;

  @override
  bool operator ==(Object other) =>
      other is SaberRemoteFile && other.path == path;

  @override
  int get hashCode => path.hashCode;
}

abstract class SaberSyncClient {
  const SaberSyncClient();

  static const configFileName = NextcloudClientExtension.configFileName;
  static final configFileUri = PathUri.parse(
    '${FileManager.appRootDirectoryPrefix}/$configFileName',
  );
  static const reproducibleSalt = NextcloudClientExtension.reproducibleSalt;

  static final log = Logger('SaberSyncClient');

  static SaberSyncClient? withSavedDetails() {
    if (stows.username.value.isEmpty || stows.ncPassword.value.isEmpty) {
      return null;
    }

    return switch (stows.syncBackend.value) {
      SyncBackend.nextcloud => NextcloudSaberSyncClient.withSavedDetails(),
      SyncBackend.webdav => WebDavSaberSyncClient.withSavedDetails(),
    };
  }

  Encrypter get encrypter;

  Future<Set<SaberRemoteFile>> findRemoteFiles();
  Future<SaberRemoteFile?> getRemoteFile(String remotePath);
  Future<Uint8List> download(String remotePath);
  Future<void> upload(
    Uint8List bytes,
    String remotePath, {
    DateTime? lastModified,
  });
  Future<Map<String, String>> getConfig();
  Future<void> setConfig(Map<String, String> config);
  Future<String> getUsername();

  Future<Uint8List?> getAvatar() async => null;

  Future<UserDetailsQuota?> getStorageQuota() async => null;

  Future<void> validateCredentials() async {
    await getUsername();
  }

  Future<Map<String, String>> generateConfig({
    required Map<String, String> config,
    Encrypter? encrypter,
    IV? iv,
    Key? key,
  }) async {
    encrypter ??= this.encrypter;
    iv ??= IV.fromBase64(stows.iv.value);
    key ??= Key.fromBase64(stows.key.value);

    config[stows.key.key] = encrypter.encrypt(key.base64, iv: iv).base64;
    config[stows.iv.key] = iv.base64;
    return config;
  }

  Future<String> loadEncryptionKey({bool generateKeyIfMissing = true}) async {
    final config = await getConfig();
    if (config.containsKey(stows.key.key) && config.containsKey(stows.iv.key)) {
      final iv = IV.fromBase64(config[stows.iv.key]!);
      final encryptedKey = config[stows.key.key]!;
      try {
        final key = encrypter.decrypt64(encryptedKey, iv: iv);
        stows.key.value = key;
        stows.iv.value = iv.base64;
        return key;
      } catch (_) {
        throw EncLoginFailure();
      }
    }

    if (!generateKeyIfMissing) throw EncLoginFailure();

    final remoteFiles = await findRemoteFiles();
    if (remoteFiles.isNotEmpty) {
      log.warning(
        'Refusing to generate a new encryption key because remote files '
        'already exist but $configFileName is missing or unreadable.',
      );
      throw EncLoginFailure();
    }

    final key = Key.fromSecureRandom(32);
    final iv = IV.fromSecureRandom(16);
    await generateConfig(config: config, iv: iv, key: key);
    await setConfig(config);

    stows.key.value = key.base64;
    stows.iv.value = iv.base64;
    return key.base64;
  }

  static Encrypter buildEncrypter() {
    final encodedPassword = utf8.encode(
      stows.encPassword.value + reproducibleSalt,
    );
    final hashedPasswordBytes = sha256.convert(encodedPassword).bytes;
    final passwordKey = Key(Uint8List.fromList(hashedPasswordBytes));
    return Encrypter(AES(passwordKey));
  }
}

class NextcloudSaberSyncClient extends SaberSyncClient {
  NextcloudSaberSyncClient(this.client);

  final NextcloudClient client;

  static NextcloudSaberSyncClient? withSavedDetails() {
    final client = NextcloudClientExtension.withSavedDetails();
    return client == null ? null : NextcloudSaberSyncClient(client);
  }

  @override
  Encrypter get encrypter => client.encrypter;

  @override
  Future<Set<SaberRemoteFile>> findRemoteFiles() async {
    try {
      final multistatus = await client.webdav.propfind(
        PathUri.parse(FileManager.appRootDirectoryPrefix),
        prop: const WebDavPropWithoutValues.fromBools(
          davGetcontentlength: true,
          davGetlastmodified: true,
          davResourcetype: true,
        ),
      );

      return multistatus
          .toWebDavFiles()
          .where(
            (file) =>
                file.path.path != '${FileManager.appRootDirectoryPrefix}/',
          )
          .map(_toRemoteFile)
          .toSet();
    } on DynamiteStatusCodeException catch (e) {
      if (e.statusCode != HttpStatus.notFound) rethrow;

      await client.webdav.mkcol(
        PathUri.parse(FileManager.appRootDirectoryPrefix),
      );
      return {};
    }
  }

  @override
  Future<SaberRemoteFile?> getRemoteFile(String remotePath) async {
    try {
      final multistatus = await client.webdav.propfind(
        PathUri.parse(remotePath),
        prop: const WebDavPropWithoutValues.fromBools(
          davGetcontentlength: true,
          davGetlastmodified: true,
          davResourcetype: true,
        ),
      );
      return _toRemoteFile(multistatus.toWebDavFiles().first);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Uint8List> download(String remotePath) async {
    return client.webdav.get(PathUri.parse(remotePath));
  }

  @override
  Future<void> upload(
    Uint8List bytes,
    String remotePath, {
    DateTime? lastModified,
  }) async {
    await client.webdav.put(
      bytes,
      PathUri.parse(remotePath),
      lastModified: lastModified,
    );
  }

  @override
  Future<Map<String, String>> getConfig() => client.getConfig();

  @override
  Future<void> setConfig(Map<String, String> config) =>
      client.setConfig(config);

  @override
  Future<String> getUsername() => client.getUsername();

  @override
  Future<Uint8List?> getAvatar() async {
    final username = stows.username.value;
    if (username.isEmpty) return null;

    final response = await client.core.avatar.getAvatar(
      userId: username,
      size: AvatarGetAvatarSize.$512,
    );
    return response.body;
  }

  @override
  Future<UserDetailsQuota?> getStorageQuota() async {
    final user = await client.provisioningApi.users.getCurrentUser();
    return user.body.ocs.data.quota;
  }

  SaberRemoteFile _toRemoteFile(WebDavFile file) {
    return SaberRemoteFile(
      path: file.path.path,
      isDirectory: file.isDirectory,
      size: file.size,
      lastModified: file.lastModified,
    );
  }
}

class WebDavSaberSyncClient extends SaberSyncClient {
  WebDavSaberSyncClient({
    required Uri baseUri,
    required this.username,
    required this.password,
    http.Client? httpClient,
  }) : baseUri = _normalizeBaseUri(baseUri),
       httpClient =
           httpClient ?? IOClient(HttpClient()..userAgent = _userAgent);

  final Uri baseUri;
  final String username;
  final String password;
  final http.Client httpClient;

  static final _userAgent =
      'Saber/$buildName '
      '(${Platform.operatingSystem}) '
      'Dart/${Platform.version.split(' ').first}';

  static WebDavSaberSyncClient? withSavedDetails() {
    final rawUrl = stows.url.value;
    if (rawUrl.isEmpty) return null;

    return WebDavSaberSyncClient(
      baseUri: Uri.parse(rawUrl),
      username: stows.username.value,
      password: stows.ncPassword.value,
    );
  }

  @override
  Encrypter get encrypter => SaberSyncClient.buildEncrypter();

  @override
  Future<void> validateCredentials() async {
    await _propfind(
      FileManager.appRootDirectoryPrefix,
      depth: '0',
      allowNotFound: true,
    );
  }

  @override
  Future<Set<SaberRemoteFile>> findRemoteFiles() async {
    final response = await _propfind(
      FileManager.appRootDirectoryPrefix,
      depth: '1',
      allowNotFound: true,
    );
    if (response == null) {
      await _mkcol(FileManager.appRootDirectoryPrefix);
      return {};
    }

    return _parsePropfind(response)
        .where((file) => file.path != '${FileManager.appRootDirectoryPrefix}/')
        .toSet();
  }

  @override
  Future<SaberRemoteFile?> getRemoteFile(String remotePath) async {
    final response = await _propfind(
      remotePath,
      depth: '0',
      allowNotFound: true,
    );
    if (response == null) return null;

    final files = _parsePropfind(response);
    return files.firstWhere(
      (file) => file.path == remotePath || file.path == '$remotePath/',
      orElse: () => files.first,
    );
  }

  @override
  Future<Uint8List> download(String remotePath) async {
    final response = await _send('GET', remotePath, expectedStatusCodes: {200});
    return response!.bodyBytes;
  }

  @override
  Future<void> upload(
    Uint8List bytes,
    String remotePath, {
    DateTime? lastModified,
  }) async {
    final headers = <String, String>{};
    if (lastModified != null) {
      headers[HttpHeaders.lastModifiedHeader] = HttpDate.format(lastModified);
    }

    await _send(
      'PUT',
      remotePath,
      bodyBytes: bytes,
      headers: headers,
      expectedStatusCodes: {201, 204},
    );
  }

  @override
  Future<Map<String, String>> getConfig() async {
    final response = await _send(
      'GET',
      SaberSyncClient.configFileUri.path,
      expectedStatusCodes: {200},
      allowNotFound: true,
    );
    if (response == null) return {};

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    return (decoded as Map<String, dynamic>).cast<String, String>();
  }

  @override
  Future<void> setConfig(Map<String, String> config) async {
    await _mkcol(FileManager.appRootDirectoryPrefix);
    await upload(
      Uint8List.fromList(utf8.encode(jsonEncode(config))),
      SaberSyncClient.configFileUri.path,
    );
  }

  @override
  Future<String> getUsername() async => username;

  Future<http.Response?> _propfind(
    String remotePath, {
    required String depth,
    bool allowNotFound = false,
  }) {
    const body =
        '<?xml version="1.0"?>'
        '<d:propfind xmlns:d="DAV:">'
        '<d:prop>'
        '<d:getcontentlength />'
        '<d:getlastmodified />'
        '<d:resourcetype />'
        '</d:prop>'
        '</d:propfind>';

    return _send(
      'PROPFIND',
      remotePath,
      headers: {'Depth': depth},
      bodyBytes: Uint8List.fromList(utf8.encode(body)),
      expectedStatusCodes: {207},
      allowNotFound: allowNotFound,
    );
  }

  Future<void> _mkcol(String remotePath) async {
    await _send(
      'MKCOL',
      remotePath,
      expectedStatusCodes: {201, 405},
      allowRedirect: true,
    );
  }

  Future<http.Response?> _send(
    String method,
    String remotePath, {
    Map<String, String>? headers,
    Uint8List? bodyBytes,
    Set<int> expectedStatusCodes = const {200},
    bool allowNotFound = false,
    bool allowRedirect = false,
  }) async {
    final request = http.Request(method, _resolve(remotePath));
    request.headers.addAll(_baseHeaders());
    if (headers != null) request.headers.addAll(headers);
    if (bodyBytes != null) request.bodyBytes = bodyBytes;

    final streamedResponse = await httpClient.send(request);
    final response = await http.Response.fromStream(streamedResponse);

    if (allowNotFound && response.statusCode == HttpStatus.notFound) {
      return null;
    }
    if (allowRedirect &&
        {
          HttpStatus.movedPermanently,
          HttpStatus.found,
        }.contains(response.statusCode)) {
      return response;
    }
    if (!expectedStatusCodes.contains(response.statusCode)) {
      throw HttpException(
        'WebDAV $method failed (${response.statusCode}) for ${request.url}',
      );
    }

    return response;
  }

  Map<String, String> _baseHeaders() {
    return {
      HttpHeaders.authorizationHeader:
          'Basic ${base64Encode(utf8.encode('$username:$password'))}',
      HttpHeaders.userAgentHeader: _userAgent,
    };
  }

  Uri _resolve(String remotePath) {
    final sanitized = remotePath.startsWith('/')
        ? remotePath.substring(1)
        : remotePath;
    return baseUri.resolve(sanitized);
  }

  List<SaberRemoteFile> _parsePropfind(http.Response response) {
    final document = XmlDocument.parse(utf8.decode(response.bodyBytes));
    return document.descendants
        .whereType<XmlElement>()
        .where((element) => element.name.local == 'response')
        .map(_parseResponse)
        .whereType<SaberRemoteFile>()
        .toList(growable: false);
  }

  SaberRemoteFile? _parseResponse(XmlElement response) {
    final href = _directChildText(response, 'href');
    if (href == null) return null;

    final propstats = response.children.whereType<XmlElement>().where(
      (element) => element.name.local == 'propstat',
    );
    XmlElement? successProp;
    for (final propstat in propstats) {
      final status = _directChildText(propstat, 'status') ?? '';
      if (!status.contains('200')) continue;
      successProp = propstat.children.whereType<XmlElement>().firstWhere(
        (element) => element.name.local == 'prop',
      );
      break;
    }
    if (successProp == null) return null;

    final remotePath = _remotePathFromHref(href);
    final size = int.tryParse(
      _directChildText(successProp, 'getcontentlength') ?? '',
    );
    final lastModifiedRaw = _directChildText(successProp, 'getlastmodified');
    final lastModified = lastModifiedRaw == null
        ? null
        : _tryParseHttpDate(lastModifiedRaw);
    final resourceType = successProp.children
        .whereType<XmlElement>()
        .firstWhere(
          (element) => element.name.local == 'resourcetype',
          orElse: () => XmlElement(XmlName('resourcetype')),
        );
    final isDirectory = resourceType.children.whereType<XmlElement>().any(
      (element) => element.name.local == 'collection',
    );

    return SaberRemoteFile(
      path: remotePath,
      isDirectory: isDirectory,
      size: size,
      lastModified: lastModified,
    );
  }

  String _remotePathFromHref(String href) {
    final hrefUri = Uri.tryParse(href);
    final decodedPath = Uri.decodeFull(
      (hrefUri?.path.isNotEmpty ?? false) ? hrefUri!.path : href,
    );
    const appRoot = FileManager.appRootDirectoryPrefix;
    final normalizedPath = decodedPath.endsWith('/')
        ? decodedPath.substring(0, decodedPath.length - 1)
        : decodedPath;

    if (normalizedPath == appRoot || normalizedPath.endsWith('/$appRoot')) {
      return '$appRoot/';
    }

    const appRootPrefix = '${FileManager.appRootDirectoryPrefix}/';
    if (normalizedPath.startsWith(appRootPrefix)) {
      return '$appRoot/${normalizedPath.substring(appRootPrefix.length)}';
    }

    const rootSegment = '/${FileManager.appRootDirectoryPrefix}/';
    final rootIndex = normalizedPath.lastIndexOf(rootSegment);
    if (rootIndex >= 0) {
      final suffix = normalizedPath.substring(rootIndex + rootSegment.length);
      return '$appRoot/$suffix';
    }

    throw FormatException('Unexpected WebDAV href: $href');
  }

  static Uri _normalizeBaseUri(Uri uri) {
    final path = uri.path.endsWith('/') ? uri.path : '${uri.path}/';
    return uri.replace(path: path);
  }

  static DateTime? _tryParseHttpDate(String value) {
    try {
      return HttpDate.parse(value);
    } catch (_) {
      return null;
    }
  }

  static String? _directChildText(XmlElement element, String localName) {
    for (final child in element.children.whereType<XmlElement>()) {
      if (child.name.local != localName) continue;
      return child.innerText.trim();
    }
    return null;
  }
}
