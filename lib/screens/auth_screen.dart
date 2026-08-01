import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../theme/app_theme.dart';

class AuthScreen extends StatelessWidget {
  const AuthScreen({super.key});

  Future<void> _signIn(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final auth = context.read<AuthService>();

    try {
      await auth.signInWithGoogle();
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(auth.errorMessage ?? 'Sign-in failed. Please try again.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              const Spacer(flex: 2),
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: AppTheme.green,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: const Center(
                  child: Text(
                    'স',
                    style: TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.w900,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Shohoj',
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'University life, made simple.',
                style: TextStyle(
                  fontSize: 16,
                  color: AppTheme.textSecondary,
                ),
              ),
              const Spacer(flex: 2),
              const _FeatureRow(
                icon: Icons.calculate_outlined,
                text: 'CGPA Calculator with retake support',
              ),
              const SizedBox(height: 12),
              const _FeatureRow(
                icon: Icons.star_outline,
                text: 'Course & faculty reviews',
              ),
              const SizedBox(height: 12),
              const _FeatureRow(
                icon: Icons.science_outlined,
                text: 'Grade playground & simulator',
              ),
              const SizedBox(height: 12),
              const _FeatureRow(
                icon: Icons.calendar_month_outlined,
                text: 'Semester planner with prereqs',
              ),
              const Spacer(flex: 2),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: auth.isSigningIn ? null : () => _signIn(context),
                  icon: auth.isSigningIn
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black,
                          ),
                        )
                      : const Icon(Icons.login_rounded),
                  label: Text(
                    auth.isSigningIn
                        ? 'Signing in...'
                        : 'Continue with BRACU Google',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.green,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              if (auth.errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  auth.errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                ),
              ],
              const SizedBox(height: 16),
              const Text(
                'Use your user.name@g.bracu.ac.bd account',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _FeatureRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppTheme.green, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }
}
