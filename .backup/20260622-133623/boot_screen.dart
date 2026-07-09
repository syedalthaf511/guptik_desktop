import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/external/docker_service.dart';
import '../../services/external/postgres_service.dart';
import '../dashboard/dashboard_screen.dart';
import 'login_screen.dart';
import '../../services/supabase_service.dart';

class BootScreen extends StatefulWidget {
  const BootScreen({super.key});

  @override
  State<BootScreen> createState() => _BootScreenState();
}

class _BootScreenState extends State<BootScreen> {
  String _statusMessage = "Initializing...";

  @override
  void initState() {
    super.initState();
    _initializeSystem();
  }

  Future<void> _initializeSystem() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final vaultPath = prefs.getString('vault_path');
      final email = prefs.getString('user_email');
      final password = prefs.getString('user_password');

      if (vaultPath == null || email == null || password == null) {
        print("Boot Diagnostics: vaultPath=$vaultPath, email=$email, password=${password != null ? '***' : 'null'}");
        throw Exception("Corrupt session data - please log in again");
      }

      // 1. Check basic Supabase Auth Session
      setState(() => _statusMessage = "Verifying cloud session...");
      final supabaseService = SupabaseService();
      if (supabaseService.currentUserId == null) {
        throw Exception("Cloud session expired. Please log in again.");
      }

      // 2. Re-link Docker Service to the correct path
      setState(() => _statusMessage = "Connecting to local Docker...");
      final dockerService = DockerService();
      dockerService.setVaultPath(vaultPath);

      // 🚀 THE FIX: WAKE UP THE DOCKER CONTAINERS!
      try {
        print("🐳 Starting Docker stack at: $vaultPath");
        await dockerService.startStack();
        print("✅ Docker stack started");
        setState(() => _statusMessage = "Docker stack is ready");
      } catch (e) {
        print("⚠️ Docker startup note: $e");
        setState(() => _statusMessage = "Docker startup: $e");
        // Continue anyway - containers might already be running
      }

      // 3. Re-connect to Postgres (Retries in case Docker is still booting)
      setState(() => _statusMessage = "Connecting to local database...");
      int retries = 0;
      bool connected = false;
      const int maxRetries = 30;
      
      while (retries < maxRetries) {
        try {
          setState(() => _statusMessage = "Database attempt ${retries + 1}/$maxRetries...");
          print("🔄 Database connection attempt ${retries + 1}/$maxRetries...");
          
          await PostgresService().connectExistingUser(
            email: email,
            userPassword: password,
          );
          connected = true;
          print("✅ Connected to local database");
          setState(() => _statusMessage = "Connected to local database");
          break;
        } catch (e) {
          retries++;
          print("⚠️ Connection attempt $retries failed: $e");
          if (retries < maxRetries) {
            await Future.delayed(const Duration(seconds: 2));
          }
        }
      }

      if (!connected) {
        throw Exception("Could not reach local database after $maxRetries attempts. Please ensure Docker is running and healthy.");
      }

      // 4. Go to Dashboard
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const DashboardScreen()),
        );
      }
    } catch (e) {
      print("❌ Boot Error: $e");
      setState(() => _statusMessage = "Boot failed: $e");
      
      // Fallback to Login after a short delay so user can see the error
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'lib/assets/logonobg.png',
              height: 80,
              errorBuilder: (_, _, _) => const Icon(
                Icons.security,
                size: 80,
                color: Colors.cyanAccent,
              ),
            ),
            const SizedBox(height: 30),
            const CircularProgressIndicator(color: Colors.cyanAccent),
            const SizedBox(height: 20),
            const Text(
              "Waking up Guptik Core...",
              style: TextStyle(
                color: Colors.cyanAccent,
                fontFamily: 'Courier',
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                _statusMessage,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey[400],
                  fontFamily: 'Courier',
                  fontSize: 12,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

}
