import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService extends ChangeNotifier {
  static const allowedEmailDomain = 'g.bracu.ac.bd';
  static const allowedEmailSuffix = '@$allowedEmailDomain';

  final _auth = FirebaseAuth.instance;
  final _google = GoogleSignIn(scopes: const ['email', 'profile']);
  bool _isSigningIn = false;
  String? _errorMessage;

  User? get user => _auth.currentUser;
  bool get isSignedIn => user != null;
  bool get isSigningIn => _isSigningIn;
  String? get errorMessage => _errorMessage;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  static bool isAllowedEmail(String? email) {
    return email?.trim().toLowerCase().endsWith(allowedEmailSuffix) ?? false;
  }

  bool get _usesFirebaseProviderSignIn {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }

  AuthService() {
    _auth.authStateChanges().listen((_) {
      _isSigningIn = false;
      notifyListeners();
    });
  }

  Future<UserCredential?> signInWithGoogle() async {
    if (_isSigningIn) return null;

    _isSigningIn = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final result = _usesFirebaseProviderSignIn
          ? await _signInWithFirebaseGoogleProvider()
          : await _signInWithGooglePlugin();
      if (result == null) {
        _isSigningIn = false;
        notifyListeners();
        return null;
      }

      if (!isAllowedEmail(result.user?.email)) {
        await signOut();
        throw FirebaseAuthException(
          code: 'unauthorized-email-domain',
          message: 'Use your BRACU Google account ($allowedEmailSuffix).',
        );
      }

      _isSigningIn = false;
      notifyListeners();
      return result;
    } on FirebaseAuthException catch (e) {
      await _safeGoogleSignOut();
      _isSigningIn = false;
      _errorMessage = e.message ?? 'Firebase sign-in failed (${e.code}).';
      notifyListeners();
      rethrow;
    } on PlatformException catch (e) {
      _isSigningIn = false;
      _errorMessage = _platformErrorMessage(e);
      notifyListeners();
      rethrow;
    } catch (e) {
      _isSigningIn = false;
      _errorMessage = 'Google sign-in failed: $e';
      notifyListeners();
      rethrow;
    }
  }

  Future<UserCredential> _signInWithFirebaseGoogleProvider() {
    final provider = GoogleAuthProvider()
      ..addScope('email')
      ..addScope('profile')
      ..setCustomParameters({'hd': allowedEmailDomain});
    return _auth.signInWithProvider(provider);
  }

  Future<UserCredential?> _signInWithGooglePlugin() async {
    final account = await _google.signIn();
    if (account == null) return null;

    if (!isAllowedEmail(account.email)) {
      await _safeGoogleSignOut();
      throw FirebaseAuthException(
        code: 'unauthorized-email-domain',
        message: 'Use your BRACU Google account ($allowedEmailSuffix).',
      );
    }

    final cred = await account.authentication;
    if (cred.accessToken == null && cred.idToken == null) {
      throw FirebaseAuthException(
        code: 'missing-google-token',
        message: 'Google did not return an authentication token.',
      );
    }

    final credential = GoogleAuthProvider.credential(
      accessToken: cred.accessToken,
      idToken: cred.idToken,
    );
    return _auth.signInWithCredential(credential);
  }

  Future<void> _safeGoogleSignOut() async {
    try {
      await _google.signOut();
    } catch (_) {
      // Firebase provider sign-in on Apple platforms does not create a
      // google_sign_in session, so sign-out can legitimately be a no-op.
    }
  }

  Future<void> signOut() async {
    _errorMessage = null;
    await _safeGoogleSignOut();
    await _auth.signOut();
    notifyListeners();
  }

  void clearError() {
    if (_errorMessage == null) return;
    _errorMessage = null;
    notifyListeners();
  }

  String _platformErrorMessage(PlatformException e) {
    if (e.code == GoogleSignIn.kSignInCanceledError) {
      return 'Sign-in was cancelled.';
    }
    final details = e.details?.toString().trim();
    if (details != null && details.isNotEmpty) {
      return 'Google sign-in failed: $details';
    }
    final message = e.message?.trim();
    if (message != null && message.isNotEmpty) {
      return 'Google sign-in failed: $message';
    }
    return 'Google sign-in failed (${e.code}).';
  }
}
