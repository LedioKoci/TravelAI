import 'package:flutter/material.dart';

import '../screens/auth_screen.dart';
import '../services/auth_service.dart';
import '../services/profile_service.dart';

/// Bottom-sheet content for account status: a sign-in prompt when logged out,
/// or the account email, a home-city editor (powers the "Departing from home?"
/// search toggle), and a log-out button when logged in. Opened from the account
/// icon in the search screen's AppBar, and from the toggle itself when there's
/// no home city on file yet.
class AccountSheet extends StatefulWidget {
  const AccountSheet({Key? key}) : super(key: key);

  @override
  State<AccountSheet> createState() => _AccountSheetState();
}

class _AccountSheetState extends State<AccountSheet> {
  bool _isLoading = true;
  bool _isLoggedIn = false;
  String? _email;
  final _homeCityController = TextEditingController();
  bool _isSavingHomeCity = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _homeCityController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final loggedIn = await AuthService.isLoggedIn();
    String? email;
    String? homeCity;

    if (loggedIn) {
      email = await AuthService.email;
      try {
        final profile = await ProfileService.getProfile();
        homeCity = profile['homeCity'] as String?;
      } catch (_) {
        // Non-fatal: the sheet still shows the logged-in state without a home city.
      }
    }

    if (!mounted) return;
    setState(() {
      _isLoggedIn = loggedIn;
      _email = email;
      _homeCityController.text = homeCity ?? '';
      _isLoading = false;
    });
  }

  Future<void> _openAuthScreen() async {
    final success = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const AuthScreen()),
    );
    if (success == true) {
      setState(() => _isLoading = true);
      await _load();
    }
  }

  Future<void> _saveHomeCity() async {
    setState(() => _isSavingHomeCity = true);
    final trimmed = _homeCityController.text.trim();

    try {
      await ProfileService.updateHomeCity(trimmed.isEmpty ? null : trimmed);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Home city updated')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update home city')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingHomeCity = false);
    }
  }

  Future<void> _logout() async {
    await AuthService.logout();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: _isLoading
          ? const SizedBox(
              height: 120,
              child: Center(child: CircularProgressIndicator()),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _isLoggedIn ? _buildLoggedIn() : _buildLoggedOut(),
            ),
    );
  }

  List<Widget> _buildLoggedOut() {
    return [
      Text(
        'Not signed in',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue.shade900),
      ),
      const SizedBox(height: 8),
      Text(
        'Sign in to save travels and sync them across devices.',
        style: TextStyle(color: Colors.grey.shade600),
      ),
      const SizedBox(height: 20),
      ElevatedButton(
        onPressed: _openAuthScreen,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blue.shade600,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: const Text('Sign in / Create account'),
      ),
    ];
  }

  List<Widget> _buildLoggedIn() {
    return [
      Row(
        children: [
          Icon(Icons.account_circle, color: Colors.blue.shade400, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _email ?? 'Signed in',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.blue.shade900),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      const SizedBox(height: 20),
      Text(
        'Home city',
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey.shade700),
      ),
      const SizedBox(height: 4),
      Text(
        'Used by the "Departing from home?" toggle on the search screen.',
        style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: _homeCityController,
              decoration: InputDecoration(
                hintText: 'e.g., Bergamo',
                filled: true,
                fillColor: Colors.blue.shade50,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: _isSavingHomeCity ? null : _saveHomeCity,
            icon: _isSavingHomeCity
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blue.shade600),
                  )
                : Icon(Icons.check_circle, color: Colors.blue.shade600),
          ),
        ],
      ),
      const SizedBox(height: 24),
      TextButton.icon(
        onPressed: _logout,
        icon: Icon(Icons.logout, color: Colors.red.shade400, size: 18),
        label: Text('Log out', style: TextStyle(color: Colors.red.shade400)),
      ),
    ];
  }
}
