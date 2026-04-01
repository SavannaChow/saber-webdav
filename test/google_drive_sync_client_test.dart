// 🤖 Generated wholely or partially with GPT-5 Codex; OpenAI
import 'dart:convert';

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
    stows.googleDriveFolderId.value = '';
  });

  test('Google Drive client lists files from Saber folder', () async {
    final requests = <http.Request>[];
    final client = GoogleDriveSaberSyncClient(
      authHeadersProvider: () async => {'authorization': 'Bearer test-token'},
      usernameProvider: () async => 'alice@example.com',
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.url.queryParameters['q']?.contains("mimeType = 'application/vnd.google-apps.folder'") ??
            false) {
          return http.Response(
            jsonEncode({
              'files': [
                {'id': 'folder-1', 'name': 'Saber', 'mimeType': 'application/vnd.google-apps.folder'},
              ],
            }),
            200,
          );
        }

        return http.Response(
          jsonEncode({
            'files': [
              {
                'id': 'file-1',
                'name': 'abc.sbe',
                'mimeType': 'application/octet-stream',
                'size': '12',
                'modifiedTime': '2026-04-01T10:00:00.000Z',
                'appProperties': {'saberLastModifiedMs': '1775037600000'},
              },
            ],
          }),
          200,
        );
      }),
    );

    final files = await client.findRemoteFiles();

    expect(files, hasLength(1));
    expect(files.single.id, 'file-1');
    expect(files.single.path, 'Saber/abc.sbe');
    expect(files.single.size, 12);
    expect(files.single.lastModified, DateTime.fromMillisecondsSinceEpoch(1775037600000));
    expect(
      requests.every(
        (request) => request.headers['authorization'] == 'Bearer test-token',
      ),
      isTrue,
    );
  });

  test('Google Drive client reads config.sbc from Saber folder', () async {
    final client = GoogleDriveSaberSyncClient(
      authHeadersProvider: () async => {'authorization': 'Bearer test-token'},
      usernameProvider: () async => 'alice@example.com',
      httpClient: MockClient((request) async {
        final query = request.url.queryParameters['q'] ?? '';
        if (query.contains("mimeType = 'application/vnd.google-apps.folder'")) {
          return http.Response(
            jsonEncode({
              'files': [
                {'id': 'folder-1', 'name': 'Saber', 'mimeType': 'application/vnd.google-apps.folder'},
              ],
            }),
            200,
          );
        }
        if (query.contains("name = 'config.sbc'")) {
          return http.Response(
            jsonEncode({
              'files': [
                {'id': 'config-1', 'name': 'config.sbc', 'mimeType': 'application/json'},
              ],
            }),
            200,
          );
        }
        if (request.url.queryParameters['alt'] == 'media') {
          return http.Response(jsonEncode({'key': 'value'}), 200);
        }

        return http.Response(jsonEncode({'files': []}), 200);
      }),
    );

    final config = await client.getConfig();
    expect(config, {'key': 'value'});
  });
}
