import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class NodeDashboardScreen extends StatefulWidget {
  final String? nodeUrl;
  
  const NodeDashboardScreen({
    super.key, 
    this.nodeUrl,
  });

  @override
  State<NodeDashboardScreen> createState() => _NodeDashboardScreenState();
}

class _NodeDashboardScreenState extends State<NodeDashboardScreen> {
  final _secureStorage = const FlutterSecureStorage();
  String _displayUrl = "Loading...";

  @override
  void initState() {
    super.initState();
    _loadRealNodeUrl();
  }

  // Fetch the real saved public URL from Secure Storage
  Future<void> _loadRealNodeUrl() async {
    // 1. If a valid, non-placeholder URL was passed from parent, use it
    if (widget.nodeUrl != null && 
        widget.nodeUrl!.isNotEmpty && 
        widget.nodeUrl != "https://my-local-node.net") {
      if (mounted) {
        setState(() => _displayUrl = widget.nodeUrl!);
      }
      return;
    }

    // 2. Otherwise read 'public_url' saved during node initialization
    try {
      String? savedUrl = await _secureStorage.read(key: 'public_url');

      if (savedUrl == null || savedUrl.isEmpty) {
        final actualGuptikId = await _secureStorage.read(key: 'current_user_id') ?? 'unknown_id';
        savedUrl = 'https://$actualGuptikId-guptik.myqrmart.com';
      } else if (!savedUrl.startsWith('http')) {
        savedUrl = 'https://$savedUrl';
      }

      if (mounted) {
        setState(() {
          _displayUrl = savedUrl!;
        });
      }
    } catch (e) {
      debugPrint("Error loading node URL: $e");
      if (mounted) {
        setState(() => _displayUrl = "URL_NOT_FOUND");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Node Dashboard",
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            "Manage your local P2P gateway and cryptographic identity.",
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 32),

          // Gateway Status Card
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.router, color: Colors.cyanAccent),
                    SizedBox(width: 12),
                    Text(
                      "Gateway Network Status",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _buildStatusRow("Docker Gateway container", true),
                _buildStatusRow("PostgreSQL Database", true),
                _buildStatusRow("Cloudflare Tunnel", true),
                const Divider(color: Colors.white12, height: 32),
                const Text(
                  "Permanent Node Address:",
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    SelectableText(
                      _displayUrl, // Displays the real fetched URL
                      style: const TextStyle(
                        color: Colors.cyanAccent,
                        fontFamily: 'monospace',
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(width: 16),
                    IconButton(
                      icon: const Icon(
                        Icons.copy,
                        color: Colors.grey,
                        size: 18,
                      ),
                      tooltip: "Copy URL",
                      onPressed: () async {
                        final scaffoldMessenger = ScaffoldMessenger.of(context);
                        await Clipboard.setData(
                          ClipboardData(text: _displayUrl),
                        );
                        if (!mounted) return;
                        scaffoldMessenger.showSnackBar(
                          const SnackBar(
                            content: Text("Node Address copied!"),
                            backgroundColor: Colors.green,
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Cryptographic Identity Card
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.security, color: Colors.greenAccent),
                    SizedBox(width: 12),
                    Text(
                      "Cryptographic Identity",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 24),
                Text(
                  "Ed25519 Identity Key: GENERATED",
                  style: TextStyle(color: Colors.grey, fontFamily: 'monospace'),
                ),
                SizedBox(height: 8),
                Text(
                  "X25519 Signed Pre-Key: ACTIVE (Rotates in 29 days)",
                  style: TextStyle(color: Colors.grey, fontFamily: 'monospace'),
                ),
                SizedBox(height: 8),
                Text(
                  "One-Time Pre-Keys Remaining: 100/100",
                  style: TextStyle(color: Colors.grey, fontFamily: 'monospace'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusRow(String label, bool isOnline) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: isOnline ? Colors.greenAccent : Colors.redAccent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(color: Colors.white70)),
          const Spacer(),
          Text(
            isOnline ? "ONLINE" : "OFFLINE",
            style: TextStyle(
              color: isOnline ? Colors.greenAccent : Colors.redAccent,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}