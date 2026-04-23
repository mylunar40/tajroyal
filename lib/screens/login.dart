import 'dart:ui';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dashboard.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    this.firebaseReady = true,
    this.startupError,
  });

  final bool firebaseReady;
  final String? startupError;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  static const String _savedEmailKey = 'auth_saved_email';
  static const String _savedPasswordKey = 'auth_saved_password';
  static const String _sessionExpiryKey = 'auth_session_expiry_ms';
  static const String _rememberMeKey = 'auth_remember_me';
  static const Duration _sessionDuration = Duration(hours: 24);

  static const Set<String> _allowedEmails = {
    'tajroyal796@gmail.com',
    'user2@tajroyal.com',
    'user3@tajroyal.com',
  };

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _rememberMe = true;

  @override
  void initState() {
    super.initState();
    _restoreSavedLoginFields();
  }

  Future<void> _restoreSavedLoginFields() async {
    final prefs = await SharedPreferences.getInstance();
    final savedEmail = prefs.getString(_savedEmailKey) ?? '';
    final savedPassword = prefs.getString(_savedPasswordKey) ?? '';
    final rememberMe = prefs.getBool(_rememberMeKey) ?? true;

    if (!mounted) return;
    setState(() {
      _rememberMe = rememberMe;
      if (savedEmail.isNotEmpty) {
        _emailController.text = savedEmail;
      }
      if (savedPassword.isNotEmpty) {
        _passwordController.text = savedPassword;
      }
    });
  }

  Future<void> _persistLoginState({
    required String email,
    required String password,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    if (_rememberMe) {
      await prefs.setString(_savedEmailKey, email.trim().toLowerCase());
      await prefs.setString(_savedPasswordKey, password);
      await prefs.setBool(_rememberMeKey, true);
      await prefs.setInt(
        _sessionExpiryKey,
        DateTime.now().add(_sessionDuration).millisecondsSinceEpoch,
      );
      return;
    }

    await prefs.setBool(_rememberMeKey, false);
    await prefs.remove(_savedEmailKey);
    await prefs.remove(_savedPasswordKey);
    await prefs.remove(_sessionExpiryKey);
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  bool _ensureFirebaseReady() {
    if (widget.firebaseReady) {
      return true;
    }

    _showMessage(
      widget.startupError ??
          'Firebase configured nahi hai. Pehle Firebase setup complete karo.',
    );
    return false;
  }

  bool _isAllowedEmail(String? email) {
    if (email == null) return false;
    return _allowedEmails.contains(email.trim().toLowerCase());
  }

  Future<void> _openDashboard() async {
    if (!mounted) return;
    // Load data from Firebase before opening dashboard
    await Future.delayed(const Duration(milliseconds: 200)); // Small delay
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const Dashboard()),
    );
  }

  Future<void> loginUser(String email, String password) async {
    if (!_ensureFirebaseReady()) {
      return;
    }

    final normalizedEmail = email.trim().toLowerCase();

    if (!_isAllowedEmail(normalizedEmail)) {
      _showMessage('Access denied. Sirf 3 authorized users allowed hain.');
      return;
    }

    try {
      if (kIsWeb) {
        await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
      }

      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: normalizedEmail,
        password: password,
      );
      _showMessage('Login Success');
      debugPrint('Login Success');
    } on FirebaseAuthException catch (e) {
      _showMessage(e.message ?? 'Error: login failed');
      debugPrint('Error: ${e.code} ${e.message}');
      rethrow;
    } catch (e) {
      _showMessage('Error: $e');
      debugPrint('Error: $e');
      rethrow;
    }
  }

  Future<void> _signInWithEmailPassword() async {
    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      _showMessage('Email aur password required hai.');
      return;
    }

    if (!_isAllowedEmail(email)) {
      _showMessage('Access denied. Sirf 3 authorized users allowed hain.');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await loginUser(email, password);
      final credential = FirebaseAuth.instance.currentUser;

      if (!_isAllowedEmail(credential?.email)) {
        await FirebaseAuth.instance.signOut();
        _showMessage('Access denied. Authorized list me account nahi hai.');
        return;
      }

      await _persistLoginState(email: email, password: password);

      await _openDashboard();
    } on FirebaseAuthException catch (e) {
      final code = e.code;
      if (code == 'user-not-found') {
        _showMessage('User nahi mila.');
      } else if (code == 'wrong-password' || code == 'invalid-credential') {
        _showMessage('Password galat hai.');
      }
    } catch (_) {
      // Error message is already shown inside login().
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _signInWithGoogle() async {
    if (!_ensureFirebaseReady()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final credential =
          await FirebaseAuth.instance.signInWithProvider(GoogleAuthProvider());
      final signedInEmail = credential.user?.email?.trim().toLowerCase();

      if (!_isAllowedEmail(signedInEmail)) {
        await FirebaseAuth.instance.signOut();
        _showMessage('Access denied. Ye Google account authorized nahi hai.');
        return;
      }

      await _openDashboard();
    } on FirebaseAuthException catch (e) {
      _showMessage(e.message ?? 'Google login failed.');
    } catch (_) {
      _showMessage('Google login failed. Platform/config check karo.');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _sendPasswordReset() async {
    if (!_ensureFirebaseReady()) {
      return;
    }

    final email = _emailController.text.trim().toLowerCase();
    if (email.isEmpty) {
      _showMessage('Forgot password se pehle email likho.');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      _showMessage('Password reset email bhej diya gaya hai.');
    } on FirebaseAuthException catch (e) {
      _showMessage(e.message ?? 'Reset email bhejne me error.');
    } catch (_) {
      _showMessage('Reset email bhejne me error.');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> signUp(String email, String password) async {
    if (!_ensureFirebaseReady()) {
      return;
    }

    final normalizedEmail = email.trim().toLowerCase();

    if (!_isAllowedEmail(normalizedEmail)) {
      _showMessage('Access denied. Sirf 3 authorized users allowed hain.');
      return;
    }

    try {
      await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: normalizedEmail,
        password: password,
      );
      _showMessage('Signup Success');
      debugPrint('Signup Success');
    } on FirebaseAuthException catch (e) {
      _showMessage(e.message ?? 'Error: signup failed');
      debugPrint('Error: ${e.code} ${e.message}');
    } catch (e) {
      _showMessage('Error: $e');
      debugPrint('Error: $e');
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background layer
          Container(
            width: double.infinity,
            height: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF0B1F33),
                  Color(0xFF123B5A),
                  Color(0xFF1E6A73),
                ],
              ),
            ),
          ),
          Container(
            width: double.infinity,
            height: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withOpacity(0.06),
                  Colors.transparent,
                  Colors.black.withOpacity(0.12),
                ],
              ),
            ),
          ),

          // Glass card center
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Container(
                  width: 380,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 32, vertical: 36),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.13),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.35),
                      width: 1.2,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!widget.firebaseReady) ...[
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 18),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFD84315).withOpacity(0.88),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            'Firebase setup incomplete hai. Isliye login abhi disabled hai.\n${widget.startupError ?? ''}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              height: 1.3,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: double.infinity,
                          height: 46,
                          child: ElevatedButton.icon(
                            onPressed: _openDashboard,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1F8A70),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            icon: const Icon(Icons.dashboard_outlined),
                            label: const Text('Open Dashboard Offline'),
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],
                      // Title
                      const Text(
                        'TAJ ROYAL GLASS',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 2,
                          shadows: [
                            Shadow(
                              color: Colors.black45,
                              blurRadius: 6,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),

                      // Email field
                      _buildGlassField(
                        controller: _emailController,
                        hint: 'Email',
                        icon: Icons.email_outlined,
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 14),

                      // Password field
                      _buildGlassField(
                        controller: _passwordController,
                        hint: 'Password',
                        icon: Icons.lock_outline,
                        obscure: _obscurePassword,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            color: Colors.white70,
                            size: 20,
                          ),
                          onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                      const SizedBox(height: 24),

                      Row(
                        children: [
                          Checkbox(
                            value: _rememberMe,
                            onChanged: _isLoading
                                ? null
                                : (value) {
                                    setState(() {
                                      _rememberMe = value ?? true;
                                    });
                                  },
                            activeColor: const Color(0xFF1565C0),
                            checkColor: Colors.white,
                            side: const BorderSide(color: Colors.white70),
                          ),
                          const Expanded(
                            child: Text(
                              'Remember login for 24 hours',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Login button
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1565C0),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 4,
                          ),
                          onPressed: _isLoading || !widget.firebaseReady
                              ? null
                              : _signInWithEmailPassword,
                          child: const Text(
                            'Login',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _isLoading || !widget.firebaseReady
                              ? null
                              : _sendPasswordReset,
                          child: const Text(
                            'Forgot Password?',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: OutlinedButton.icon(
                          onPressed: _isLoading || !widget.firebaseReady
                              ? null
                              : _signInWithGoogle,
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.white70),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: const Icon(Icons.g_mobiledata, size: 28),
                          label: const Text(
                            'Continue with Google',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Allowed users: 3 fixed accounts only',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      if (_isLoading) ...[
                        const SizedBox(height: 14),
                        const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlassField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscure = false,
    TextInputType keyboardType = TextInputType.text,
    Widget? suffixIcon,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.4), width: 1),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        keyboardType: keyboardType,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.white60),
          prefixIcon: Icon(icon, color: Colors.white70, size: 20),
          suffixIcon: suffixIcon,
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }
}
