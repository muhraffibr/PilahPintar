// Konfigurasi Firebase untuk mode DATA_SOURCE=firebase.
//
// Nilai dibaca saat build dari firebase_config.json (salin dari
// firebase_config.example.json, lalu isi dari Firebase Console):
//
//   flutter run --dart-define-from-file=firebase_config.json
//   flutter build apk --dart-define-from-file=firebase_config.json
//
// Alternatif: `flutterfire configure` akan menimpa file ini dengan
// konfigurasi per platform.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

class DefaultFirebaseOptions {
  static const _apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const _appId = String.fromEnvironment('FIREBASE_APP_ID');
  static const _senderId = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
  static const _projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const _databaseUrl = String.fromEnvironment('FIREBASE_DATABASE_URL');
  static const _storageBucket = String.fromEnvironment('FIREBASE_STORAGE_BUCKET');

  static FirebaseOptions get currentPlatform {
    final missing = [
      if (_apiKey.isEmpty) 'FIREBASE_API_KEY',
      if (_appId.isEmpty) 'FIREBASE_APP_ID',
      if (_senderId.isEmpty) 'FIREBASE_MESSAGING_SENDER_ID',
      if (_projectId.isEmpty) 'FIREBASE_PROJECT_ID',
      if (_databaseUrl.isEmpty) 'FIREBASE_DATABASE_URL',
    ];
    if (missing.isNotEmpty) {
      throw UnsupportedError(
        'Konfigurasi Firebase belum lengkap: ${missing.join(', ')}. '
        'Isi firebase_config.json lalu build dengan '
        '--dart-define-from-file=firebase_config.json.',
      );
    }
    return const FirebaseOptions(
      apiKey: _apiKey,
      appId: _appId,
      messagingSenderId: _senderId,
      projectId: _projectId,
      databaseURL: _databaseUrl,
      storageBucket: _storageBucket == '' ? null : _storageBucket,
    );
  }
}
