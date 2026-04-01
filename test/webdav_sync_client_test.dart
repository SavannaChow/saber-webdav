// 🤖 Generated wholely or partially with GPT-5 Codex; OpenAI
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/sync/saber_sync_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'utils/test_mock_channel_handlers.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    FlavorConfig.setup();
    setupMockFlutterSecureStorage();
    SharedPreferences.setMockInitialValues({});
    stows.encPassword.value = 'shared-password';
    stows.key.value = '';
    stows.iv.value = '';
  });

  test('WebDAV client lists files from PROPFIND response', () async {
    late http.Request capturedRequest;
    final client = WebDavSaberSyncClient(
      baseUri: Uri.parse('https://dav.example.com/storage'),
      username: 'alice',
      password: 'secret',
      httpClient: MockClient((request) async {
        capturedRequest = request;
        return http.Response('''
<?xml version="1.0"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/storage/Saber/</d:href>
    <d:propstat>
      <d:prop>
        <d:resourcetype><d:collection /></d:resourcetype>
      </d:prop>
      <d:status>HTTP/1.1 200 OK</d:status>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/storage/Saber/abc.sbe</d:href>
    <d:propstat>
      <d:prop>
        <d:getcontentlength>12</d:getcontentlength>
        <d:getlastmodified>Wed, 31 Mar 2026 10:00:00 GMT</d:getlastmodified>
        <d:resourcetype />
      </d:prop>
      <d:status>HTTP/1.1 200 OK</d:status>
    </d:propstat>
  </d:response>
</d:multistatus>
''', 207);
      }),
    );

    final files = await client.findRemoteFiles();

    expect(capturedRequest.method, 'PROPFIND');
    expect(
      capturedRequest.url.toString(),
      'https://dav.example.com/storage/Saber',
    );
    expect(capturedRequest.headers['authorization'], startsWith('Basic '));
    expect(files, hasLength(1));

    final file = files.single;
    expect(file.path, 'Saber/abc.sbe');
    expect(file.size, 12);
    expect(file.isDirectory, isFalse);
    expect(file.lastModified, DateTime.utc(2026, 3, 31, 10));
  });

  test('WebDAV client accepts hrefs outside the configured base path', () async {
    final client = WebDavSaberSyncClient(
      baseUri: Uri.parse('https://dav.example.com/webdav/notes/'),
      username: 'alice',
      password: 'secret',
      httpClient: MockClient((_) async {
        return http.Response('''
<?xml version="1.0"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/dav/files/alice/Saber/</d:href>
    <d:propstat>
      <d:prop>
        <d:resourcetype><d:collection /></d:resourcetype>
      </d:prop>
      <d:status>HTTP/1.1 200 OK</d:status>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/files/alice/Saber/abc.sbe</d:href>
    <d:propstat>
      <d:prop>
        <d:getcontentlength>12</d:getcontentlength>
        <d:resourcetype />
      </d:prop>
      <d:status>HTTP/1.1 200 OK</d:status>
    </d:propstat>
  </d:response>
</d:multistatus>
''', 207);
      }),
    );

    final files = await client.findRemoteFiles();

    expect(files, hasLength(1));
    expect(files.single.path, 'Saber/abc.sbe');
  });

  test('WebDAV config returns empty map on 404', () async {
    final client = WebDavSaberSyncClient(
      baseUri: Uri.parse('https://dav.example.com/storage/'),
      username: 'alice',
      password: 'secret',
      httpClient: MockClient((_) async => http.Response('', 404)),
    );

    expect(await client.getConfig(), isEmpty);
  });

  test(
    'WebDAV client does not generate a new encryption key when remote files exist',
    () async {
      final client = WebDavSaberSyncClient(
        baseUri: Uri.parse('https://dav.example.com/storage/'),
        username: 'alice',
        password: 'secret',
        httpClient: MockClient((request) async {
          if (request.method == 'GET' &&
              request.url.path.endsWith('/Saber/config.sbc')) {
            return http.Response('', 404);
          }

          if (request.method == 'PROPFIND') {
            return http.Response('''
<?xml version="1.0"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/storage/Saber/</d:href>
    <d:propstat>
      <d:prop>
        <d:resourcetype><d:collection /></d:resourcetype>
      </d:prop>
      <d:status>HTTP/1.1 200 OK</d:status>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/storage/Saber/existing-note.sbe</d:href>
    <d:propstat>
      <d:prop>
        <d:getcontentlength>12</d:getcontentlength>
        <d:resourcetype />
      </d:prop>
      <d:status>HTTP/1.1 200 OK</d:status>
    </d:propstat>
  </d:response>
</d:multistatus>
''', 207);
          }

          if (request.method == 'PUT') {
            fail('Should not upload a new config when remote files already exist');
          }

          return http.Response('', 500);
        }),
      );

      await expectLater(client.loadEncryptionKey(), throwsA(isA<Exception>()));
      expect(stows.key.value, isEmpty);
      expect(stows.iv.value, isEmpty);
    },
  );
}
