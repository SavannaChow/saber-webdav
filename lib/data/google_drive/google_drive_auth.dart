/// 🤖 Generated wholely or partially with GPT-5 Codex; OpenAI
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/prefs.dart';

class GoogleDriveAuth {
  GoogleDriveAuth._();

  static const driveFileScope = 'https://www.googleapis.com/auth/drive.file';

  static final log = Logger('GoogleDriveAuth');
  static GoogleSignIn? _googleSignIn;

  static bool get isSupported =>
      Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

  static bool get isConfigured {
    if (!isSupported) return false;
    if (!Platform.isMacOS) return true;
    return FlavorConfig.googleDriveClientId.isNotEmpty;
  }

  static Future<void> initialize() async {
    if (_googleSignIn != null) return;

    if (!isSupported) {
      throw UnsupportedError('Google Drive sync is not supported here.');
    }

    if (!isConfigured) {
      throw StateError(
        'Google Drive is not configured. Build with '
        '--dart-define=GOOGLE_DRIVE_CLIENT_ID=...',
      );
    }

    final clientId = FlavorConfig.googleDriveClientId;
    final serverClientId = FlavorConfig.googleDriveServerClientId;
    _googleSignIn = GoogleSignIn(
      scopes: const [driveFileScope],
      clientId: clientId.isEmpty ? null : clientId,
      serverClientId: serverClientId.isEmpty ? null : serverClientId,
    );
  }

  static Future<GoogleSignInAccount?> tryRestoreSession() async {
    await initialize();

    final googleSignIn = _googleSignIn!;
    final restored =
        googleSignIn.currentUser ??
        await googleSignIn.signInSilently(suppressErrors: true);
    if (restored != null) {
      _applyAccount(restored);
    }
    return restored;
  }

  static Future<GoogleSignInAccount> signInInteractive() async {
    await initialize();

    final account = await _googleSignIn!.signIn();
    if (account == null) {
      throw StateError('Google sign-in was cancelled.');
    }

    _applyAccount(account);
    return account;
  }

  static Future<void> signOut() async {
    if (_googleSignIn == null) {
      _clearAccount();
      return;
    }

    await _googleSignIn!.signOut();
    _clearAccount();
  }

  static Future<GoogleSignInAccount> requireAccount() async {
    final account = await tryRestoreSession();
    if (account == null) {
      throw StateError('Google Drive account is not signed in.');
    }
    return account;
  }

  static Future<Map<String, String>> authHeaders() async {
    final account = await requireAccount();
    return account.authHeaders;
  }

  static Future<String> getUsername() async {
    final account = await requireAccount();
    return account.email;
  }

  static Future<Uint8List?> getAvatar() async {
    final account = await requireAccount();
    final photoUrl = account.photoUrl;
    if (photoUrl == null || photoUrl.isEmpty) return null;

    final response = await http.get(Uri.parse(photoUrl));
    if (response.statusCode != HttpStatus.ok) return null;
    return response.bodyBytes;
  }

  static void _applyAccount(GoogleSignInAccount account) {
    stows.username.value = account.email;
  }

  static void _clearAccount() {
    stows.username.value = '';
    stows.googleDriveFolderId.value = '';
  }
}
