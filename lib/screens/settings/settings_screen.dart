import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/external/docker_service.dart';
import '../auth/login_signup_screen.dart'; // Ensure this points to your new LoginScreen

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isKilling = false;

  Future<void> _activateKillSwitch() async {
    // Confirm before killing
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
            SizedBox(width: 10),
            Text("EMERGENCY KILL", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text(
          "This will immediately shut down all local AI, Database, and Tunnel containers, terminating the session. Proceed?",
          style: TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("CANCEL", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text("SHUT DOWN", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isKilling = true);

    try {
      // 1. Stop all Docker Containers
      await DockerService().stopStack();

      // 2. Clear Session Info
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      // 3. Sign out of Supabase
      await Supabase.instance.client.auth.signOut();

      // 4. Return to Login
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
MaterialPageRoute(builder: (_) => const LoginSignupScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
        setState(() => _isKilling = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(40.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("SYSTEM SETTINGS", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 2)),
          const SizedBox(height: 40),

          // Regular Settings Panel
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white10),
            ),
            child: const Column(
              children: [
                ListTile(
                  leading: Icon(Icons.person, color: Colors.cyanAccent),
                  title: Text("Account Details"),
                  subtitle: Text("Manage your connected user profile"),
                  trailing: Icon(Icons.chevron_right, color: Colors.grey),
                ),
                Divider(color: Colors.white10),
                ListTile(
                  leading: Icon(Icons.data_usage, color: Colors.cyanAccent),
                  title: Text("Storage Location"),
                  subtitle: Text("View current vault and database path"),
                  trailing: Icon(Icons.chevron_right, color: Colors.grey),
                ),
              ],
            ),
          ),

          const Spacer(),

          // KILL SWITCH PANEL
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.red.withOpacity(0.3), width: 2),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.red.withOpacity(0.2), shape: BoxShape.circle),
                  child: const Icon(Icons.power_settings_new, color: Colors.redAccent, size: 32),
                ),
                const SizedBox(width: 20),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("SYSTEM KILL SWITCH", style: TextStyle(color: Colors.redAccent, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1)),
                      SizedBox(height: 4),
                      Text("Instantly shuts down all background services, destroys the tunnel connection, and logs you out.", 
                        style: TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                ),
                SizedBox(
                  width: 150,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isKilling ? null : _activateKillSwitch,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                    child: _isKilling
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text("ACTIVATE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1)),
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