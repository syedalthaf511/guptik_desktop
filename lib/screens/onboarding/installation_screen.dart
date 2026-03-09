import 'package:flutter/material.dart';
import '../../services/external/docker_service.dart';
import '../dashboard/dashboard_screen.dart';
import '../../services/external/postgres_service.dart';
import 'dart:async';
import '../../services/external/ollama_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class InstallationScreen extends StatefulWidget {
  final String deviceId;
  final String vaultPath;
  final String userEmail;
  final String userPassword;
  final String cfToken;
  final String publicUrl;

  const InstallationScreen({
    super.key,
    required this.deviceId,
    required this.vaultPath,
    required this.userEmail,
    required this.userPassword,
    required this.cfToken,
    required this.publicUrl,
  });

  @override
  State<InstallationScreen> createState() => _InstallationScreenState();
}

class _InstallationScreenState extends State<InstallationScreen> {
  // Services
  final DockerService _dockerService = DockerService();
  final OllamaService _ollamaService = OllamaService();

  // State
  final List<String> _logs = [];
  final ScrollController _scrollController = ScrollController();

  bool _step1Docker = false;
  bool _step2Db = false;
  bool _step3Model = false; // "In Progress"
  bool _modelPulling = false;
  bool _finished = false;

  String? _selectedModel;
  final List<Map<String, String>> _availableModels = [
    {
      'name': 'deepseek-r1:1.5b',
      'label': 'DeepSeek R1 (1.5B)',
      'desc': 'Fast, Efficient, 1.1GB',
    },
    {
      'name': 'llama3.2:1b',
      'label': 'Llama 3.2 (1B)',
      'desc': 'Meta Latest, Balanced, 1.3GB',
    },
    {
      'name': 'qwen2.5:0.5b',
      'label': 'Qwen 2.5 (0.5B)',
      'desc': 'Ultra Lightweight, 500MB',
    },
  ];

  @override
  void initState() {
    super.initState();
    _dockerService.setVaultPath(widget.vaultPath);
    _startInstallation();
  }

