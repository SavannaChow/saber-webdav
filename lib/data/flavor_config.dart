/// 🤖 Generated wholely or partially with GPT-5 Codex; OpenAI
class FlavorConfig {
  FlavorConfig._();

  static late String _flavor;
  static String get flavor => _flavor;

  static late String _appStore;
  static String get appStore => _appStore;

  static late bool _shouldCheckForUpdatesByDefault;
  static bool get shouldCheckForUpdatesByDefault =>
      _shouldCheckForUpdatesByDefault;

  static late String _googleDriveClientId;
  static String get googleDriveClientId => _googleDriveClientId;

  static late String _googleDriveServerClientId;
  static String get googleDriveServerClientId => _googleDriveServerClientId;

  static void setup({
    String flavor = '',
    String appStore = '',
    bool shouldCheckForUpdatesByDefault = true,
    String googleDriveClientId = '',
    String googleDriveServerClientId = '',
  }) {
    _flavor = flavor;
    _appStore = appStore;
    _shouldCheckForUpdatesByDefault = shouldCheckForUpdatesByDefault;
    _googleDriveClientId = googleDriveClientId;
    _googleDriveServerClientId = googleDriveServerClientId;
  }

  static void setupFromEnvironment() => setup(
    flavor: const String.fromEnvironment('FLAVOR'),
    appStore: const String.fromEnvironment('APP_STORE'),
    shouldCheckForUpdatesByDefault: const bool.fromEnvironment(
      'UPDATE_CHECK',
      defaultValue: true,
    ),
    googleDriveClientId: const String.fromEnvironment('GOOGLE_DRIVE_CLIENT_ID'),
    googleDriveServerClientId: const String.fromEnvironment(
      'GOOGLE_DRIVE_SERVER_CLIENT_ID',
    ),
  );
}
