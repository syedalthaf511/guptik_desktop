import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';
import 'package:http/http.dart' as http; 
import '../../services/trustme/trust_me_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// HELPERS
// ─────────────────────────────────────────────────────────────────────────────

/// Converts a raw [media]/[vault] content string to a full HTTP URL.
String _resolveMediaUrl(String raw) {
  if (raw.startsWith('[media]')) {
    return raw.replaceFirst("[media]", "http://localhost:55000");
  }
  if (raw.startsWith('[vault]')) {
    return raw.replaceFirst("[vault]", "http://localhost:55000");
  }
  return raw;
}

/// Returns a WhatsApp-style time string: "3:07 PM"
String _formatTime(DateTime dt) {
  final h = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
  final m = dt.minute.toString().padLeft(2, '0');
  final ampm = dt.hour >= 12 ? 'PM' : 'AM';
  return '$h:$m $ampm';
}

/// Returns date label for separator: "Today", "Yesterday", or "12 Apr 2025"
String _formatDateLabel(DateTime dt) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final msgDay = DateTime(dt.year, dt.month, dt.day);
  final diff = today.difference(msgDay).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
}

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Gets a friendly last-message preview for the sidebar
String _previewForType(String type, String content) {
  switch (type) {
    case 'image':    return '🖼  Photo';
    case 'video':    return '🎥  Video';
    case 'document': return '📄  Document';
    case 'audio':    return '🎵  Audio';
    default:
      // strip any prefix tags
      final clean = content
          .replaceAll(RegExp(r'^\[(media|vault|document)\]'), '')
          .trim();
      return clean.length > 40 ? '${clean.substring(0, 40)}…' : clean;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MAIN SCREEN
// ─────────────────────────────────────────────────────────────────────────────

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
  
  final FocusNode _focusNode = FocusNode(); 
  List<Map<String, dynamic>> _activeMessages = [];

  Timer? _messageTimer;
  String _myUserId = '';
  int _previousMessageCount = 0;

  String? _editingMessageId; 

  @override
  void initState() {
    super.initState();
    _myUserId = Supabase.instance.client.auth.currentUser?.id ?? '';
    _fetchConversations();

    _messageTimer = Timer.periodic(const Duration(milliseconds: 1500), (timer) {
      if (_selectedChat != null) {
        _loadActiveMessages();
        TrustMeService.instance.markConversationAsRead(_selectedChat!.id);
      }
      if (timer.tick % 3 == 0) _fetchConversationsLocally();
      if (timer.tick % 40 == 0 && _selectedChat != null) {
        _pingSupabaseOnlineStatus();
      }
      if (timer.tick % 4 == 0 && _selectedChat != null) {
        _checkPeerOnlineStatus();
      }
    });
  }

  Future<void> _checkPeerOnlineStatus() async {
    if (_selectedChat == null) return;
    try {
      final contact = await TrustMeService.instance.getContactForConversation(_selectedChat!.id);
      if (contact != null && contact['url'] != null) {
        var url = contact['url'].toString();
        if (!url.startsWith('http')) url = 'https://$url';

        final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 3));
        if (mounted) {
          setState(() {
            _selectedChat!.isOnline = (res.statusCode == 200);
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() => _selectedChat!.isOnline = false);
    }
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

  // ── Message loading ─────────────────────────────────────────────────────────

  Future<void> _loadActiveMessages() async {
    if (_selectedChat == null) return;
    try {
      final dbMessages =
          await TrustMeService.instance.getMessages(_selectedChat!.id);
      if (!mounted) return;

      final List<Map<String, dynamic>> formatted =
          dbMessages.map<Map<String, dynamic>>((msg) {
        final rawContent = msg['content']?.toString() ?? '';
        String type = msg['content_type']?.toString() ?? 'text';

        // ── Detect type from content prefix ──
        if (rawContent.startsWith('[media]') ||
            rawContent.startsWith('[vault]')) {
          final lower = rawContent.toLowerCase();
          if (lower.endsWith('.mp4') ||
              lower.endsWith('.mov') ||
              lower.endsWith('.mkv') ||
              lower.endsWith('.avi')) {
            type = 'video';
          } else if (lower.endsWith('.pdf') ||
              lower.endsWith('.doc') ||
              lower.endsWith('.docx') ||
              lower.endsWith('.txt') ||
              lower.endsWith('.zip') ||
              lower.endsWith('.xlsx') ||
              lower.endsWith('.csv')) {
            type = 'document';
          } else {
            type = 'image';
          }
        } else if (rawContent.startsWith('[document]')) {
          type = 'document';
        }

        // ── Deleted message override ──
        final isDeleted =
            msg['is_deleted_for_everyone'] == true || msg['is_deleted'] == true;

        // 🚀 THE FIX: Convert DB time (UTC) to Local Device Time (IST)
        String rawTime = msg['created_at']?.toString() ?? '';
        if (rawTime.isNotEmpty && !rawTime.endsWith('Z') && !rawTime.contains('+')) {
          rawTime += 'Z'; // Force Flutter to recognize this as UTC time
        }
        DateTime parsedTime = DateTime.tryParse(rawTime)?.toLocal() ?? DateTime.now();

        return {
          'id': msg['id']?.toString() ?? '',
          'content': rawContent,
          'isMe': msg['sender_id'] == _myUserId,
          'time': parsedTime, // 🚀 Converted time injected here!
          'type': isDeleted ? 'deleted' : type,
          'is_read': msg['is_read'] == true,
          'is_delivered': msg['is_delivered'] == true,
          'reaction_emoji': msg['reaction_emoji']?.toString(),
          'reply_to_id': msg['reply_to_message_id']?.toString(),
          'media_file_size': msg['media_file_size'],
          'media_mime_type': msg['media_mime_type']?.toString(),
        };
      }).toList();

      setState(() => _activeMessages = formatted);

      if (formatted.length > _previousMessageCount) {
        _previousMessageCount = formatted.length;
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
      debugPrint('Failed to load messages: $e');
    }
  }

  // ── Send & Edit ────────────────────────────────────────────────────────────────────

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _selectedChat == null) return;

    if (_editingMessageId != null) {
      // --- WE ARE EDITING A MESSAGE ---
      final msgId = _editingMessageId!;
      
      setState(() {
        // Optimistically update the UI instantly
        final index = _activeMessages.indexWhere((m) => m['id'] == msgId);
        if (index != -1) _activeMessages[index]['content'] = text;
        
        _editingMessageId = null; // Exit edit mode
        _messageController.clear();
      });

      // Send the edit command to the backend
      await TrustMeService.instance.editMessage(conversationId: _selectedChat!.id, messageId: msgId, newContent: text);
      
    } else {
      // --- WE ARE SENDING A NEW MESSAGE ---
      setState(() {
        _activeMessages.add({
          'content': text,
          'isMe': true,
          'time': DateTime.now(), // Local time for instant rendering
          'type': 'text',
          'is_read': false,
          'is_delivered': false,
        });
        _previousMessageCount++;
        _messageController.clear();
      });

      _scrollToBottom();

      try {
        await TrustMeService.instance.sendMessage(
          conversationId: _selectedChat!.id,
          content: text,
        );
      } catch (e) {
        debugPrint('Message send error: $e');
      }
    }
  }

  void _scrollToBottom() {
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

  void _showDesktopMenu(Offset position, Map<String, dynamic> msg) {
    final isMe = msg['isMe'] as bool;
    final type = msg['type'] as String;

    if (type == 'deleted') return; // Cannot edit/copy a deleted message

    final items = <PopupMenuEntry<String>>[
      if (type == 'text') 
        const PopupMenuItem(value: 'copy', child: Row(children: [Icon(Icons.copy, size: 18, color: Colors.white), SizedBox(width: 8), Text('Copy', style: TextStyle(color: Colors.white))])),
      if (isMe && type == 'text') 
        const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit, size: 18, color: Colors.cyanAccent), SizedBox(width: 8), Text('Edit', style: TextStyle(color: Colors.white))])),
      const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline, size: 18, color: Colors.redAccent), SizedBox(width: 8), Text('Delete', style: TextStyle(color: Colors.redAccent))])),
    ];

    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
      items: items,
      color: const Color(0xFF1E293B),
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ).then((value) {
      if (value == 'copy') {
        Clipboard.setData(ClipboardData(text: msg['content']));
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied to clipboard'), backgroundColor: Colors.green));
      } else if (value == 'edit') {
        setState(() {
          _editingMessageId = msg['id'];
          _messageController.text = msg['content'];
          _focusNode.requestFocus();
        });
      } else if (value == 'delete') {
        _showDeleteDialog(msg);
      }
    });
  }

  void _showDeleteDialog(Map<String, dynamic> msg) {
    final isMe = msg['isMe'] as bool;

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text("Delete message?", style: TextStyle(color: Colors.white)),
        content: const Text("This action cannot be undone.", style: TextStyle(color: Colors.grey)),
        actions: [
          TextButton(
            child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
            onPressed: () => Navigator.pop(dialogCtx),
          ),
          TextButton(
            child: const Text("Delete for me", style: TextStyle(color: Colors.cyanAccent)),
            onPressed: () async {
              Navigator.pop(dialogCtx);
              setState(() => _activeMessages.removeWhere((m) => m['id'] == msg['id']));
              await TrustMeService.instance.deleteMessage(conversationId: _selectedChat!.id, messageId: msg['id'], forEveryone: false);
            },
          ),
          if (isMe)
            TextButton(
              child: const Text("Delete for everyone", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
              onPressed: () async {
                Navigator.pop(dialogCtx);
                setState(() {
                  final index = _activeMessages.indexWhere((m) => m['id'] == msg['id']);
                  if (index != -1) _activeMessages[index]['type'] = 'deleted';
                });
                await TrustMeService.instance.deleteMessage(conversationId: _selectedChat!.id, messageId: msg['id'], forEveryone: true);
              },
            ),
        ],
      ),
    );
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
      debugPrint('Presence ping failed: $e');
    }
  }

  @override
  void dispose() {
    _messageTimer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose(); 
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // ── LEFT: Chat list ──────────────────────────────────────────────────
        Container(
          width: 320,
          decoration: const BoxDecoration(
            color: Color(0xFF0F172A),
            border:
                Border(right: BorderSide(color: Colors.white12, width: 1)),
          ),
          child: Column(
            children: [
              // Search bar
              Container(
                padding: const EdgeInsets.all(12),
                color: const Color(0xFF1E293B),
                child: TextField(
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Search encrypted chats...',
                    hintStyle: TextStyle(color: Colors.grey.shade500),
                    prefixIcon:
                        const Icon(Icons.search, color: Colors.grey),
                    filled: true,
                    fillColor: Colors.black26,
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 0),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                            color: Colors.cyanAccent))
                    : _conversations.isEmpty
                        ? _buildEmptyList()
                        : ListView.builder(
                            itemCount: _conversations.length,
                            itemBuilder: (context, index) {
                              final chat = _conversations[index];
                              return _buildChatTile(
                                  chat, _selectedChat?.id == chat.id);
                            },
                          ),
              ),
            ],
          ),
        ),

        // ── RIGHT: Active chat ───────────────────────────────────────────────
        Expanded(
          child: _selectedChat == null
              ? _buildNoChatSelected()
              : _buildActiveChatArea(),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // CHAT LIST TILE
  // ─────────────────────────────────────────────────────────────────────────────

  Widget _buildChatTile(ConversationSummary chat, bool isSelected) {
    final lastType = chat.lastMessageType ?? 'text';
    final preview = _previewForType(
        lastType, chat.lastMessagePreview ?? 'No messages yet');

    // Timestamp label
    String timeLabel = '';
    if (chat.lastMessageAt != null) {
      final now = DateTime.now();
      final diff =
          DateTime(now.year, now.month, now.day)
              .difference(DateTime(chat.lastMessageAt!.year,
                  chat.lastMessageAt!.month, chat.lastMessageAt!.day))
              .inDays;
      if (diff == 0) {
        timeLabel = _formatTime(chat.lastMessageAt!);
      } else if (diff == 1) {
        timeLabel = 'Yesterday';
      } else {
        const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
        timeLabel =
            '${chat.lastMessageAt!.day} ${months[chat.lastMessageAt!.month - 1]}';
      }
    }

    return InkWell(
      onTap: () {
        setState(() {
          _selectedChat = chat;
          _activeMessages.clear();
          _previousMessageCount = 0;
          chat.unreadCount = 0;
          _editingMessageId = null; 
        });
        TrustMeService.instance.markConversationAsRead(chat.id);
        _loadActiveMessages();
      },
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.cyanAccent.withAlpha(18)
              : Colors.transparent,
          border: const Border(
              bottom: BorderSide(color: Colors.white10)),
        ),
        child: Row(
          children: [
            // Avatar with online dot
            Stack(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: Colors.cyanAccent.withAlpha(50),
                  child: Text(
                    chat.displayName[0].toUpperCase(),
                    style: const TextStyle(
                        color: Colors.cyanAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 18),
                  ),
                ),
                // Online presence dot
                if (chat.isOnline)
                  Positioned(
                    bottom: 1,
                    right: 1,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: Colors.greenAccent,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: const Color(0xFF0F172A), width: 2),
                      ),
                    ),
                  ),
                // Pinned badge
                if (chat.isPinned == true)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                          color: Color(0xFF0F172A),
                          shape: BoxShape.circle),
                      child: const Icon(Icons.push_pin,
                          color: Colors.cyanAccent, size: 11),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name row
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          chat.displayName,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (chat.isMuted == true)
                        const Icon(Icons.volume_off,
                            color: Colors.grey, size: 13),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    preview,
                    style: TextStyle(
                        color: Colors.grey.shade500, fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Time + badge column
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  timeLabel,
                  style: TextStyle(
                      color: chat.unreadCount > 0
                          ? Colors.cyanAccent
                          : Colors.grey.shade600,
                      fontSize: 11),
                ),
                const SizedBox(height: 5),
                if (chat.unreadCount > 0)
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: const BoxDecoration(
                        color: Colors.cyanAccent,
                        shape: BoxShape.circle),
                    child: Text(
                      chat.unreadCount > 99
                          ? '99+'
                          : chat.unreadCount.toString(),
                      style: const TextStyle(
                          color: Colors.black,
                          fontSize: 10,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // EMPTY / PLACEHOLDER STATES
  // ─────────────────────────────────────────────────────────────────────────────

  Widget _buildEmptyList() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shield_outlined,
                size: 48, color: Colors.grey.shade700),
            const SizedBox(height: 16),
            const Text('No Secure Chats',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              'Use the sidebar to generate a code\nand establish a new P2P connection.',
              textAlign: TextAlign.center,
              style:
                  TextStyle(color: Colors.grey.shade500, fontSize: 13),
            ),
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
            Icon(Icons.lock_outline,
                size: 80, color: Colors.cyanAccent.withAlpha(50)),
            const SizedBox(height: 24),
            const Text('Guptik Trust Me (V1)',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text(
              'Select a chat to view your end-to-end encrypted messages.\nKeys never leave this device.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.greenAccent.withAlpha(20),
                borderRadius: BorderRadius.circular(20),
                border:
                    Border.all(color: Colors.greenAccent.withAlpha(100)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle,
                      color: Colors.greenAccent, size: 16),
                  SizedBox(width: 8),
                  Text('Double Ratchet Protocol Active',
                      style: TextStyle(
                          color: Colors.greenAccent, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // ACTIVE CHAT AREA
  // ─────────────────────────────────────────────────────────────────────────────

  Widget _buildActiveChatArea() {
    return Container(
      color: const Color(0xFF0A1628),
      child: Column(
        children: [
          _buildChatHeader(),
          Expanded(child: _buildMessageList()),
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildChatHeader() {
    final isOnline = _selectedChat!.isOnline;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        border:
            Border(bottom: BorderSide(color: Colors.white12, width: 1)),
      ),
      child: Row(
        children: [
          Stack(
            children: [
              CircleAvatar(
                backgroundColor: Colors.cyanAccent.withAlpha(50),
                child: Text(
                  _selectedChat!.displayName[0].toUpperCase(),
                  style: const TextStyle(color: Colors.cyanAccent),
                ),
              ),
              if (isOnline)
                Positioned(
                  bottom: 1,
                  right: 1,
                  child: Container(
                    width: 11,
                    height: 11,
                    decoration: BoxDecoration(
                      color: Colors.greenAccent,
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: const Color(0xFF1E293B), width: 2),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _selectedChat!.displayName,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold),
                ),
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      margin: const EdgeInsets.only(right: 5),
                      decoration: BoxDecoration(
                        color: isOnline ? Colors.greenAccent : Colors.grey,
                        shape: BoxShape.circle,
                      ),
                    ),
                    Text(
                      isOnline ? 'Online' : 'Offline',
                      style: TextStyle(
                          color:
                              isOnline ? Colors.greenAccent : Colors.grey,
                          fontSize: 11),
                    ),
                    const SizedBox(width: 10),
                    const Icon(Icons.lock,
                        color: Colors.cyanAccent, size: 11),
                    const SizedBox(width: 4),
                    const Text('E2E Encrypted',
                        style: TextStyle(
                            color: Colors.cyanAccent, fontSize: 11)),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
              icon: const Icon(Icons.search, color: Colors.grey),
              onPressed: () {}),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.grey),
            color: const Color(0xFF1E293B),
            onSelected: (value) {
              if (value == 'rename') _showRenameDialog();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'rename',
                child: Row(
                  children: [
                    Icon(Icons.edit, color: Colors.cyanAccent, size: 18),
                    SizedBox(width: 12),
                    Text('Rename Contact',
                        style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Rename contact dialog ───────────────────────────────────────────────────
  void _showRenameDialog() {
    if (_selectedChat == null) return;

    final originalName = _selectedChat!.contactUsername ?? 'Unknown';
    final currentCustom = _selectedChat!.customUsername ?? '';

    final controller = TextEditingController(
        text: currentCustom.isNotEmpty ? currentCustom : originalName);

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Row(
          children: [
            Icon(Icons.edit, color: Colors.cyanAccent, size: 20),
            SizedBox(width: 10),
            Text('Rename Contact',
                style: TextStyle(color: Colors.white, fontSize: 17)),
          ],
        ),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Original name: $originalName',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Enter a custom name...',
                  hintStyle:
                      TextStyle(color: Colors.grey.shade600),
                  filled: true,
                  fillColor: Colors.black26,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  enabledBorder: OutlineInputBorder(
                    borderSide:
                        BorderSide(color: Colors.grey.shade700),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide:
                        const BorderSide(color: Colors.cyanAccent),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.clear,
                        color: Colors.grey, size: 18),
                    tooltip: 'Clear custom name',
                    onPressed: () => controller.clear(),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Clear the field to revert to the original name.',
                style: TextStyle(color: Colors.grey, fontSize: 11),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel',
                style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.cyanAccent),
            onPressed: () async {
              final newName = controller.text.trim();
              Navigator.pop(dialogCtx);

              final success =
                  await TrustMeService.instance.renameContact(
                conversationId: _selectedChat!.id,
                customName: newName,
              );

              if (success && mounted) {
                // Instantly update the UI
                setState(() {
                  final idx = _conversations
                      .indexWhere((c) => c.id == _selectedChat!.id);
                  if (idx != -1) {
                    final old = _conversations[idx];
                    _conversations[idx] = ConversationSummary(
                      id: old.id,
                      type: old.type,
                      contactUsername: old.contactUsername,
                      customUsername:
                          newName.isEmpty ? null : newName,
                      lastMessagePreview: old.lastMessagePreview,
                      lastMessageAt: old.lastMessageAt,
                      lastMessageType: old.lastMessageType,
                      unreadCount: old.unreadCount,
                      isOnline: old.isOnline,
                      isPinned: old.isPinned,
                      isMuted: old.isMuted,
                    );
                    _selectedChat = _conversations[idx];
                  }
                });

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(newName.isEmpty
                        ? 'Name reverted to "$originalName"'
                        : 'Contact renamed to "$newName"'),
                    backgroundColor: Colors.green.shade700,
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            },
            child: const Text('Save',
                style: TextStyle(color: Colors.black,
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList() {
    if (_activeMessages.isEmpty) {
      return Center(
        child: Text(
          'Send a message to start the secure chat.',
          style: TextStyle(color: Colors.grey.shade600),
        ),
      );
    }

    // Build items list with date separators
    final List<Widget> items = [];
    for (int i = 0; i < _activeMessages.length; i++) {
      final msg = _activeMessages[i];
      final msgTime = msg['time'] as DateTime;

      // Insert date separator when day changes
      if (i == 0 ||
          !_isSameDay(msgTime, _activeMessages[i - 1]['time'] as DateTime)) {
        items.add(_buildDateSeparator(_formatDateLabel(msgTime)));
      }

      items.add(_buildMessageBubble(msg));
    }

    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      children: items,
    );
  }

  Widget _buildDateSeparator(String label) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 12),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white10),
        ),
        child: Text(
          label,
          style: const TextStyle(color: Colors.grey, fontSize: 12),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // MESSAGE BUBBLE
  // ─────────────────────────────────────────────────────────────────────────────

  Widget _buildMessageBubble(Map<String, dynamic> msg) {
    final isMe = msg['isMe'] as bool;
    final type = msg['type'] as String;
    final time = msg['time'] as DateTime;
    final reaction = msg['reaction_emoji'] as String?;

    final bubbleColor = isMe
        ? const Color(0xFF005C4B)   // WhatsApp-style dark teal for sent
        : const Color(0xFF1E293B);  // Dark blue-grey for received

    Widget content;
    switch (type) {
      case 'deleted':
        content = _buildDeletedBubble();
        break;
      case 'image':
        content = _buildImageContent(msg);
        break;
      case 'video':
        content = _buildVideoContent(msg);
        break;
      case 'document':
        content = _buildDocumentContent(msg);
        break;
      default:
        content = _buildTextContent(msg['content'].toString());
    }

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onSecondaryTapDown: (details) => _showDesktopMenu(details.globalPosition, msg),
        onLongPressStart: (details) => _showDesktopMenu(details.globalPosition, msg), 
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Container(
              margin: EdgeInsets.only(
                bottom: reaction != null ? 4 : 6,
                left: isMe ? 60 : 0,
                right: isMe ? 0 : 60,
              ),
              decoration: BoxDecoration(
                color: (type == 'image' || type == 'video')
                    ? Colors.transparent
                    : bubbleColor,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isMe ? 16 : 4),
                  bottomRight: Radius.circular(isMe ? 4 : 16),
                ),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withAlpha(40),
                      blurRadius: 4,
                      offset: const Offset(0, 2)),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isMe ? 16 : 4),
                  bottomRight: Radius.circular(isMe ? 4 : 16),
                ),
                child: Stack(
                  children: [
                    // ── Media / text content ──
                    Padding(
                      padding: (type == 'image' || type == 'video')
                          ? EdgeInsets.zero
                          : const EdgeInsets.fromLTRB(12, 10, 12, 6),
                      child: content,
                    ),

                    // ── Timestamp + status row (bottom-right of bubble) ──
                    Positioned(
                      bottom: 6,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 2),
                        decoration: (type == 'image' || type == 'video')
                            ? BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(8),
                              )
                            : null,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _formatTime(time),
                              style: TextStyle(
                                  color: (type == 'image' || type == 'video')
                                      ? Colors.white
                                      : Colors.white54,
                                  fontSize: 10),
                            ),
                            if (isMe) ...[
                              const SizedBox(width: 4),
                              _buildStatusTick(
                                  msg['is_read'] as bool? ?? false,
                                  msg['is_delivered'] as bool? ?? false),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Reaction emoji below bubble ──
            if (reaction != null && reaction.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 6, left: 4, right: 4),
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: Text(reaction, style: const TextStyle(fontSize: 16)),
              ),
          ],
        ),
      ),
    );
  }

  // WhatsApp-style ticks & Queued Clock
  Widget _buildStatusTick(bool isRead, bool isDelivered) {
    if (isRead) {
      // Double blue/cyan ticks (Read by peer)
      return const Icon(Icons.done_all, size: 14, color: Colors.cyanAccent);
    } else if (isDelivered) {
      // Double grey ticks (Delivered to peer)
      return const Icon(Icons.done_all, size: 14, color: Colors.white54);
    } else {
      // Clock Icon! The message is queued locally waiting for the peer's Docker to come online.
      return const Icon(Icons.access_time, size: 13, color: Colors.white54);
    }
  }

  // ── Deleted bubble ───────────────────────────────────────────────────────────
  Widget _buildDeletedBubble() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.block, color: Colors.grey, size: 14),
        const SizedBox(width: 6),
        Text(
          'This message was deleted',
          style: TextStyle(
              color: Colors.grey.shade500,
              fontSize: 14,
              fontStyle: FontStyle.italic),
        ),
        const SizedBox(width: 40), // space for timestamp
      ],
    );
  }

  // ── Text bubble ─────────────────────────────────────────────────────────────
  Widget _buildTextContent(String content) {
    return Padding(
      padding: const EdgeInsets.only(right: 64, bottom: 8),
      child: Text(
        content,
        style: const TextStyle(color: Colors.white, fontSize: 15),
      ),
    );
  }

  // ── Image bubble ────────────────────────────────────────────────────────────
  Widget _buildImageContent(Map<String, dynamic> msg) {
    final url = _resolveMediaUrl(msg['content'].toString());
    return GestureDetector(
      onTap: () => _openImageFullscreen(url),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              url,
              width: 260,
              height: 220,
              fit: BoxFit.cover,
              loadingBuilder: (ctx, child, progress) {
                if (progress == null) return child;
                return Container(
                  width: 260,
                  height: 220,
                  color: Colors.black26,
                  child: Center(
                    child: CircularProgressIndicator(
                      value: progress.expectedTotalBytes != null
                          ? progress.cumulativeBytesLoaded /
                              progress.expectedTotalBytes!
                          : null,
                      color: Colors.cyanAccent,
                      strokeWidth: 2,
                    ),
                  ),
                );
              },
              errorBuilder: (ctx, error, _) => Container(
                width: 260,
                height: 100,
                color: Colors.black26,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.broken_image,
                        color: Colors.grey, size: 36),
                    const SizedBox(height: 6),
                    Text('Cannot load image',
                        style: TextStyle(
                            color: Colors.grey.shade500, fontSize: 12)),
                  ],
                ),
              ),
            ),
          ),
          // Tap hint
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(6)),
              child: const Icon(Icons.zoom_out_map,
                  color: Colors.white70, size: 14),
            ),
          ),
          // Bottom padding so timestamp sits cleanly
          const SizedBox(height: 28),
        ],
      ),
    );
  }

  void _openImageFullscreen(String url) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 5.0,
                child: Image.network(url,
                    fit: BoxFit.contain,
            errorBuilder: (_, a, b) => const Icon(
                        Icons.broken_image,
                        color: Colors.grey,
                        size: 80)),
              ),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20)),
                  child: const Icon(Icons.close,
                      color: Colors.white, size: 20),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Video bubble ─────────────────────────────────────────────────────────────
  Widget _buildVideoContent(Map<String, dynamic> msg) {
    final url = _resolveMediaUrl(msg['content'].toString());
    return GestureDetector(
      onTap: () => _openVideoPlayer(url),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 260,
            height: 200,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.movie, color: Colors.white24, size: 60),
          ),
          // Play button overlay
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.black.withAlpha(160),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white54, width: 2),
            ),
            child: const Icon(Icons.play_arrow,
                color: Colors.white, size: 32),
          ),
          // "Tap to play" label
          Positioned(
            bottom: 34,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('Tap to play',
                  style:
                      TextStyle(color: Colors.white70, fontSize: 11)),
            ),
          ),
          const SizedBox(height: 28),
        ],
      ),
    );
  }

  void _openVideoPlayer(String url) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => _VideoPlayerDialog(url: url),
    );
  }

  // ── Document bubble ──────────────────────────────────────────────────────────
  Widget _buildDocumentContent(Map<String, dynamic> msg) {
    final raw = msg['content'].toString();
    // Extract filename from end of path/url
    final fileName = raw
        .replaceAll(RegExp(r'^\[(document|media|vault)\]'), '')
        .trim()
        .split('/')
        .last;
    final mime = msg['media_mime_type']?.toString() ?? '';
    final size = msg['media_file_size'];
    final sizeLabel = size != null
        ? _formatFileSize(size is int ? size : int.tryParse(size.toString()) ?? 0)
        : '';

    IconData docIcon = Icons.insert_drive_file;
    Color docColor = Colors.blueAccent;
    if (mime.contains('pdf')) { docIcon = Icons.picture_as_pdf; docColor = Colors.redAccent; }
    else if (mime.contains('zip') || mime.contains('archive')) { docIcon = Icons.folder_zip; docColor = Colors.orangeAccent; }
    else if (mime.contains('sheet') || mime.contains('csv')) { docIcon = Icons.table_chart; docColor = Colors.greenAccent; }

    final url = _resolveMediaUrl(raw.replaceFirst(RegExp(r'^\[document\]'), '[media]'));

    return GestureDetector(
      onTap: () => _openDocumentUrl(url, fileName),
      child: Container(
        width: 240,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 32),
        decoration: BoxDecoration(
          color: Colors.black.withAlpha(60),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: docColor.withAlpha(30),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(docIcon, color: docColor, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fileName,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (sizeLabel.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(sizeLabel,
                        style: const TextStyle(
                            color: Colors.grey, fontSize: 11)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.open_in_new,
                color: Colors.cyanAccent, size: 18),
          ],
        ),
      ),
    );
  }

  /// Opens a document URL using the OS default handler.
  /// Works on Windows, macOS, and Linux — no extra package needed.
  Future<void> _launchUrl(String url) async {
    try {
      if (Platform.isWindows) {
        await Process.run('rundll32', ['url.dll,FileProtocolHandler', url]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [url]);
      } else {
        await Process.run('xdg-open', [url]);
      }
    } catch (e) {
      debugPrint('Could not open URL: $e');
    }
  }

  void _openDocumentUrl(String url, String fileName) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Open Document',
            style: TextStyle(color: Colors.white)),
        content: Text(
          'Open "$fileName" in your system viewer?',
          style: const TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel',
                style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.cyanAccent),
            onPressed: () {
              Navigator.pop(dialogCtx);
              _launchUrl(url);
            },
            child: const Text('Open',
                style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // INPUT BAR
  // ─────────────────────────────────────────────────────────────────────────────

  Widget _buildInputBar() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 🚀 ADDED: The "Editing Message" Banner
        if (_editingMessageId != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            color: const Color(0xFF1E293B),
            child: Row(
              children: [
                const Icon(Icons.edit, color: Colors.cyanAccent, size: 18),
                const SizedBox(width: 12),
                const Expanded(child: Text("Editing message...", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.grey, size: 20),
                  onPressed: () => setState(() {
                    _editingMessageId = null;
                    _messageController.clear();
                  })
                ),
              ],
            ),
          ),

        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            color: Color(0xFF1E293B),
            border: Border(top: BorderSide(color: Colors.white12)),
          ),
          child: Row(
            children: [
              if (_editingMessageId == null) // 🚀 Hide attachment when editing
                IconButton(
                  icon: const Icon(Icons.attach_file, color: Colors.grey),
                  onPressed: _showAttachmentMenu,
                ),
              Expanded(
                child: TextField(
                  controller: _messageController,
                  focusNode: _focusNode, 
                  style: const TextStyle(color: Colors.white),
                  onSubmitted: (_) => _sendMessage(),
                  maxLines: null,
                  decoration: InputDecoration(
                    hintText: 'Type an encrypted message...',
                    hintStyle: TextStyle(color: Colors.grey.shade600),
                    filled: true,
                    fillColor: Colors.black26,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
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
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // ATTACHMENT PICKER
  // ─────────────────────────────────────────────────────────────────────────────

  void _showAttachmentMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Padding(
          padding:
              const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildAttachOption(
                  icon: Icons.image,
                  label: 'Image',
                  color: Colors.purpleAccent,
                  onTap: () {
                    Navigator.pop(context);
                    _pickFile('image');
                  }),
              _buildAttachOption(
                  icon: Icons.videocam,
                  label: 'Video',
                  color: Colors.pinkAccent,
                  onTap: () {
                    Navigator.pop(context);
                    _pickFile('video');
                  }),
              _buildAttachOption(
                  icon: Icons.insert_drive_file,
                  label: 'Document',
                  color: Colors.blueAccent,
                  onTap: () {
                    Navigator.pop(context);
                    _pickFile('document');
                  }),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAttachOption(
      {required IconData icon,
      required String label,
      required Color color,
      required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
              radius: 32,
              backgroundColor: color.withAlpha(40),
              child: Icon(icon, color: color, size: 28)),
          const SizedBox(height: 8),
          Text(label,
              style: const TextStyle(
                  color: Colors.white70, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Future<void> _pickFile(String type) async {
    FileType pickerType = FileType.any;
    if (type == 'image') pickerType = FileType.image;
    if (type == 'video') pickerType = FileType.video;

    try {
      final result = await FilePicker.platform
          .pickFiles(type: pickerType, allowMultiple: false);
      if (result != null && result.files.single.path != null) {
        _sendFile(result.files.single.path!, result.files.single.name, type);
      }
    } catch (e) {
      debugPrint('File pick error: $e');
    }
  }

  Future<void> _sendFile(
      String filePath, String fileName, String type) async {
    if (_selectedChat == null) return;
    final sizeInMB =
        await File(filePath).length() / (1024 * 1024);

    if (sizeInMB > 500) {
      setState(() {
        _activeMessages.add({
          'content': '❌ File too large (max 500 MB)',
          'isMe': true,
          'time': DateTime.now(),
          'type': 'system'
        });
        _previousMessageCount++;
      });
      return;
    }

    setState(() {
      _activeMessages.add({
        'content':
            'Uploading $type... (${sizeInMB.toStringAsFixed(1)} MB)',
        'isMe': true,
        'time': DateTime.now(),
        'type': 'system'
      });
      _previousMessageCount++;
    });

    try {
      final response = await TrustMeService.instance.streamMediaFile(
        conversationId: _selectedChat!.id,
        filePath: filePath,
        contentType: type,
      );
      setState(() {
        _activeMessages.removeWhere((m) => m['type'] == 'system');
        _activeMessages.add({
          'content': response['path'],
          'isMe': true,
          'time': DateTime.now(),
          'type': type,
          'is_read': false,
          'is_delivered': false,
        });
      });
    } catch (e) {
      setState(() {
        _activeMessages.removeWhere((m) => m['type'] == 'system');
        _activeMessages.add({
          'content': '❌ Failed to upload $type',
          'isMe': true,
          'time': DateTime.now(),
          'type': 'system'
        });
      });
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// VIDEO PLAYER DIALOG  
// ─────────────────────────────────────────────────────────────────────────────

class _VideoPlayerDialog extends StatefulWidget {
  final String url;
  const _VideoPlayerDialog({required this.url});

  @override
  State<_VideoPlayerDialog> createState() => _VideoPlayerDialogState();
}

class _VideoPlayerDialogState extends State<_VideoPlayerDialog> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      _controller =
          VideoPlayerController.networkUrl(Uri.parse(widget.url));
      await _controller!.initialize();
      _controller!.addListener(() {
        if (mounted) setState(() {});
      });
      if (mounted) setState(() => _isInitialized = true);
      _controller!.play();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final maxDialogHeight = screenHeight * 0.85;

    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxDialogHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
              child: Row(
                children: [
                  const Icon(Icons.movie, color: Colors.cyanAccent, size: 18),
                  const SizedBox(width: 8),
                  const Expanded(
                      child: Text('Secure Video',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold))),
                  IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close,
                          color: Colors.grey, size: 20)),
                ],
              ),
            ),
            const SizedBox(height: 8),

            if (_error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline,
                        color: Colors.redAccent, size: 48),
                    const SizedBox(height: 12),
                    const Text('Failed to load video',
                        style: TextStyle(
                            color: Colors.redAccent,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Text(_error,
                        style: const TextStyle(
                            color: Colors.grey, fontSize: 11),
                        textAlign: TextAlign.center),
                  ],
                ),
              )
            else if (!_isInitialized)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.cyanAccent),
                    SizedBox(height: 14),
                    Text('Buffering securely...',
                        style: TextStyle(
                            color: Colors.cyanAccent, fontSize: 12)),
                  ],
                ),
              )
            else ...[
              Flexible(
                child: AspectRatio(
                  aspectRatio: _controller!.value.aspectRatio,
                  child: VideoPlayer(_controller!),
                ),
              ),

              VideoProgressIndicator(
                _controller!,
                allowScrubbing: true,
                colors: const VideoProgressColors(
                  playedColor: Colors.cyanAccent,
                  bufferedColor: Colors.white24,
                  backgroundColor: Colors.white12,
                ),
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Row(
                  children: [
                    Text(
                      _formatDuration(_controller!.value.position),
                      style: const TextStyle(
                          color: Colors.grey, fontSize: 12),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.replay_10,
                          color: Colors.white, size: 28),
                      onPressed: () {
                        final pos = _controller!.value.position -
                            const Duration(seconds: 10);
                        _controller!.seekTo(
                            pos < Duration.zero ? Duration.zero : pos);
                      },
                    ),
                    IconButton(
                      icon: Icon(
                        _controller!.value.isPlaying
                            ? Icons.pause_circle_filled
                            : Icons.play_circle_fill,
                        color: Colors.cyanAccent,
                        size: 44,
                      ),
                      onPressed: () {
                        _controller!.value.isPlaying
                            ? _controller!.pause()
                            : _controller!.play();
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.forward_10,
                          color: Colors.white, size: 28),
                      onPressed: () {
                        final dur = _controller!.value.duration;
                        final pos = _controller!.value.position +
                            const Duration(seconds: 10);
                        _controller!.seekTo(pos > dur ? dur : pos);
                      },
                    ),
                    const Spacer(),
                    Text(
                      _formatDuration(_controller!.value.duration),
                      style: const TextStyle(
                          color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}