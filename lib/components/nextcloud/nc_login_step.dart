// 🤖 Generated wholely or partially with GPT-5 Codex; OpenAI
import 'dart:async';
import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:nextcloud/core.dart';
import 'package:nextcloud/nextcloud.dart';
import 'package:regexed_validator/regexed_validator.dart';
import 'package:saber/components/settings/app_info.dart';
import 'package:saber/components/theming/adaptive_circular_progress_indicator.dart';
import 'package:saber/data/google_drive/google_drive_auth.dart';
import 'package:saber/data/nextcloud/login_flow.dart';
import 'package:saber/data/nextcloud/nextcloud_client_extension.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/sync/saber_sync_client.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:saber/pages/user/login.dart';
import 'package:url_launcher/url_launcher.dart';

class NcLoginStep extends StatefulWidget {
  const NcLoginStep({super.key, required this.recheckCurrentStep});

  final void Function() recheckCurrentStep;

  @override
  State<NcLoginStep> createState() => _NcLoginStepState();
}

class _NcLoginStepState extends State<NcLoginStep> {
  static const width = 400.0;

  /// Lighter than the actual Saber color for better contrast
  static const saberColor = Color(0xFFffd642);
  static const onSaberColor = Colors.black;
  static const saberColorDarkened = Color(0xFFc29800);
  static const ncColor = Color(0xFF0082c9);
  static const webDavColor = Color(0xFF33691E);
  static const googleDriveColor = Color(0xFF1A73E8);

  SaberLoginFlow? loginFlow;

  final _serverUrlValid = ValueNotifier(false);
  late final _serverUrlController = TextEditingController();

  final _webDavValid = ValueNotifier(false);
  final _webDavBusy = ValueNotifier(false);
  final _webDavError = ValueNotifier('');
  late final _webDavUrlController = TextEditingController();
  late final _webDavUsernameController = TextEditingController();
  late final _webDavPasswordController = TextEditingController();
  final _googleDriveBusy = ValueNotifier(false);
  final _googleDriveError = ValueNotifier('');

  late SyncBackend _selectedBackend = stows.syncBackend.value;

  @override
  void initState() {
    super.initState();

    _serverUrlController.addListener(() {
      final url = _prependHttpsIfMissing(_serverUrlController.text);
      _serverUrlValid.value = validator.url(url);
    });

    void updateWebDavValid() {
      final url = _prependHttpsIfMissing(_webDavUrlController.text);
      _webDavValid.value =
          validator.url(url) &&
          _webDavUsernameController.text.isNotEmpty &&
          _webDavPasswordController.text.isNotEmpty;
    }

    _webDavUrlController.addListener(updateWebDavValid);
    _webDavUsernameController.addListener(updateWebDavValid);
    _webDavPasswordController.addListener(updateWebDavValid);
  }

  @override
  void dispose() {
    loginFlow?.dispose();
    _serverUrlController.dispose();
    _webDavUrlController.dispose();
    _webDavUsernameController.dispose();
    _webDavPasswordController.dispose();
    _serverUrlValid.dispose();
    _webDavValid.dispose();
    _webDavBusy.dispose();
    _webDavError.dispose();
    _googleDriveBusy.dispose();
    _googleDriveError.dispose();
    super.dispose();
  }

  void startLoginFlow(Uri serverUrl) {
    loginFlow?.dispose();
    loginFlow = SaberLoginFlow.start(serverUrl: serverUrl);

    showAdaptiveDialog(
      context: context,
      builder: (context) => _LoginFlowDialog(loginFlow: loginFlow!),
    );

    loginFlow!.future.then((credentials) async {
      final client = NextcloudClient(
        Uri.parse(credentials.server),
        loginName: credentials.loginName,
        appPassword: credentials.appPassword,
        httpClient: NextcloudClientExtension.newHttpClient(),
      );
      final username = await client.getUsername();

      stows.syncBackend.value = SyncBackend.nextcloud;
      stows.url.value =
          credentials.server ==
              NextcloudClientExtension.defaultNextcloudUri.toString()
          ? ''
          : credentials.server;
      stows.username.value = username;
      stows.ncPassword.value = credentials.appPassword;
      stows.encPassword.value = '';

      stows.pfp.value = null;
      client.core.avatar
          .getAvatar(userId: username, size: AvatarGetAvatarSize.$512)
          .then((response) => response.body)
          .then((pfp) => stows.pfp.value = pfp);

      widget.recheckCurrentStep();
    });
  }

