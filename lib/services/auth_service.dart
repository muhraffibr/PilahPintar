import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

/// Login operator lewat Firebase Authentication (Email/Password).
///
/// Hanya dipakai pada mode Firebase. Mode simulasi tidak memakai login.
/// Sesi tersimpan otomatis oleh Firebase Auth, jadi operator tidak perlu
/// login ulang setiap membuka aplikasi.
class AuthService {
  AuthService(this._auth, this._db);

  final FirebaseAuth _auth;
  final FirebaseDatabase _db;

  /// `null` = belum login.
  Stream<User?> authStateChanges() => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  String? get email => _auth.currentUser?.email;

  Future<void> signIn(String email, String password) async {
    await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<void> signOut() => _auth.signOut();

  /// `true` bila UID akun ini terdaftar di `/operators/<uid>` (diisi dari
  /// Firebase Console). Hanya operator yang boleh mengirim perintah dan
  /// mengubah pengaturan; akun lain hanya bisa memantau.
  Future<bool> isOperator() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return false;
    try {
      final snap = await _db.ref('operators/$uid').get();
      return snap.value == true;
    } catch (_) {
      return false;
    }
  }

  /// Pesan error login dalam bahasa Indonesia.
  static String describeError(Object error) {
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'invalid-email':
          return 'Format email tidak valid.';
        case 'user-disabled':
          return 'Akun ini dinonaktifkan.';
        case 'user-not-found':
        case 'wrong-password':
        case 'invalid-credential':
          return 'Email atau password salah.';
        case 'too-many-requests':
          return 'Terlalu banyak percobaan. Coba lagi beberapa saat lagi.';
        case 'network-request-failed':
          return 'Tidak ada koneksi internet.';
      }
      return 'Login gagal (${error.code}).';
    }
    return 'Login gagal: $error';
  }
}
