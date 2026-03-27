import 'package:flutter/material.dart';
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

  // 🚀 NEW: Controllers for the Chat UI
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<Map<String, dynamic>> _activeMessages =
      []; // Temporary list to hold UI messages

  @override
  void initState() {
    super.initState();
    _fetchConversations();
  }

  Future<void> _fetchConversations() async {
    setState(() => _isLoading = true);
    try {
      final chats = await TrustMeService.instance.getConversations();
      if (mounted) {
        setState(() {
          _conversations = chats;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Failed to load conversations: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // 🚀 NEW: Function to handle sending a message
  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _selectedChat == null) return;

    // 1. Instantly show it in the UI (Optimistic UI update)
    setState(() {
      _activeMessages.add({
        'content': text,
        'isMe': true,
        'time': DateTime.now(),
      });
      _messageController.clear();
    });

    // Scroll to the bottom
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });

    // 2. Send it to the Gateway to be encrypted and routed to the peer
    try {
      await TrustMeService.instance.sendMessage(
        conversationId: _selectedChat!.id,
        content: text,
      );
    } catch (e) {
      debugPrint("Message failed to send: $e");
      // In a real app, you would mark the bubble with a red "!" icon here
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // ---------------------------------------------------------
        // LEFT PANEL: Conversation List
        // ---------------------------------------------------------
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
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: Colors.cyanAccent,
                        ),
                      )
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

        // ---------------------------------------------------------
        // RIGHT PANEL: Active Message Thread
        // ---------------------------------------------------------
        Expanded(
          child: _selectedChat == null
              ? _buildNoChatSelected()
              : _buildActiveChatArea(),
        ),
      ],
    );
  }

  // --- UI BUILDERS ---

  Widget _buildChatTile(ConversationSummary chat, bool isSelected) {
    return InkWell(
      onTap: () {
        setState(() {
          _selectedChat = chat;
          _activeMessages.clear(); // Clear messages when switching chats
        });
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
                (chat.contactUsername ?? "?")[0].toUpperCase(),
                style: const TextStyle(
                  color: Colors.cyanAccent,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    chat.contactUsername ?? "Unknown Contact",
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
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
                    decoration: const BoxDecoration(
                      color: Colors.cyanAccent,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      chat.unreadCount.toString(),
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
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
            const Text(
              "No Secure Chats",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Use the sidebar to generate a code and establish a new P2P connection.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
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
            Icon(
              Icons.lock_outline,
              size: 80,
              color: Colors.cyanAccent.withAlpha(50),
            ),
            const SizedBox(height: 24),
            const Text(
              "Guptik Trust Me (V1)",
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "Select a chat to view your end-to-end encrypted messages.\nKeys never leave this device.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
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
                  Text(
                    "Double Ratchet Protocol Active",
                    style: TextStyle(color: Colors.greenAccent, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 🚀 CHANGED: This is the real Message Thread UI!
  Widget _buildActiveChatArea() {
    return Container(
      color: const Color(0xFF0F172A),
      child: Column(
        children: [
          // 1. Top Chat Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: const BoxDecoration(
              color: Color(0xFF1E293B),
              border: Border(
                bottom: BorderSide(color: Colors.white12, width: 1),
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.cyanAccent.withAlpha(50),
                  child: Text(
                    (_selectedChat!.contactUsername ?? "?")[0].toUpperCase(),
                    style: const TextStyle(color: Colors.cyanAccent),
                  ),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _selectedChat!.contactUsername ?? "Unknown",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Row(
                      children: [
                        Icon(Icons.lock, color: Colors.cyanAccent, size: 12),
                        SizedBox(width: 4),
                        Text(
                          "E2E Encrypted Connection",
                          style: TextStyle(
                            color: Colors.cyanAccent,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.search, color: Colors.grey),
                  onPressed: () {},
                ),
                IconButton(
                  icon: const Icon(Icons.more_vert, color: Colors.grey),
                  onPressed: () {},
                ),
              ],
            ),
          ),

          // 2. Message List (The Bubbles)
          Expanded(
            child: _activeMessages.isEmpty
                ? Center(
                    child: Text(
                      "Send a message to start the secure chat.",
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(24),
                    itemCount: _activeMessages.length,
                    itemBuilder: (context, index) {
                      final msg = _activeMessages[index];
                      final isMe = msg['isMe'] as bool;

                      return Align(
                        alignment: isMe
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          constraints: const BoxConstraints(maxWidth: 400),
                          decoration: BoxDecoration(
                            color: isMe
                                ? const Color(0xFF006A60)
                                : const Color(0xFF1E293B),
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(16),
                              topRight: const Radius.circular(16),
                              bottomLeft: Radius.circular(isMe ? 16 : 0),
                              bottomRight: Radius.circular(isMe ? 0 : 16),
                            ),
                          ),
                          child: Text(
                            msg['content'],
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),

          // 3. Bottom Input Bar
          Container(
            padding: const EdgeInsets.all(16),
            color: const Color(0xFF1E293B),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.attach_file, color: Colors.grey),
                  onPressed: () {},
                ),
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    style: const TextStyle(color: Colors.white),
                    // Allow hitting "Enter" to send on Desktop!
                    onSubmitted: (_) => _sendMessage(),
                    decoration: InputDecoration(
                      hintText: "Type an encrypted message...",
                      hintStyle: TextStyle(color: Colors.grey.shade600),
                      filled: true,
                      fillColor: Colors.black26,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 14,
                      ),
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
      ),
    );
  }
}
