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
import 'package:saber/data/google_drive/google_drive_auth.dart';
import 'package:saber/data/nextcloud/errors.dart';
import 'package:saber/data/nextcloud/nextcloud_client_extension.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/version.dart';
import 'package:xml/xml.dart';

enum SyncBackend { nextcloud, webdav, googleDrive }

class SaberRemoteFile {
  const SaberRemoteFile({
    required this.path,
    required this.isDirectory,
    this.id,
    this.size,
    this.lastModified,
  });

  final String path;
  final bool isDirectory;
  final String? id;
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
    return switch (stows.syncBackend.value) {
      SyncBackend.googleDrive => GoogleDriveSaberSyncClient.withSavedDetails(),
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

class GoogleDriveSaberSyncClient extends SaberSyncClient {
  GoogleDriveSaberSyncClient({
    http.Client? httpClient,
    Future<Map<String, String>> Function()? authHeadersProvider,
    Future<String> Function()? usernameProvider,
    Future<Uint8List?> Function()? avatarProvider,
  }) : httpClient = httpClient ?? http.Client(),
       authHeadersProvider = authHeadersProvider ?? GoogleDriveAuth.authHeaders,
       usernameProvider = usernameProvider ?? GoogleDriveAuth.getUsername,
       avatarProvider = avatarProvider ?? GoogleDriveAuth.getAvatar;

  static const _apiHost = 'www.googleapis.com';
  static const _driveApiPath = '/drive/v3/files';
  static const _uploadApiPath = '/upload/drive/v3/files';
  static const _folderMimeType = 'application/vnd.google-apps.folder';
  static const _folderName = FileManager.appRootDirectoryPrefix;
  static const _lastModifiedProperty = 'saberLastModifiedMs';

  final http.Client httpClient;
  final Future<Map<String, String>> Function() authHeadersProvider;
  final Future<String> Function() usernameProvider;
  final Future<Uint8List?> Function() avatarProvider;

  static GoogleDriveSaberSyncClient? withSavedDetails() {
    if (!stows.hasRemoteLogin) return null;
    return GoogleDriveSaberSyncClient();
  }

  @override
  Encrypter get encrypter => SaberSyncClient.buildEncrypter();

  @override
  Future<void> validateCredentials() async {
    await GoogleDriveAuth.requireAccount();
    await _resolveFolderId(createIfMissing: true);
  }

  @override
  Future<Set<SaberRemoteFile>> findRemoteFiles() async {
    final folderId = await _resolveFolderId(createIfMissing: true);
    final files = await _listFiles(
      "'$folderId' in parents and trashed = false",
    );
    return files.map(_toRemoteFile).toSet();
  }

  @override
  Future<SaberRemoteFile?> getRemoteFile(String remotePath) async {
    final folderId = await _resolveFolderId(createIfMissing: false);
    if (folderId == null) return null;

    final name = _basename(remotePath);
    final files = await _listFiles(
      "name = '${_escapeQueryValue(name)}' and "
      "'$folderId' in parents and trashed = false",
      pageSize: 1,
    );
    if (files.isEmpty) return null;
    return _toRemoteFile(files.first);
  }

  @override
  Future<Uint8List> download(String remotePath) async {
    final remoteFile = await getRemoteFile(remotePath);
    if (remoteFile?.id == null) {
      throw HttpException('Google Drive file not found for $remotePath');
    }

    final response = await _send(
      method: 'GET',
      uri: Uri.https(
        _apiHost,
        '$_driveApiPath/${remoteFile!.id}',
        const {'alt': 'media'},
      ),
      expectedStatusCodes: const {200},
    );
    return response.bodyBytes;
  }

  @override
  Future<void> upload(
    Uint8List bytes,
    String remotePath, {
    DateTime? lastModified,
  }) async {
    final folderId = await _resolveFolderId(createIfMissing: true);
    final existing = await getRemoteFile(remotePath);
    final metadata = <String, Object?>{
      'name': _basename(remotePath),
      'parents': [folderId],
      'appProperties': {
        _lastModifiedProperty:
            (lastModified ?? DateTime.now()).millisecondsSinceEpoch.toString(),
      },
    };

    final boundary = 'saber-${DateTime.now().microsecondsSinceEpoch}';
    final body = _buildMultipartRelatedBody(
      boundary: boundary,
      metadata: metadata,
      bytes: bytes,
    );

    final basePath = existing?.id == null
        ? _uploadApiPath
        : '$_uploadApiPath/${existing!.id}';
    final response = await _send(
      method: existing?.id == null ? 'POST' : 'PATCH',
      uri: Uri.https(
        _apiHost,
        basePath,
        const {'uploadType': 'multipart', 'fields': 'id'},
      ),
      bodyBytes: body,
      headers: {
        HttpHeaders.contentTypeHeader:
            'multipart/related; boundary=$boundary',
      },
      expectedStatusCodes: const {200},
    );

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (folderId != null &&
        decoded is Map<String, dynamic> &&
        decoded['id'] is String) {
      _rememberFolderId(folderId);
    }
  }

  @override
  Future<Map<String, String>> getConfig() async {
    final response = await _downloadOptional(SaberSyncClient.configFileUri.path);
    if (response == null) return {};

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    return (decoded as Map<String, dynamic>).cast<String, String>();
  }

  @override
  Future<void> setConfig(Map<String, String> config) async {
    await upload(
      Uint8List.fromList(utf8.encode(jsonEncode(config))),
      SaberSyncClient.configFileUri.path,
    );
  }

  @override
  Future<String> getUsername() => usernameProvider();

  @override
  Future<Uint8List?> getAvatar() => avatarProvider();

  Future<http.Response?> _downloadOptional(String remotePath) async {
    final remoteFile = await getRemoteFile(remotePath);
    if (remoteFile?.id == null) return null;

    return _send(
      method: 'GET',
      uri: Uri.https(
        _apiHost,
        '$_driveApiPath/${remoteFile!.id}',
        const {'alt': 'media'},
      ),
      expectedStatusCodes: const {200},
    );
  }

  Future<String?> _resolveFolderId({required bool createIfMissing}) async {
    final cached = stows.googleDriveFolderId.value;
    if (cached.isNotEmpty) {
      final file = await _getFileById(cached);
      if (file != null && file['mimeType'] == _folderMimeType) return cached;
    }

    final files = await _listFiles(
      "name = '${_escapeQueryValue(_folderName)}' and "
      "mimeType = '$_folderMimeType' and "
      "'root' in parents and trashed = false",
      pageSize: 1,
    );
    if (files.isNotEmpty) {
      final folderId = files.first['id'] as String;
      _rememberFolderId(folderId);
      return folderId;
    }

    if (!createIfMissing) return null;

    final response = await _send(
      method: 'POST',
      uri: Uri.https(_apiHost, _driveApiPath, const {'fields': 'id'}),
      jsonBody: {
        'name': _folderName,
        'mimeType': _folderMimeType,
        'parents': ['root'],
      },
      expectedStatusCodes: const {200},
    );
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    final folderId = (decoded as Map<String, dynamic>)['id'] as String;
    _rememberFolderId(folderId);
    return folderId;
  }

  Future<List<Map<String, dynamic>>> _listFiles(
    String query, {
    int pageSize = 1000,
  }) async {
    final response = await _send(
      method: 'GET',
      uri: Uri.https(_apiHost, _driveApiPath, {
        'q': query,
        'spaces': 'drive',
        'pageSize': '$pageSize',
        'fields':
            'files(id,name,mimeType,size,modifiedTime,appProperties,trashed)',
      }),
      expectedStatusCodes: const {200},
    );

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    final files = (decoded as Map<String, dynamic>)['files'] as List<dynamic>;
    return files.cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>?> _getFileById(String fileId) async {
    try {
      final response = await _send(
        method: 'GET',
        uri: Uri.https(_apiHost, '$_driveApiPath/$fileId', const {
          'fields': 'id,mimeType',
        }),
        expectedStatusCodes: const {200},
      );
      return jsonDecode(utf8.decode(response.bodyBytes))
          as Map<String, dynamic>;
    } on HttpException {
      return null;
    }
  }

  Future<http.Response> _send({
    required String method,
    required Uri uri,
    Map<String, String>? headers,
    Uint8List? bodyBytes,
    Object? jsonBody,
    Set<int> expectedStatusCodes = const {200},
  }) async {
    final request = http.Request(method, uri);
    request.headers.addAll(await authHeadersProvider());
    request.headers[HttpHeaders.userAgentHeader] = WebDavSaberSyncClient._userAgent;
    if (headers != null) request.headers.addAll(headers);

    if (jsonBody != null) {
      request.headers[HttpHeaders.contentTypeHeader] = 'application/json';
      request.body = jsonEncode(jsonBody);
    } else if (bodyBytes != null) {
      request.bodyBytes = bodyBytes;
    }

    final streamed = await httpClient.send(request);
    final response = await http.Response.fromStream(streamed);
    if (!expectedStatusCodes.contains(response.statusCode)) {
      throw HttpException(
        'Google Drive $method failed (${response.statusCode}) for $uri',
      );
    }
    return response;
  }

  SaberRemoteFile _toRemoteFile(Map<String, dynamic> file) {
    final name = file['name'] as String;
    final appProperties = file['appProperties'] as Map<String, dynamic>?;
    final storedModified = appProperties?[_lastModifiedProperty] as String?;
    final modifiedTime = storedModified == null
        ? DateTime.tryParse(file['modifiedTime'] as String? ?? '')
        : DateTime.fromMillisecondsSinceEpoch(int.parse(storedModified));
    return SaberRemoteFile(
      id: file['id'] as String,
      path: '${FileManager.appRootDirectoryPrefix}/$name',
      isDirectory: file['mimeType'] == _folderMimeType,
      size: int.tryParse(file['size'] as String? ?? ''),
      lastModified: modifiedTime,
    );
  }

  Uint8List _buildMultipartRelatedBody({
    required String boundary,
    required Map<String, Object?> metadata,
    required Uint8List bytes,
  }) {
    final builder = BytesBuilder();
    builder.add(_utf8(
      '--$boundary\r\n'
      'Content-Type: application/json; charset=UTF-8\r\n\r\n'
      '${jsonEncode(metadata)}\r\n'
      '--$boundary\r\n'
      'Content-Type: application/octet-stream\r\n\r\n',
    ));
    builder.add(bytes);
    builder.add(_utf8('\r\n--$boundary--\r\n'));
    return builder.takeBytes();
  }

  static Uint8List _utf8(String value) => Uint8List.fromList(utf8.encode(value));

  static String _basename(String remotePath) =>
      remotePath.substring(remotePath.lastIndexOf('/') + 1);

  static String _escapeQueryValue(String value) => value.replaceAll("'", r"\'");

  void _rememberFolderId(String folderId) {
    stows.googleDriveFolderId.value = folderId;
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