  static String _prependHttpsIfMissing(String url) {
    if (!url.startsWith(RegExp(r'https?://'))) {
      return 'https://$url';
    }
    return url;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final textTheme = TextTheme.of(context);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final screenHeight = MediaQuery.sizeOf(context).height;
    return ListView(
      padding: EdgeInsets.symmetric(
        horizontal: screenWidth > width ? (screenWidth - width) / 2 : 16,
        vertical: 16,
      ),
      children: [
        const SizedBox(height: 16),
        if (screenHeight > 500) ...[
          SvgPicture.asset(
            'assets/images/undraw_cloud_sync_re_02p1.svg',
            width: width,
            height: min(width * 576 / 844.6693, screenHeight * 0.25),
            excludeFromSemantics: true,
          ),
          SizedBox(height: min(64, screenHeight * 0.05)),
        ],
        Text(
          t.login.ncLoginStep.whereToStoreData,
          style: textTheme.headlineSmall,
        ),
        Text.rich(
          t.login.form.agreeToPrivacyPolicy(
            linkToPrivacyPolicy: (text) => TextSpan(
              text: text,
              style: TextStyle(color: colorScheme.primary),
              recognizer: TapGestureRecognizer()
                ..onTap = () {
                  launchUrl(AppInfo.privacyPolicyUrl);
                },
            ),
          ),
        ),
        const SizedBox(height: 32),
        SegmentedButton<SyncBackend>(
          segments: const [
            ButtonSegment(
              value: SyncBackend.googleDrive,
              label: Text('Google Drive'),
            ),
            ButtonSegment(value: SyncBackend.webdav, label: Text('WebDAV')),
            ButtonSegment(
              value: SyncBackend.nextcloud,
              label: Text('Nextcloud'),
            ),
          ],
          selected: {_selectedBackend},
          onSelectionChanged: (selection) {
            setState(() {
              _selectedBackend = selection.first;
              _webDavError.value = '';
              _googleDriveError.value = '';
            });
          },
        ),
        const SizedBox(height: 24),
        ...switch (_selectedBackend) {
          SyncBackend.googleDrive => _buildGoogleDriveLogin(
            context,
            textTheme,
            colorScheme,
          ),
          SyncBackend.webdav => _buildWebDavLogin(
            context,
            textTheme,
            colorScheme,
          ),
          SyncBackend.nextcloud => _buildNextcloudLogin(
            context,
            textTheme,
            colorScheme,
          ),
        },
      ],
    );
  }

