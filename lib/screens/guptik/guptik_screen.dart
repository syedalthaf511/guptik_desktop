import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'n8n_webview_screen.dart';
import 'package:uuid/uuid.dart';
import '../../services/external/postgres_service.dart';

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
  List<Map<String, String>> _messages = [];
  List<Map<String, dynamic>> _sessions = [];
  bool _isGenerating = false;

  // 🚀 Cline-Style Multi-Provider Configuration State
  String _aiProvider = "OpenRouter"; 
  String _aiEndpointUrl = "https://openrouter.ai/api/v1/chat/completions";
  String _aiApiKey = "";
  String _aiModelName = "meta-llama/llama-3-8b-instruct";
  
  List<Map<String, String>> _cachedModels = [];
  bool _isFetchingModels = false;

  @override
  void initState() {
    super.initState();
    _loadSessions();
    _loadAiSettings(); 
  }

  // 🚀 LOAD & SYNC AI SETTINGS ON DESKTOP LAUNCH
  Future<void> _loadAiSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final p = prefs.getString('ai_provider') ?? "OpenRouter";
    final u = prefs.getString('ai_endpoint_url') ?? "https://openrouter.ai/api/v1/chat/completions";
    final k = prefs.getString('ai_api_key') ?? "";
    final m = prefs.getString('ai_model_name') ?? "meta-llama/llama-3-8b-instruct";

    setState(() {
      _aiProvider = p;
      _aiEndpointUrl = u;
      _aiApiKey = k;
      _aiModelName = m;
    });

    // 🚀 Auto-push to Gateway Server (Port 55000) on startup
    _pushConfigToGateway(p, u, k, m);
  }

  // 🚀 SAVE SETTINGS LOCALLY & PUSH TO GATEWAY
  Future<void> _saveAiSettings(String provider, String url, String key, String model) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ai_provider', provider);
    await prefs.setString('ai_endpoint_url', url);
    await prefs.setString('ai_api_key', key);
    await prefs.setString('ai_model_name', model);

    setState(() {
      _aiProvider = provider;
      _aiEndpointUrl = url;
      _aiApiKey = key;
      _aiModelName = model;
    });

    await _pushConfigToGateway(provider, url, key, model);
  }

  // 🚀 HELPER: PUSH CONFIG TO GATEWAY (PORT 55000)
  Future<void> _pushConfigToGateway(String provider, String url, String key, String model) async {
    try {
      await http.post(
        Uri.parse("http://localhost:55000/api/ai-config"), // FIXED: Port updated to 55000
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'provider': provider,
          'endpoint_url': url,
          'api_key': key,
          'model_name': model,
        }),
      );
    } catch (e) {
      debugPrint("Gateway sync warning: $e");
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

  // 🚀 Universal AI Calling Logic supporting provider-specific headers
  Future<void> _sendMessage() async {
    if (_inputController.text.trim().isEmpty) return;

    final userText = _inputController.text.trim();
    _inputController.clear();

    setState(() {
      _messages.add({'role': 'user', 'content': userText});
      _isGenerating = true;
    });
    _scrollToBottom();

    await PostgresService().saveChatMessage(
      sessionId: _sessionId, role: 'user', content: userText, model: _aiModelName,
    );

    setState(() {
      _messages.add({'role': 'assistant', 'content': 'Waiting for AI response...'});
    });

    try {
      final historyForAi = _messages
          .sublist(0, _messages.length - 1) 
          .map((m) => {'role': m['role']!, 'content': m['content']!})
          .toList();

      final requestBody = jsonEncode({
        "model": _aiModelName,
        "messages": historyForAi,
        "stream": false 
      });

      String safeUrl = _aiEndpointUrl.trim();
      if (safeUrl.startsWith("http://") && (safeUrl.contains("openrouter") || safeUrl.contains("openai"))) {
        safeUrl = safeUrl.replaceFirst("http://", "https://");
      }

      String safeKey = _aiApiKey.replaceAll('\n', '').replaceAll('\r', '').replaceAll(' ', '').trim();
      if (safeKey.toLowerCase().startsWith('bearer')) {
        safeKey = safeKey.substring(6).trim();
      }

      final Map<String, String> headers = {
        "Content-Type": "application/json",
      };

      if (_aiProvider == "OpenRouter") {
        headers["HTTP-Referer"] = "https://guptik.com";
        headers["X-Title"] = "Guptik Desktop";
      }

      if (safeKey.isNotEmpty) {
        if (_aiProvider == "Anthropic") {
          headers["x-api-key"] = safeKey;
          headers["anthropic-version"] = "2023-06-01";
        } else {
          headers["Authorization"] = "Bearer $safeKey";
        }
      }

      final response = await http.post(
        Uri.parse(safeUrl),
        headers: headers,
        body: requestBody,
      );

      String aiResponseText = "";

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['choices'] != null && data['choices'].isNotEmpty) {
          aiResponseText = data['choices'][0]['message']['content'];
        } else if (data['content'] != null && data['content'] is List) {
          aiResponseText = data['content'][0]['text'] ?? "";
        } else if (data['message'] != null && data['message']['content'] != null) {
          aiResponseText = data['message']['content'];
        } else {
          aiResponseText = "Response format not recognized.";
        }
      } else {
        aiResponseText = "[API Error: ${response.statusCode}] - ${response.body}";
      }

      setState(() {
        _messages.last['content'] = aiResponseText;
      });
      _scrollToBottom();

      await PostgresService().saveChatMessage(
        sessionId: _sessionId, role: 'assistant', content: aiResponseText, model: _aiModelName,
      );
      _loadSessions();

    } catch (e) {
      setState(() => _messages.last['content'] = "[Network Error: Check your AI Settings URL]\n$e");
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

  void _showAiSettingsDialog() {
    String tempProvider = _aiProvider;
    String tempUrl = _aiEndpointUrl;
    String tempKey = _aiApiKey;
    String tempModel = _aiModelName;
    String fetchStatus = "";

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {

          void onProviderChanged(String? newProvider) {
            if (newProvider == null) return;
            setDialogState(() {
              tempProvider = newProvider;
              _cachedModels = [];
              switch (newProvider) {
                case "OpenAI":
                  tempUrl = "https://api.openai.com/v1/chat/completions";
                  tempModel = "gpt-4o";
                  break;
                case "OpenRouter":
                  tempUrl = "https://openrouter.ai/api/v1/chat/completions";
                  tempModel = "meta-llama/llama-3-8b-instruct";
                  break;
                case "Anthropic":
                  tempUrl = "https://api.anthropic.com/v1/messages";
                  tempModel = "claude-3-5-sonnet-20241022";
                  break;
                case "Gemini":
                  tempUrl = "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions";
                  tempModel = "gemini-1.5-flash";
                  break;
                case "DeepSeek":
                  tempUrl = "https://api.deepseek.com/chat/completions";
                  tempModel = "deepseek-chat";
                  break;
                case "Ollama":
                  tempUrl = "http://localhost:11434/api/chat";
                  tempModel = "llama3";
                  break;
                case "LM Studio":
                  tempUrl = "http://localhost:1234/v1/chat/completions";
                  tempModel = "local-model";
                  break;
                case "Hugging Face":
                  tempUrl = "https://api-inference.huggingface.co/v1/chat/completions";
                  tempModel = "mistralai/Mistral-7B-Instruct-v0.2";
                  break;
              }
            });
          }

          Future<void> fetchModels() async {
            if (tempProvider == "OpenRouter") {
              if (tempKey.isEmpty) {
                setDialogState(() => fetchStatus = "Please enter an API Key first.");
                return;
              }
              setDialogState(() {
                _isFetchingModels = true;
                fetchStatus = "Fetching OpenRouter models...";
              });

              try {
                final res = await http.get(
                  Uri.parse("https://openrouter.ai/api/v1/models"),
                  headers: {"Authorization": "Bearer ${tempKey.trim()}"},
                );

                if (res.statusCode == 200) {
                  final data = jsonDecode(res.body);
                  final List<dynamic> modelsList = data['data'];
                  List<Map<String, String>> parsed = [];
                  for (var m in modelsList) {
                    parsed.add({
                      "id": m["id"].toString(),
                      "name": m["name"].toString()
                    });
                  }
                  parsed.sort((a, b) => a["name"]!.toLowerCase().compareTo(b["name"]!.toLowerCase()));
                  
                  setDialogState(() {
                    _cachedModels = parsed;
                    _isFetchingModels = false;
                    fetchStatus = "Loaded ${parsed.length} models successfully!";
                    if (!_cachedModels.any((m) => m['id'] == tempModel) && parsed.isNotEmpty) {
                      tempModel = parsed.first['id']!;
                    }
                  });
                } else {
                  setDialogState(() {
                    _isFetchingModels = false;
                    fetchStatus = "Error: ${res.statusCode} (Invalid Key?)";
                  });
                }
              } catch (_) {
                setDialogState(() {
                  _isFetchingModels = false;
                  fetchStatus = "Connection error while fetching models.";
                });
              }
            }
          }

          return AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            title: const Text("Cline-Style AI Provider Settings", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            content: SizedBox(
              width: 500,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("API Provider", style: TextStyle(color: Colors.grey, fontSize: 12)),
                    const SizedBox(height: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8)),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: tempProvider,
                          isExpanded: true,
                          dropdownColor: const Color(0xFF0F172A),
                          style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold),
                          items: const [
                            DropdownMenuItem(value: "OpenAI", child: Text("OpenAI")),
                            DropdownMenuItem(value: "OpenRouter", child: Text("OpenRouter")),
                            DropdownMenuItem(value: "Anthropic", child: Text("Anthropic (Claude)")),
                            DropdownMenuItem(value: "Gemini", child: Text("Google Gemini")),
                            DropdownMenuItem(value: "DeepSeek", child: Text("DeepSeek")),
                            DropdownMenuItem(value: "Ollama", child: Text("Ollama (Local)")),
                            DropdownMenuItem(value: "LM Studio", child: Text("LM Studio (Local)")),
                            DropdownMenuItem(value: "Hugging Face", child: Text("Hugging Face")),
                          ],
                          onChanged: onProviderChanged,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    const Text("API Key", style: TextStyle(color: Colors.grey, fontSize: 12)),
                    const SizedBox(height: 5),
                    TextField(
                      controller: TextEditingController(text: tempKey)..selection = TextSelection.collapsed(offset: tempKey.length),
                      onChanged: (val) => tempKey = val,
                      obscureText: true,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: tempProvider.contains("Local") || tempProvider == "Ollama" ? "Not required" : "Enter API key...",
                        hintStyle: const TextStyle(color: Colors.white24),
                        filled: true,
                        fillColor: Colors.black26,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 20),

                    const Text("API Base URL", style: TextStyle(color: Colors.grey, fontSize: 12)),
                    const SizedBox(height: 5),
                    TextField(
                      controller: TextEditingController(text: tempUrl)..selection = TextSelection.collapsed(offset: tempUrl.length),
                      onChanged: (val) => tempUrl = val,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.black26,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 20),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Model Selection", style: TextStyle(color: Colors.grey, fontSize: 12)),
                        if (tempProvider == "OpenRouter")
                          TextButton.icon(
                            onPressed: _isFetchingModels ? null : fetchModels,
                            icon: _isFetchingModels 
                              ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(color: Colors.cyanAccent, strokeWidth: 2))
                              : const Icon(Icons.cloud_download, color: Colors.cyanAccent, size: 16),
                            label: const Text("Fetch Models", style: TextStyle(color: Colors.cyanAccent, fontSize: 12)),
                          )
                      ],
                    ),
                    const SizedBox(height: 5),
                    
                    if (tempProvider == "OpenRouter" && _cachedModels.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8)),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _cachedModels.any((m) => m['id'] == tempModel) ? tempModel : null,
                            isExpanded: true,
                            menuMaxHeight: 400,
                            dropdownColor: const Color(0xFF0F172A),
                            hint: Text(tempModel.isEmpty ? "Select model..." : tempModel, style: const TextStyle(color: Colors.white70)),
                            items: _cachedModels.map((m) {
                              return DropdownMenuItem<String>(
                                value: m['id'],
                                child: Text("${m['name']} (${m['id']})", style: const TextStyle(color: Colors.cyanAccent, fontSize: 13), overflow: TextOverflow.ellipsis),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) setDialogState(() => tempModel = val);
                            },
                          ),
                        ),
                      )
                    else
                      TextField(
                        controller: TextEditingController(text: tempModel)..selection = TextSelection.collapsed(offset: tempModel.length),
                        onChanged: (val) => tempModel = val,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: "Enter model ID (e.g. gpt-4o, claude-3-5-sonnet)",
                          hintStyle: const TextStyle(color: Colors.white24),
                          filled: true,
                          fillColor: Colors.black26,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                        ),
                      ),

                    if (fetchStatus.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(fetchStatus, style: TextStyle(color: fetchStatus.contains("Error") ? Colors.redAccent : Colors.greenAccent, fontSize: 12)),
                      )
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel", style: TextStyle(color: Colors.grey))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.cyanAccent),
                onPressed: () {
                  _saveAiSettings(tempProvider, tempUrl, tempKey, tempModel);
                  Navigator.pop(ctx);
                },
                child: const Text("Save Configuration", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        }
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
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
                      Navigator.push(context, MaterialPageRoute(builder: (context) => const N8nWebviewScreen()));
                    },
                    icon: const Icon(Icons.work, color: Color(0xFF205CE9)),
                    label: const Text("Automations", style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.cyanAccent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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

        Expanded(
          child: Column(
            children: [
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
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(4)),
                          child: Text(_aiProvider, style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 200,
                          child: Text(_aiModelName, overflow: TextOverflow.ellipsis, textAlign: TextAlign.right, style: const TextStyle(color: Colors.cyanAccent, fontFamily: 'Courier', fontSize: 12)),
                        ),
                        const SizedBox(width: 10),
                        IconButton(
                          icon: const Icon(Icons.settings, color: Colors.cyanAccent),
                          tooltip: "Configure AI Provider",
                          onPressed: _showAiSettingsDialog,
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              Expanded(
                child: _messages.isEmpty 
                  ? Center(child: Text("Configure your API settings and start a chat.", style: TextStyle(color: Colors.grey[700])))
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