  void _addLog(String msg) {
    if (!mounted) return;
    setState(() {
      _logs.add("> $msg");
    });
    // Auto-scroll to bottom
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _startInstallation() async {
    try {
      _addLog("INITIALIZING GUPTIK CORE...");
      _addLog("Target Vault: ${widget.vaultPath}");
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_logged_in', true);
      await prefs.setString('vault_path', widget.vaultPath);
      await prefs.setString('user_email', widget.userEmail);
      await prefs.setString('user_password', widget.userPassword);

      // --- STEP 1: DOCKER ---
      _addLog("Configuring Docker containers...");
      await _dockerService.autoConfigure(
        dbPass: widget.userPassword,
        tunnelToken: widget.cfToken,
        publicUrl: widget.publicUrl,
        email: widget.userEmail,
        userPassword: widget.userPassword,
      );

      _addLog("Starting Docker Stack (This may take a moment)...");
      await _dockerService.startStack();

      setState(() => _step1Docker = true);
      _addLog("✓ Docker Services are Active.");

      // --- STEP 2: DATABASE ---
      _addLog("Initializing Local Postgres User...");
      await PostgresService().initializeUserDatabase(
        email: widget.userEmail,
        userPassword: widget.userPassword,
      );
      setState(() => _step2Db = true);
      _addLog("✓ Database Tables Created.");

      // --- STEP 3: PREPARE FOR AI ---
      _addLog("Waiting for AI Engine (Ollama) to respond...");

      // Poll for Ollama readiness
      int retries = 0;
      while (retries < 20) {
        if (await _ollamaService.isReady()) break;
        await Future.delayed(const Duration(seconds: 2));
        retries++;
      }

      _addLog("✓ AI Engine is Online.");

      // Now we wait for user input (Model Selection)
      setState(() => _step3Model = true);
    } catch (e) {
      _addLog("CRITICAL ERROR: $e");
    }
  }

  Future<void> _pullSelectedModel() async {
    if (_selectedModel == null) return;

    setState(() => _modelPulling = true);
    _addLog("----------------------------------------");
    _addLog("DOWNLOADING MODEL: $_selectedModel");
    _addLog("----------------------------------------");

    try {
      await for (final status in _ollamaService.pullModel(_selectedModel!)) {
        // Only log updates, don't spam if string is same
        if (_logs.isEmpty || _logs.last != "> $status") {
          _addLog(status);
        }
        if (status == "Success") break;
      }

      _addLog("✓ Model Installation Complete.");
      setState(() => _finished = true);
    } catch (e) {
      _addLog("Model Pull Error: $e");
      setState(() => _modelPulling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Slate 900
      body: Row(
        children: [
          // --- LEFT PANEL: STATUS & SELECTION ---
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.all(40),
              decoration: const BoxDecoration(
                border: Border(right: BorderSide(color: Colors.white10)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "SYSTEM SETUP",
                    style: TextStyle(
                      color: Colors.cyanAccent,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 40),

                  _buildStatusItem(
                    "Core Services",
                    "Docker, Cloudflare Tunnel",
                    _step1Docker,
                  ),
                  _buildStatusItem(
                    "Secure Storage",
                    "Postgres, Vault Tables",
                    _step2Db,
                  ),
                  _buildStatusItem(
                    "AI Neural Engine",
                    "Ollama, Vector Logs",
                    _step3Model,
                  ),

                  const Spacer(),

                  // --- MODEL SELECTION UI ---
                  if (_step3Model && !_finished) ...[
                    const Text(
                      "SELECT AI MODEL",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedModel,
                          dropdownColor: const Color(0xFF1E293B),
                          hint: const Text(
                            "Choose a Brain...",
                            style: TextStyle(color: Colors.grey),
                          ),
                          isExpanded: true,
                          style: const TextStyle(color: Colors.white),
                          items: _availableModels.map((m) {
                            return DropdownMenuItem(
                              value: m['name'],
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    m['label']!,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    m['desc']!,
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                          onChanged: _modelPulling
                              ? null
                              : (v) => setState(() => _selectedModel = v),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: (_selectedModel != null && !_modelPulling)
                            ? _pullSelectedModel
                            : null,
                        icon: _modelPulling
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.black,
                                ),
                              )
                            : const Icon(Icons.download, color: Colors.black),
                        label: Text(
                          _modelPulling ? "INSTALLING..." : "INSTALL & FINISH",
                          style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.cyanAccent,
                        ),
                      ),
                    ),
                  ],

                  if (_finished)
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const DashboardScreen(),
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.greenAccent,
                        ),
                        child: const Text(
                          "ENTER DASHBOARD",
                          style: TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // --- RIGHT PANEL: TERMINAL LOGS ---
          Expanded(
            flex: 3,
            child: Container(
              color: const Color(0xFF000000),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.terminal,
                        color: Colors.greenAccent,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        "TERMINAL OUTPUT",
                        style: TextStyle(
                          color: Colors.green[800],
                          fontFamily: 'Courier',
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white10),
                  Expanded(
                    child: ListView.builder(
                      controller: _scrollController,
                      itemCount: _logs.length,
                      itemBuilder: (context, index) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4.0),
                          child: Text(
                            _logs[index],
                            style: const TextStyle(
                              color: Colors.greenAccent,
                              fontFamily: 'Courier',
                              fontSize: 13,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusItem(String title, String subtitle, bool isDone) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24.0),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDone ? Colors.greenAccent : Colors.white10,
              border: Border.all(
                color: isDone ? Colors.greenAccent : Colors.grey,
              ),
            ),
            child: isDone
                ? const Icon(Icons.check, size: 16, color: Colors.black)
                : null,
          ),
          const SizedBox(width: 15),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: isDone ? Colors.white : Colors.grey,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