  List<Widget> _buildNextcloudLogin(
    BuildContext context,
    TextTheme textTheme,
    ColorScheme colorScheme,
  ) {
    return [
      Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          SvgPicture.asset('assets/icon/icon.svg', width: 32, height: 32),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              t.login.ncLoginStep.saberNcServer,
              style: textTheme.headlineSmall,
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      ElevatedButton(
        onPressed: () =>
            startLoginFlow(NextcloudClientExtension.defaultNextcloudUri),
        style: buttonColorStyle(saberColor, onSaberColor),
        child: Text(t.login.ncLoginStep.loginWithSaber),
      ),
      const SizedBox(height: 4),
      Text.rich(
        t.login.signup(
          linkToSignup: (text) => TextSpan(
            text: text,
            style: TextStyle(
              color: colorScheme.brightness == Brightness.dark
                  ? saberColor
                  : saberColorDarkened,
            ),
            recognizer: TapGestureRecognizer()
              ..onTap = () {
                launchUrl(NcLoginPage.signupUrl);
              },
          ),
        ),
      ),
      const SizedBox(height: 32),
      Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          SvgPicture.asset(
            'assets/images/nextcloud-logo.svg',
            width: 32,
            height: 32,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              t.login.ncLoginStep.otherNcServer,
              style: textTheme.headlineSmall,
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      TextField(
        autocorrect: false,
        autofillHints: const [AutofillHints.url],
        controller: _serverUrlController,
        decoration: InputDecoration(
          labelText: t.login.ncLoginStep.serverUrl,
          hintText: 'https://nc.example.com',
        ),
      ),
      const SizedBox(height: 4),
      ValueListenableBuilder(
        valueListenable: _serverUrlValid,
        builder: (context, valid, child) {
          return ElevatedButton(
            onPressed: valid
                ? () {
                    _serverUrlController.text = _prependHttpsIfMissing(
                      _serverUrlController.text,
                    );
                    startLoginFlow(Uri.parse(_serverUrlController.text));
                  }
                : null,
            style: buttonColorStyle(ncColor),
            child: child,
          );
        },
        child: Text(t.login.ncLoginStep.loginWithNextcloud),
      ),
    ];
  }

  List<Widget> _buildWebDavLogin(
    BuildContext context,
    TextTheme textTheme,
    ColorScheme colorScheme,
  ) {
    return [
      Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          const Icon(Icons.storage_rounded, size: 32),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              'Connect your own WebDAV server',
              style: textTheme.headlineSmall,
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      TextField(
        autocorrect: false,
        autofillHints: const [AutofillHints.url],
        controller: _webDavUrlController,
        decoration: const InputDecoration(
          labelText: 'WebDAV URL',
          hintText: 'https://dav.example.com/remote.php/dav/files/user/',
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        autocorrect: false,
        autofillHints: const [AutofillHints.username],
        controller: _webDavUsernameController,
        decoration: const InputDecoration(labelText: 'Username'),
      ),
      const SizedBox(height: 12),
      TextField(
        autocorrect: false,
        autofillHints: const [AutofillHints.password],
        controller: _webDavPasswordController,
        obscureText: true,
        decoration: const InputDecoration(labelText: 'Password'),
      ),
      const SizedBox(height: 4),
      ValueListenableBuilder(
        valueListenable: _webDavError,
        builder: (context, error, _) {
          if (error.isEmpty) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(error, style: TextStyle(color: colorScheme.error)),
          );
        },
      ),
      const SizedBox(height: 4),
      ValueListenableBuilder(
        valueListenable: _webDavValid,
        builder: (context, valid, child) {
          return ValueListenableBuilder(
            valueListenable: _webDavBusy,
            builder: (context, busy, _) {
              return ElevatedButton(
                onPressed: valid && !busy ? _loginWithWebDav : null,
                style: buttonColorStyle(webDavColor),
                child: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: AdaptiveCircularProgressIndicator(),
                      )
                    : child,
              );
            },
          );
        },
        child: const Text('Continue with WebDAV'),
      ),
    ];
  }

  Future<void> _loginWithWebDav() async {
    _webDavError.value = '';
    _webDavBusy.value = true;

    try {
      final url = _prependHttpsIfMissing(_webDavUrlController.text.trim());
      final username = _webDavUsernameController.text.trim();
      final password = _webDavPasswordController.text;

      final client = WebDavSaberSyncClient(
        baseUri: Uri.parse(url),
        username: username,
        password: password,
      );
      await client.validateCredentials();

      stows.syncBackend.value = SyncBackend.webdav;
      stows.url.value = url;
      stows.username.value = username;
      stows.ncPassword.value = password;
      stows.encPassword.value = '';
      stows.key.value = '';
      stows.iv.value = '';
      stows.pfp.value = null;
      stows.lastStorageQuota.value = null;

      widget.recheckCurrentStep();
    } catch (e) {
      _webDavError.value = 'Failed to connect to WebDAV.\n\n$e';
    } finally {
      _webDavBusy.value = false;
    }
  }

