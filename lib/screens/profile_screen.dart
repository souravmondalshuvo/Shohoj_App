import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/liquid_glass.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  Future<void> _signOut(BuildContext context) async {
    HapticFeedback.mediumImpact();
    await context.read<AuthService>().signOut();
    if (context.mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().user;
    final isCupertino = isCupertinoPlatform(context);

    if (isCupertino) {
      return Scaffold(
        backgroundColor: AppTheme.bg,
        body: Stack(
          children: [
            const Positioned.fill(child: LiquidBackdrop()),
            SafeArea(
              bottom: false,
              child: CustomScrollView(
                slivers: [
                  CupertinoSliverNavigationBar(
                    largeTitle: const Text('Profile'),
                    backgroundColor: Colors.transparent,
                    border: null,
                    trailing: CupertinoButton(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(36, 36),
                      onPressed: () => Navigator.of(context).maybePop(),
                      child: const Icon(CupertinoIcons.xmark_circle_fill),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 34),
                    sliver: SliverList.list(
                      children: [
                        _ProfileHeader(user: user),
                        const SizedBox(height: 14),
                        _ProfileDetails(user: user),
                        const SizedBox(height: 14),
                        _SignOutButton(onPressed: () => _signOut(context)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _ProfileHeader(user: user),
          const SizedBox(height: 14),
          _ProfileDetails(user: user),
          const SizedBox(height: 14),
          _SignOutButton(onPressed: () => _signOut(context)),
        ],
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  final User? user;

  const _ProfileHeader({required this.user});

  @override
  Widget build(BuildContext context) {
    final name = user?.displayName?.trim();
    final email = user?.email?.trim();
    final initial = (name?.isNotEmpty == true ? name![0] : email?[0] ?? 'S').toUpperCase();

    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          CircleAvatar(
            radius: 34,
            backgroundColor: AppTheme.greenDim,
            backgroundImage: user?.photoURL != null ? NetworkImage(user!.photoURL!) : null,
            child: user?.photoURL == null
                ? Text(
                    initial,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name?.isNotEmpty == true ? name! : 'Shohoj user',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  email?.isNotEmpty == true ? email! : 'No email available',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileDetails extends StatelessWidget {
  final User? user;

  const _ProfileDetails({required this.user});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          _DetailRow(
            icon: Icons.verified_user_outlined,
            label: 'Sign-in provider',
            value: _providerLabel(user),
          ),
          const Divider(height: 1),
          _DetailRow(
            icon: Icons.badge_outlined,
            label: 'User ID',
            value: user?.uid ?? 'Unavailable',
            mono: true,
          ),
        ],
      ),
    );
  }

  String _providerLabel(User? user) {
    final providerId = user?.providerData.isNotEmpty == true
        ? user!.providerData.first.providerId
        : null;
    if (providerId == 'google.com') return 'Google';
    return providerId ?? 'Unavailable';
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool mono;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.mono = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.textSecondary, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
          ),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 13,
                fontFamily: mono ? 'monospace' : null,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SignOutButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _SignOutButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    if (isCupertinoPlatform(context)) {
      return CupertinoButton(
        onPressed: onPressed,
        color: Colors.redAccent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(16),
        padding: const EdgeInsets.symmetric(vertical: 15),
        child: const Text(
          'Sign Out',
          style: TextStyle(
            color: Colors.redAccent,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }

    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.logout_rounded),
      label: const Text('Sign out'),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.redAccent,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14),
      ),
    );
  }
}
