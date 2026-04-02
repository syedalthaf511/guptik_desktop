import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart'; // 🚀 ADDED: The official Video Player
import '../../services/trustme/trust_me_service.dart';

class SecureChatsScreen extends StatefulWidget {
  const SecureChatsScreen({super.key});

  @override
  State<SecureChatsScreen> createState() => _SecureChatsScreenState();
}

class _SecureChatsScreenState extends State<SecureChatsScreen> {
  List<ConversationSummary> _conversations = [];
  bool _isLoading = true;
  ConversationSummary? _selectedChat;

  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<Map<String, dynamic>> _activeMessages = [];

  Timer? _messageTimer;
  String _myUserId = '';
  int _previousMessageCount = 0;

  @override
  void initState() {
    super.initState();
    _myUserId = Supabase.instance.client.auth.currentUser?.id ?? '';
    _fetchConversations();

    _messageTimer = Timer.periodic(const Duration(milliseconds: 1500), (timer) {
      if (_selectedChat != null) {
        _loadActiveMessages();
      }
      if (timer.tick % 3 == 0) {
        _fetchConversationsLocally();
      }
      if (timer.tick % 40 == 0 && _selectedChat != null) {
        _pingSupabaseOnlineStatus();
      }
    });
  }

  Future<void> _fetchConversationsLocally() async {
    try {
      final chats = await TrustMeService.instance.getConversations();
      if (mounted) setState(() => _conversations = chats);
    } catch (_) {}
  }

  Future<void> _fetchConversations() async {
    setState(() => _isLoading = true);
    await _fetchConversationsLocally();
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadActiveMessages() async {
    if (_selectedChat == null) return;

    try {
      final dbMessages = await TrustMeService.instance.getMessages(_selectedChat!.id);

      if (!mounted) return;

      final List<Map<String, dynamic>> formattedMessages = dbMessages.map<Map<String, dynamic>>((msg) {
        final rawContent = msg['content'].toString();
        String type = msg['content_type'] ?? 'text';
        String cleanContent = rawContent;

        // 🚀 LOOKS FOR THE NEW [media] TAG
        if (rawContent.startsWith('[media]')) {
          final lowerContent = rawContent.toLowerCase();
          if (lowerContent.endsWith('.mp4') || lowerContent.endsWith('.mov') || lowerContent.endsWith('.mkv')) {
            type = 'video';
          } else if (lowerContent.endsWith('.pdf') || lowerContent.endsWith('.doc') || lowerContent.endsWith('.txt')) {
            type = 'document';
          } else {
            type = 'image';
          }
        } 
        else if (rawContent.startsWith('[vault]')) {
           // Fallback for previous messages sent under the old tag
           type = 'image'; 
        }

        final isMe = msg['sender_id'] == _myUserId;

        return {
          'content': cleanContent,
          'isMe': isMe,
          'time': DateTime.tryParse(msg['created_at'].toString()) ?? DateTime.now(),
          'type': type,
        };
      }).toList();

      setState(() {
        _activeMessages = formattedMessages;
      });

      if (formattedMessages.length > _previousMessageCount) {
        _previousMessageCount = formattedMessages.length;
        Future.delayed(const Duration(milliseconds: 100), () {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });
      }
    } catch (e) {
      debugPrint("Failed to load messages: $e");
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _selectedChat == null) return;

    setState(() {
      _activeMessages.add(<String,dynamic>{
        'content': text,
        'isMe': true,
        'time': DateTime.now(),
        'type': 'text',
      });
      _previousMessageCount++;
      _messageController.clear();
    });

    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });

    try {
      await TrustMeService.instance.sendMessage(
        conversationId: _selectedChat!.id,
        content: text,
      );
    } catch (e) {
      debugPrint("Message failed to send: $e");
    }
  }

  Future<void> _pingSupabaseOnlineStatus() async {
    try {
      if (_myUserId.isNotEmpty) {
        await Supabase.instance.client
            .from('trust_me_secure_invites')
            .update({'updated_at': DateTime.now().toUtc().toIso8601String()})
            .or('creator_id.eq.$_myUserId,connected_with.eq.$_myUserId');
      }
    } catch (e) {
      debugPrint("Presence Ping Failed: $e");
    }
  }

  @override
  void dispose() {
    _messageTimer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 320,
          decoration: const BoxDecoration(
            color: Color(0xFF0F172A),
            border: Border(right: BorderSide(color: Colors.white12, width: 1)),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                color: const Color(0xFF1E293B),
                child: TextField(
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: "Search encrypted chats...",
                    hintStyle: TextStyle(color: Colors.grey.shade500),
                    prefixIcon: const Icon(Icons.search, color: Colors.grey),
                    filled: true,
                    fillColor: Colors.black26,
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: Colors.cyanAccent))
                    : _conversations.isEmpty
                    ? _buildEmptyList()
                    : ListView.builder(
                        itemCount: _conversations.length,
                        itemBuilder: (context, index) {
                          final chat = _conversations[index];
                          final isSelected = _selectedChat?.id == chat.id;
                          return _buildChatTile(chat, isSelected);
                        },
                      ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _selectedChat == null
              ? _buildNoChatSelected()
              : _buildActiveChatArea(),
        ),
      ],
    );
  }

  Widget _buildChatTile(ConversationSummary chat, bool isSelected) {
    return InkWell(
      onTap: () {
        setState(() {
          _selectedChat = chat;
          _activeMessages.clear();
          _previousMessageCount = 0;
        });
        _loadActiveMessages();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white.withAlpha(12) : Colors.transparent,
          border: const Border(bottom: BorderSide(color: Colors.white10)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: Colors.cyanAccent.withAlpha(50),
              child: Text(
                chat.displayName[0].toUpperCase(),
                style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    chat.displayName,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    chat.lastMessagePreview ?? "No messages yet",
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  chat.lastMessageAt != null
                      ? "${chat.lastMessageAt!.hour}:${chat.lastMessageAt!.minute.toString().padLeft(2, '0')}"
                      : "",
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                ),
                const SizedBox(height: 6),
                if (chat.unreadCount > 0)
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(color: Colors.cyanAccent, shape: BoxShape.circle),
                    child: Text(
                      chat.unreadCount.toString(),
                      style: const TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyList() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shield_outlined, size: 48, color: Colors.grey.shade700),
            const SizedBox(height: 16),
            const Text("No Secure Chats", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text("Use the sidebar to generate a code and establish a new P2P connection.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _buildNoChatSelected() {
    return Container(
      color: const Color(0xFF0F172A),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline, size: 80, color: Colors.cyanAccent.withAlpha(50)),
            const SizedBox(height: 24),
            const Text("Guptik Trust Me (V1)", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text("Select a chat to view your end-to-end encrypted messages.\nKeys never leave this device.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.greenAccent.withAlpha(20),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.greenAccent.withAlpha(100)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle, color: Colors.greenAccent, size: 16),
                  SizedBox(width: 8),
                  Text("Double Ratchet Protocol Active", style: TextStyle(color: Colors.greenAccent, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveChatArea() {
    return Container(
      color: const Color(0xFF0F172A),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: const BoxDecoration(
              color: Color(0xFF1E293B),
              border: Border(bottom: BorderSide(color: Colors.white12, width: 1)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.cyanAccent.withAlpha(50),
                  child: Text(
                   _selectedChat!.displayName[0].toUpperCase(),
                    style: const TextStyle(color: Colors.cyanAccent),
                  ),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                    _selectedChat!.displayName,
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const Row(
                      children: [
                        Icon(Icons.lock, color: Colors.cyanAccent, size: 12),
                        SizedBox(width: 4),
                        Text("E2E Encrypted Connection", style: TextStyle(color: Colors.cyanAccent, fontSize: 12)),
                      ],
                    ),
                  ],
                ),
                const Spacer(),
                IconButton(icon: const Icon(Icons.search, color: Colors.grey), onPressed: () {}),
                IconButton(icon: const Icon(Icons.more_vert, color: Colors.grey), onPressed: () {}),
              ],
            ),
          ),

          Expanded(
            child: _activeMessages.isEmpty
                ? Center(child: Text("Send a message to start the secure chat.", style: TextStyle(color: Colors.grey.shade600)))
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(24),
                    itemCount: _activeMessages.length,
                    itemBuilder: (context, index) {
                      final msg = _activeMessages[index];
                      final isMe = msg['isMe'] as bool;

                      return Align(
                        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          constraints: const BoxConstraints(maxWidth: 400),
                          decoration: BoxDecoration(
                            color: isMe ? const Color(0xFF006A60) : const Color(0xFF1E293B),
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(16),
                              topRight: const Radius.circular(16),
                              bottomLeft: Radius.circular(isMe ? 16 : 0),
                              bottomRight: Radius.circular(isMe ? 0 : 16),
                            ),
                          ),
                          
                          // 🚀 UPGRADED: Real Image AND Video Players!
                          child: msg['type'] == 'image'
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    msg['content'].toString().replaceFirst('[media]', 'http://localhost:55000').replaceFirst('[vault]', 'http://localhost:55000'),
                                    width: 250,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) => 
                                        const Text("⚠️ Cannot load image", style: TextStyle(color: Colors.red)),
                                  ),
                                )
                              : msg['type'] == 'video'
                                  ? _VideoBubble(url: msg['content'].toString().replaceFirst('[media]', 'http://localhost:55000').replaceFirst('[vault]', 'http://localhost:55000'))
                                  : Text(
                                      msg['content'],
                                      style: const TextStyle(color: Colors.white, fontSize: 15),
                                    ),
                        ),
                      );
                    },
                  ),
          ),

          Container(
            padding: const EdgeInsets.all(16),
            color: const Color(0xFF1E293B),
            child: Row(
              children: [
                IconButton(icon: const Icon(Icons.attach_file, color: Colors.grey), onPressed: _showAttachmentMenu),
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    style: const TextStyle(color: Colors.white),
                    onSubmitted: (_) => _sendMessage(),
                    decoration: InputDecoration(
                      hintText: "Type an encrypted message...",
                      hintStyle: TextStyle(color: Colors.grey.shade600),
                      filled: true,
                      fillColor: Colors.black26,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FloatingActionButton(
                  mini: true,
                  backgroundColor: Colors.cyanAccent,
                  onPressed: _sendMessage,
                  child: const Icon(Icons.send, color: Colors.black, size: 20),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showAttachmentMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildAttachmentOption(icon: Icons.image, label: "Image", color: Colors.purpleAccent, onTap: () { Navigator.pop(context); _pickFile('image'); }),
              _buildAttachmentOption(icon: Icons.videocam, label: "Video", color: Colors.pinkAccent, onTap: () { Navigator.pop(context); _pickFile('video'); }),
              _buildAttachmentOption(icon: Icons.insert_drive_file, label: "Document", color: Colors.blueAccent, onTap: () { Navigator.pop(context); _pickFile('document'); }),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAttachmentOption({required IconData icon, required String label, required Color color, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(radius: 32, backgroundColor: color.withAlpha(40), child: Icon(icon, color: color, size: 28)),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Future<void> _pickFile(String type) async {
    FileType pickerType = FileType.any;
    if (type == 'image') pickerType = FileType.image;
    else if (type == 'video') pickerType = FileType.video;

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(type: pickerType, allowMultiple: false);
      if (result != null && result.files.single.path != null) {
        _sendFile(result.files.single.path!, result.files.single.name, type);
      }
    } catch (e) { debugPrint("Error picking file: $e"); }
  }

  Future<void> _sendFile(String filePath, String fileName, String type) async {
    if (_selectedChat == null) return;
    final sizeInMB = await File(filePath).length() / (1024 * 1024);

    if (sizeInMB > 500) {
      setState(() {
        _activeMessages.add({'content': '❌ Error: Streaming limit is 500MB.', 'isMe': true, 'time': DateTime.now(), 'type': 'system'});
        _previousMessageCount++;
      });
      return;
    }

    setState(() {
      _activeMessages.add(<String, dynamic>{'content': 'Uploading $type... (${sizeInMB.toStringAsFixed(1)} MB)', 'isMe': true, 'time': DateTime.now(), 'type': 'system'});
      _previousMessageCount++;
    });

    try {
      final response = await TrustMeService.instance.streamMediaFile(
        conversationId: _selectedChat!.id,
        filePath: filePath,
        contentType: type,
      );

      setState(() {
        _activeMessages.removeWhere((msg) => msg['type'] == 'system');
        _activeMessages.add(<String, dynamic>{'content': response['path'], 'isMe': true, 'time': DateTime.now(), 'type': type});
      });
    } catch (e) {
      setState(() {
        _activeMessages.removeWhere((msg) => msg['type'] == 'system');
        _activeMessages.add(<String, dynamic>{'content': '❌ Failed to upload $type', 'isMe': true, 'time': DateTime.now(), 'type': 'system'});
      });
    }
  }
}


// 🚀 BRAND NEW: The Custom Video Player Bubble with Error Catching!
class _VideoBubble extends StatefulWidget {
  final String url;
  const _VideoBubble({required this.url});

  @override
  State<_VideoBubble> createState() => _VideoBubbleState();
}

class _VideoBubbleState extends State<_VideoBubble> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    try {
      debugPrint("🎥 Attempting to load video from: ${widget.url}");
      _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      
      // 🚀 THE FIX: We added an 'await' with a try/catch block so it stops spinning if it fails!
      await _controller!.initialize();
      
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e) {
      debugPrint("❌ Video Player Error: $e");
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
        });
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 🚨 IF IT FAILS: Show a red box with the exact error message!
    if (_errorMessage.isNotEmpty) {
      return Container(
        width: 250,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.red.withAlpha(40),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.redAccent.withAlpha(100)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 36),
            const SizedBox(height: 8),
            const Text(
              "Video Error",
              style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              _errorMessage,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    // ⏳ STILL LOADING: Show the spinner
    if (!_isInitialized || _controller == null) {
      return const SizedBox(
        height: 150, width: 250,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.cyanAccent),
              SizedBox(height: 12),
              Text("Buffering securely...", style: TextStyle(color: Colors.cyanAccent, fontSize: 12)),
            ],
          ),
        ),
      );
    }

    // ✅ SUCCESS: Play the Video!
    return SizedBox(
      width: 250,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: AspectRatio(
              aspectRatio: _controller!.value.aspectRatio,
              child: VideoPlayer(_controller!),
            ),
          ),
          const SizedBox(height: 8),
          IconButton(
            icon: Icon(
              _controller!.value.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
              color: Colors.white,
              size: 36,
            ),
            onPressed: () {
              setState(() {
                _controller!.value.isPlaying ? _controller!.pause() : _controller!.play();
              });
            },
          ),
        ],
      ),
    );
  }
}
