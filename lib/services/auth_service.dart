import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'cloud_sync.dart';

/// Thrown with a message that is safe to show to the user.
class AuthException implements Exception {
  const AuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AuthService {
  AuthService._();

  static final AuthService instance = AuthService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  Future<void>? _googleInit;

  User? get currentUser => _auth.currentUser;

  /// True until the learner signs in with email or Google.
  bool get isGuest => currentUser?.isAnonymous ?? true;

  /// Gives this install a Firebase user so progress can be stored before
  /// sign-in: an anonymous one, later linked to the real account.
  /// Fails quietly when offline or when anonymous sign-in is disabled.
  Future<void> ensureUser() async {
    if (_auth.currentUser != null) return;
    try {
      await _auth.signInAnonymously();
    } catch (e) {
      // Offline, or Anonymous sign-in is not enabled in the Firebase console.
      // Tried again the next time progress is saved.
      debugPrint('AuthService: anonymous sign-in failed: $e');
    }
  }

  /// Signs in to an account that already exists. A guest's reading history
  /// moves along with them.
  Future<void> signIn(String email, String password) => _guard(
    () => _switchAccount(
      () => _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      ),
    ),
  );

  /// Creates an account. For a guest this links the email to their current
  /// user, so everything they have done so far stays with it.
  Future<void> register(String name, String email, String password) =>
      _guard(() async {
        final credential = EmailAuthProvider.credential(
          email: email.trim(),
          password: password,
        );
        final guest = _auth.currentUser;
        final result = guest != null && guest.isAnonymous
            ? await guest.linkWithCredential(credential)
            : await _auth.createUserWithEmailAndPassword(
                email: email.trim(),
                password: password,
              );
        await result.user?.updateDisplayName(name.trim());
      });

  Future<void> sendPasswordReset(String email) =>
      _guard(() => _auth.sendPasswordResetEmail(email: email.trim()));

  Future<void> signInWithGoogle() => _guard(() async {
    _googleInit ??= GoogleSignIn.instance.initialize();
    await _googleInit;
    final account = await GoogleSignIn.instance.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw const AuthException('Google sign-in did not return a token.');
    }
    final credential = GoogleAuthProvider.credential(idToken: idToken);
    final guest = _auth.currentUser;
    if (guest != null && guest.isAnonymous) {
      try {
        // Keeps the guest's user, and with it all their progress.
        await guest.linkWithCredential(credential);
        return;
      } on FirebaseAuthException catch (e) {
        // This Google account already has a BiLingo account: switch to it.
        if (e.code != 'credential-already-in-use') rethrow;
        await _switchAccount(
          () => _auth.signInWithCredential(e.credential ?? credential),
        );
        return;
      }
    }
    await _auth.signInWithCredential(credential);
  });

  /// Runs [signIn], which replaces the current user, and carries a guest's
  /// reading history over to the account signed in to.
  Future<void> _switchAccount(Future<Object?> Function() signIn) async {
    final guest = await CloudSync.instance.takeGuestData();
    await signIn();
    if (guest != null) await CloudSync.instance.adoptGuestData(guest);
  }

  /// Signs out and starts a fresh guest user for this install.
  Future<void> signOut() async {
    await _auth.signOut();
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      // Not signed in with Google, or plugin not initialised: nothing to clear.
    }
    await ensureUser();
  }

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } on AuthException {
      rethrow;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw const AuthException('Sign-in cancelled.');
      }
      throw AuthException(
        'Google sign-in failed (${e.code.name}). Check the SHA-1 in Firebase.',
      );
    } on FirebaseAuthException catch (e) {
      throw AuthException(_message(e.code));
    }
  }

  String _message(String code) => switch (code) {
    'invalid-email' => 'That email address looks invalid.',
    'user-not-found' ||
    'wrong-password' ||
    'invalid-credential' => 'Incorrect email or password.',
    'user-disabled' => 'This account has been disabled.',
    'email-already-in-use' => 'An account already exists for that email.',
    'weak-password' => 'Password must be at least 6 characters.',
    'too-many-requests' => 'Too many attempts. Try again later.',
    'credential-already-in-use' ||
    'provider-already-linked' => 'That account is already in use.',
    'requires-recent-login' => 'Please sign in again to continue.',
    'network-request-failed' => 'No internet connection.',
    _ => 'Something went wrong ($code).',
  };
}
