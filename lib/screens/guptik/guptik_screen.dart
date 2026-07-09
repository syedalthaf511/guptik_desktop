import 'package:flutter/material.dart';
import 'n8n_webview_screen.dart';
import 'package:uuid/uuid.dart';
import '../../services/external/postgres_service.dart';
import '../../services/external/ollama_service.dart';

class GuptikScreen extends StatefulWidget {
  const GuptikScreen({super.key});

  @override
  State<GuptikScreen> createState() => _GuptikScreenState();
}

class _GuptikScreenState extends State<GuptikScreen> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  // State
  String _sessionId = const Uuid().v4();
  List<Map<String, String>> _messages = []; // Local state for UI
  List<Map<String, dynamic>> _sessions = []; // History sidebar
  String? _currentModel;
  List<String> _availableModels = [];
  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    _loadSessions();
    _loadModels();
  }

  // 🚀 FIX 1: Smarter model loading so it doesn't overwrite your current selection!
  Future<void> _loadModels() async {
    final models = await OllamaService().getLocalModels();
    // Ensure we have absolutely no duplicates to prevent dropdown crashes
    final uniqueModels = models.toSet().toList(); 

    if (mounted) {
      setState(() {
        _availableModels = uniqueModels;
        
        // Only select the first model IF we don't have one selected,
        // or if the one we had selected was deleted.
        if (_currentModel == null || !uniqueModels.contains(_currentModel)) {
          _currentModel = uniqueModels.isNotEmpty ? uniqueModels.first : null;
        }
      });
    }
  }

  Future<void> _loadSessions() async {
    final sessions = await PostgresService().getChatSessions();
    if (mounted) setState(() => _sessions = sessions);
  }

  Future<void> _loadHistory(String sessionId) async {
    final history = await PostgresService().getChatHistory(sessionId);
    setState(() {
      _sessionId = sessionId;
      _messages = history.map((m) => {
        'role': m['role'] as String,
        'content': m['content'] as String
      }).toList();
    });
    _scrollToBottom();
  }

  void _createNewChat() {
    setState(() {
      _sessionId = const Uuid().v4();
      _messages = [];
    });
  }

  Future<void> _sendMessage() async {
    if (_inputController.text.trim().isEmpty || _currentModel == null) return;

    final userText = _inputController.text.trim();
    _inputController.clear();

    // 1. Add User Message to UI & DB
    setState(() {
      _messages.add({'role': 'user', 'content': userText});
      _isGenerating = true;
    });
    _scrollToBottom();

    await PostgresService().saveChatMessage(
      sessionId: _sessionId,
      role: 'user',
      content: userText,
      model: _currentModel!,
    );

    // 2. Prepare for AI Response
    String fullResponse = "";
    setState(() {
      _messages.add({'role': 'assistant', 'content': '...'}); // Placeholder
    });

    // 3. Stream Response
    try {
      final historyForAi = _messages
          .sublist(0, _messages.length - 1) 
          .map((m) => {'role': m['role']!, 'content': m['content']!})
          .toList();

      await for (final chunk in OllamaService().generateChatStream(
        model: _currentModel!,
        history: historyForAi,
      )) {
        fullResponse += chunk;
        setState(() {
          _messages.last['content'] = fullResponse;
        });
        _scrollToBottom();
      }

      // 4. Save AI Response to DB
      await PostgresService().saveChatMessage(
        sessionId: _sessionId,
        role: 'assistant',
        content: fullResponse,
        model: _currentModel!,
      );

      _loadSessions();

    } catch (e) {
      setState(() => _messages.last['content'] = "[Error: $e]");
    } finally {
      setState(() => _isGenerating = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showPullModelDialog() {
    final TextEditingController modelNameController = TextEditingController();
    bool isPulling = false;
    String pullStatus = '';

    showDialog(
      context: context,
      barrierDismissible: false, 
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              title: const Row(
                children: [
                  Icon(Icons.cloud_download, color: Colors.cyanAccent),
                  SizedBox(width: 10),
                  Text("Pull New AI Model", style: TextStyle(color: Colors.white, fontSize: 18)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Enter an Ollama model tag (e.g., 'phi3', 'mistral', 'llama3:8b')", style: TextStyle(color: Colors.grey, fontSize: 13)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: modelNameController,
                    enabled: !isPulling, 
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.black26,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      hintText: "Model name...",
                      hintStyle: TextStyle(color: Colors.grey.shade600),
                    ),
                  ),
                  if (pullStatus.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(pullStatus, style: TextStyle(
                      color: pullStatus.startsWith("Error") ? Colors.redAccent : Colors.cyanAccent, 
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    )),
                    if (isPulling)
                      const Padding(
                        padding: EdgeInsets.only(top: 8.0),
                        child: LinearProgressIndicator(color: Colors.cyanAccent, backgroundColor: Colors.black26),
                      ),
                  ]
                ],
              ),
              actions: [
                if (!isPulling)
                  TextButton(
                    onPressed: () => Navigator.pop(dialogCtx),
                    child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
                  ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.cyanAccent),
                  onPressed: isPulling ? null : () async {
                    final modelName = modelNameController.text.trim().toLowerCase();
                    if (modelName.isEmpty) return;

                    setDialogState(() {
                      isPulling = true;
                      pullStatus = "Connecting to Ollama...";
                    });

                    await for (String status in OllamaService().pullModel(modelName)) {
                      setDialogState(() => pullStatus = status);
                      
                      if (status == "Success") {
                        // Reload the fresh list from Ollama
                        await _loadModels();
                        
                        // 🚀 FIX 2: Safely check if Ollama appended ':latest' to the name you typed!
                        setState(() {
                          if (_availableModels.contains(modelName)) {
                            _currentModel = modelName;
                          } else if (_availableModels.contains('$modelName:latest')) {
                            _currentModel = '$modelName:latest';
                          } else if (_availableModels.isNotEmpty) {
                            _currentModel = _availableModels.first; // Fallback to safe known model
                          }
                        });
                        
                        if (dialogCtx.mounted) {
                          Navigator.pop(dialogCtx);
                        }
                        break;
                      } else if (status.startsWith("Error")) {
                        setDialogState(() => isPulling = false);
                        break;
                      }
                    }
                  },
                  child: Text(isPulling ? "Downloading..." : "Pull Model", style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // --- SIDEBAR (History) ---
        Container(
          width: 250,
          color: const Color(0xFF1E293B),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const N8nWebviewScreen()),
                      );
                    },
                    icon: const Icon(Icons.work, color: Color(0xFF205CE9)),
                    label: const Text(
                      "Automations",
                      style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.cyanAccent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: ElevatedButton.icon(
                  onPressed: _createNewChat,
                  icon: const Icon(Icons.add, color: Colors.black),
                  label: const Text("NEW CHAT", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.cyanAccent,
                    minimumSize: const Size(double.infinity, 45),
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: _sessions.length,
                  itemBuilder: (context, index) {
                    final s = _sessions[index];
                    final isActive = s['id'] == _sessionId;
                    return ListTile(
                      title: Text(s['title'], style: TextStyle(color: isActive ? Colors.white : Colors.grey[400], fontSize: 13)),
                      subtitle: Text(s['date'].toString().split(' ')[0], style: TextStyle(color: Colors.grey[600], fontSize: 10)),
                      selected: isActive,
                      selectedTileColor: Colors.white10,
                      onTap: () => _loadHistory(s['id']),
                    );
                  },
                ),
              ),
            ],
          ),
        ),

        // --- MAIN CHAT AREA ---
        Expanded(
          child: Column(
            children: [
              // Header
              Container(
                height: 60,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.white10)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("GUPTIK NEURAL", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    
                    DropdownButton<String>(
                      value: _currentModel,
                      dropdownColor: const Color(0xFF1E293B),
                      underline: Container(),
                      icon: const Icon(Icons.arrow_drop_down, color: Colors.cyanAccent),
                      style: const TextStyle(color: Colors.cyanAccent, fontFamily: 'Courier'),
                      
                      hint: const Text("Select a Model", style: TextStyle(color: Colors.cyanAccent)),
                      
                      items: [
                        ..._availableModels.map((m) => DropdownMenuItem<String>(
                          value: m, 
                          child: Text(m)
                        )),
                        
                        const DropdownMenuItem<String>(
                          value: '---pull_new---',
                          child: Row(
                            children: [
                              Icon(Icons.download, color: Colors.greenAccent, size: 16),
                              SizedBox(width: 8),
                              Text("Add New Model", style: TextStyle(color: Colors.greenAccent)),
                            ],
                          ),
                        ),
                      ],
                      onChanged: (val) {
                        if (val == '---pull_new---') {
                          _showPullModelDialog();
                        } else {
                          setState(() => _currentModel = val);
                        }
                      },
                    ),
                  ],
                ),
              ),

              // Messages
              Expanded(
                child: _messages.isEmpty 
                  ? Center(child: Text("Start a conversation with local AI", style: TextStyle(color: Colors.grey[700])))
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(20),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final msg = _messages[index];
                        final isUser = msg['role'] == 'user';
                        return Align(
                          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 20),
                            constraints: const BoxConstraints(maxWidth: 700),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: isUser ? Colors.cyanAccent.withOpacity(0.15) : const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: isUser ? Colors.cyanAccent.withOpacity(0.3) : Colors.white10),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(isUser ? Icons.person : Icons.psychology, size: 16, color: isUser ? Colors.cyanAccent : Colors.purpleAccent),
                                    const SizedBox(width: 8),
                                    Text(isUser ? "YOU" : "GUPTIK", style: TextStyle(color: isUser ? Colors.cyanAccent : Colors.purpleAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                SelectableText(
                                  msg['content']!,
                                  style: const TextStyle(height: 1.5, fontSize: 14),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
              ),

              // Input
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _inputController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: "Ask anything...",
                          hintStyle: TextStyle(color: Colors.grey[600]),
                          filled: true,
                          fillColor: const Color(0xFF1E293B),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                        ),
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    FloatingActionButton(
                      onPressed: _isGenerating ? null : _sendMessage,
                      backgroundColor: Colors.cyanAccent,
                      child: _isGenerating 
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                        : const Icon(Icons.send, color: Colors.black),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}