  List<Widget> _buildGoogleDriveLogin(
    BuildContext context,
    TextTheme textTheme,
    ColorScheme colorScheme,
  ) {
    final isConfigured = GoogleDriveAuth.isConfigured;
    final unsupportedMessage = !GoogleDriveAuth.isSupported
        ? 'Google Drive sync is currently supported on Android and macOS.'
        : !isConfigured
        ? 'Google Drive is not configured for this build.\n\n'
              'Build with --dart-define=GOOGLE_DRIVE_CLIENT_ID=...'
        : '';

    return [
      Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          const Icon(Icons.cloud_circle_rounded, size: 32),
          const SizedBox(width: 16),
          Expanded(
            child: Text('Connect Google Drive', style: textTheme.headlineSmall),
          ),
        ],
      ),
      const SizedBox(height: 16),
      const Text(
        'Saber will create a visible "Saber" folder in your Google Drive and '
        'store encrypted sync files there.',
      ),
      if (unsupportedMessage.isNotEmpty) ...[
        const SizedBox(height: 12),
        Text(
          unsupportedMessage,
          style: TextStyle(color: colorScheme.error),
        ),
      ],
      ValueListenableBuilder(
        valueListenable: _googleDriveError,
        builder: (context, error, _) {
          if (error.isEmpty) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(error, style: TextStyle(color: colorScheme.error)),
          );
        },
      ),
      const SizedBox(height: 12),
      ValueListenableBuilder(
        valueListenable: _googleDriveBusy,
        builder: (context, busy, child) {
          return ElevatedButton(
            onPressed: (!isConfigured || busy || !GoogleDriveAuth.isSupported)
                ? null
                : _loginWithGoogleDrive,
            style: buttonColorStyle(googleDriveColor),
            child: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: AdaptiveCircularProgressIndicator(),
                  )
                : child,
          );
        },
        child: const Text('Continue with Google Drive'),
      ),
    ];
  }

  Future<void> _loginWithGoogleDrive() async {
    _googleDriveError.value = '';
    _googleDriveBusy.value = true;

    try {
      final account = await GoogleDriveAuth.signInInteractive();
      final avatar = await GoogleDriveAuth.getAvatar();

      stows.syncBackend.value = SyncBackend.googleDrive;
      stows.url.value = 'https://drive.google.com/drive/my-drive';
      stows.username.value = account.email;
      stows.ncPassword.value = '';
      stows.encPassword.value = '';
      stows.key.value = '';
      stows.iv.value = '';
      stows.pfp.value = avatar;
      stows.lastStorageQuota.value = null;

      widget.recheckCurrentStep();
    } catch (e) {
      _googleDriveError.value = 'Failed to connect to Google Drive.\n\n$e';
    } finally {
      _googleDriveBusy.value = false;
    }
  }

  static ButtonStyle buttonColorStyle(Color primary, [Color? onPrimary]) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: primary,
      primary: primary,
      onPrimary: onPrimary,
    );
    return ElevatedButton.styleFrom(
      backgroundColor: colorScheme.primary,
      foregroundColor: colorScheme.onPrimary,
    );
  }
}

class _LoginFlowDialog extends StatefulWidget {
  const _LoginFlowDialog({required this.loginFlow});

  final SaberLoginFlow loginFlow;

  @override
  State<_LoginFlowDialog> createState() => _LoginFlowDialogState();
}

class _LoginFlowDialogState extends State<_LoginFlowDialog> {
  @override
  void initState() {
    super.initState();
    widget.loginFlow.future.then((_) {
      if (!mounted) return;
      Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog.adaptive(
      title: Text(t.login.ncLoginStep.loginFlow.pleaseAuthorize),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(t.login.ncLoginStep.loginFlow.followPrompts),
          TextButton(
            onPressed: widget.loginFlow.openLoginUrl,
            child: Text(t.login.ncLoginStep.loginFlow.browserDidntOpen),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            widget.loginFlow.dispose();
            Navigator.of(context).pop();
          },
          child: Text(t.common.cancel),
        ),
        _FakeDoneButton(child: Text(t.common.done)),
      ],
    );
  }
}

/// [SaberLoginFlow] polls the login flow and completes automatically.
///
/// The done button isn't needed, but it's added to prevent the user from
/// closing the dialog before the login flow is completed.
///
/// When pressed, the text will be replaced with a spinner for 10 seconds.
class _FakeDoneButton extends StatefulWidget {
  const _FakeDoneButton({required this.child});

  final Widget child;

  @override
  State<_FakeDoneButton> createState() => _FakeDoneButtonState();
}

class _FakeDoneButtonState extends State<_FakeDoneButton> {
  var pressed = false;

  Timer? timer;

  void _onPressed() {
    timer?.cancel();
    timer = Timer(const Duration(seconds: 10), () {
      if (mounted) setState(() => pressed = false);
    });
    if (mounted) setState(() => pressed = true);
  }

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: pressed ? null : _onPressed,
    child: pressed
        ? const SizedBox(
            width: 16,
            height: 16,
            child: AdaptiveCircularProgressIndicator(),
          )
        : widget.child,
  );
}
