import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService extends ChangeNotifier {
  final _auth = FirebaseAuth.instance;
  final _google = GoogleSignIn();

  User? get user => _auth.currentUser;
  bool get isSignedIn => user != null;

  AuthService() {
    _auth.authStateChanges().listen((_) => notifyListeners());
  }

  Future<void> signInWithGoogle() async {
    final account = await _google.signIn();
    if (account == null) return;
    final cred = await account.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: cred.accessToken,
      idToken: cred.idToken,
    );
    await _auth.signInWithCredential(credential);
  }

  Future<void> signOut() async {
    await _google.signOut();
    await _auth.signOut();
  }
}
