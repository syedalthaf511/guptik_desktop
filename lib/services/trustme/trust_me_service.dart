import 'dart:convert';
import 'dart:io'; // 🚀 ADDED: To read files natively from Windows
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TrustMeService {
  static TrustMeService? _instance;
  static TrustMeService get instance => _instance ??= TrustMeService._();
  TrustMeService._();

  WebSocketChannel? _wsChannel;
  final _listeners = <String, List<Function(Map<String, dynamic>)>>{};

  String get _gatewayUrl => 'http://localhost:55000';
  String get _wsUrl => '${_gatewayUrl.replaceFirst('http', 'ws')}/ws';

  // Connects to your local Docker Gateway
  Future<void> connect() async {
    _wsChannel = WebSocketChannel.connect(Uri.parse(_wsUrl));
    _wsChannel!.stream.listen(
      (message) {
        final event = jsonDecode(message as String) as Map<String, dynamic>;
        final type = event['type'] as String?;
        if (type != null) {
          _listeners[type]?.forEach((cb) => cb(event));
          _listeners['*']?.forEach((cb) => cb(event));
        }
      },
      onDone: () {
        Future.delayed(const Duration(seconds: 5), connect);
      },
    );
  }

  void forceUIConversationsRefresh() {
    if (_listeners['*'] != null) {
      _listeners['*']?.forEach((cb) => cb({'type': 'connection_established'}));
    }
  }

  // =========================================================
  // SECTION C: TRUST ME (V1) - Signaling & Local Finalisation
  // =========================================================

  // Node A generates the code AND starts the Background Radar
  Future<Map<String, dynamic>> generateHandshakeCode(
    String targetUsername,
  ) async {
    final response = await http.post(
      Uri.parse('$_gatewayUrl/internal/handshake/generate'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'target_username': targetUsername}),
    );

    if (response.statusCode != 200) throw Exception("Generation failed");

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final code = data['code'];

    try {
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser?.id;

      if (userId != null) {
        const secureStorage = FlutterSecureStorage();
        final myUsername =
            await secureStorage.read(key: 'current_username') ?? 'Peer_A';

        var myUrl = await secureStorage.read(key: 'public_url') ?? '';
        if (myUrl.isNotEmpty && !myUrl.startsWith('http')) {
          myUrl = 'https://$myUrl';
        }

        final myIdentityKey =
            await secureStorage.read(key: 'my_identity_pubkey') ?? '';
        final mySignedPreKey =
            await secureStorage.read(key: 'my_signed_prekey') ?? '';
        final mySignedPreKeyId =
            await secureStorage.read(key: 'my_signed_prekey_id') ?? '0';

        // 1. Upload Node A's details to Supabase
        await supabase.from('trust_me_secure_invites').insert({
          'creator_id': userId,
          'invite_code': code,
          'creator_username': myUsername,
          'creator_cloudflare_url': myUrl,
          'creator_identity_pubkey': myIdentityKey,
          'creator_signed_prekey': mySignedPreKey,
          // 🚀 CRITICAL FIX: Safe parsing so empty strings don't crash!
          'creator_signed_prekey_id': int.tryParse(mySignedPreKeyId) ?? 0,
        });

        print("✅ Invite logged. Launching Background Radar...");

        // 🚀 THE FIX: Start radar in the background so it doesn't freeze the app!
        _startActiveRadar(code);
      }
    } catch (e) {
      print("⚠️ Supabase Invite Insert Error: $e");
    }

    // Instantly returns the code to the UI while radar spins in the background!
    return data;
  }

  // 🚀 NEW BACKGROUND FUNCTION: Watches Supabase for 5 Full Minutes
  Future<void> _startActiveRadar(String code) async {
    final supabase = Supabase.instance.client;
    bool nodeBJoined = false;
    int attempts = 0;

    // Check every 3 seconds for up to 5 minutes (100 attempts)
    while (!nodeBJoined && attempts < 100) {
      await Future.delayed(const Duration(seconds: 3));
      attempts++;

      try {
        final checkResult = await supabase
            .from('trust_me_secure_invites')
            .select()
            .eq('invite_code', code)
            .maybeSingle();

        // If Node B's ID is suddenly in the row, they joined!
        if (checkResult != null && checkResult['connected_with'] != null) {
          nodeBJoined = true;
          print(
            "🎉 RADAR HIT! Node B Joined! Finalising Node A's local database...",
          );

          await finaliseHandshakeLocallyForNodeA(
            joinerGId: checkResult['connected_with'],
            joinerUsername: checkResult['joiner_username'] ?? 'Peer_B',
            joinerUrl: checkResult['joiner_cloudflare_url'],
            identityKey: checkResult['joiner_identity_pubkey'] ?? 'pending',
            signedPreKey: checkResult['joiner_signed_prekey'] ?? 'pending',
            signedPreKeyId: checkResult['joiner_signed_prekey_id'] ?? 0,
          );
        }
      } catch (e) {
        // Silently ignore temporary read errors while polling
      }
    }

    if (!nodeBJoined) {
      print("⚠️ Radar stopped. Node B never joined within 5 minutes.");
    }
  }

  // Node B claims the invite AND downloads Node A's Real Keys
  Future<Map<String, dynamic>> initiatePeerConnection({
    required String peerUrl,
    required String code,
    required String myUsername,
    required String myUrl,
  }) async {
    var target = peerUrl.trim();
    if (!target.startsWith('http')) target = 'https://$target';
    target = target.replaceAll(RegExp(r'/$'), '');

    try {
      final supabase = Supabase.instance.client;
      final myUserId = supabase.auth.currentUser?.id;

      if (myUserId != null) {
        final inviteResult = await supabase
            .from('trust_me_secure_invites')
            .select()
            .eq('invite_code', code)
            .maybeSingle();
        if (inviteResult == null)
          throw Exception("Invalid or expired invite code.");

        final creatorId = inviteResult['creator_id'];
        final creatorUsername = inviteResult['creator_username'] ?? 'Peer_A';

        var creatorUrl = inviteResult['creator_cloudflare_url'] ?? target;
        if (creatorUrl.isNotEmpty && !creatorUrl.startsWith('http')) {
          creatorUrl = 'https://$creatorUrl';
        }

        final creatorIdentity = inviteResult['creator_identity_pubkey'];
        final creatorPrekey = inviteResult['creator_signed_prekey'];
        final creatorPrekeyId = inviteResult['creator_signed_prekey_id'];

        const secureStorage = FlutterSecureStorage();
        final myIdentityKey =
            await secureStorage.read(key: 'my_identity_pubkey') ?? '';
        final mySignedPreKey =
            await secureStorage.read(key: 'my_signed_prekey') ?? '';
        final mySignedPreKeyId =
            await secureStorage.read(key: 'my_signed_prekey_id') ?? '0';

        // Node B uploads its own keys to Supabase so Node A's Radar can find them
        await supabase
            .from('trust_me_secure_invites')
            .update({
              'connected_with': myUserId,
              'joiner_username': myUsername,
              'joiner_cloudflare_url': myUrl,
              'joiner_identity_pubkey': myIdentityKey,
              'joiner_signed_prekey': mySignedPreKey,
              // 🚀 CRITICAL FIX: Safe parsing!
              'joiner_signed_prekey_id': int.tryParse(mySignedPreKeyId) ?? 0,
            })
            .eq('id', inviteResult['id']);

        // Pass Node A's real keys to the local Postgres Database
        await _finaliseConnectionLocally(
          counterpartGId: creatorId,
          counterpartUsername: creatorUsername,
          counterpartUrl: creatorUrl,
          identityKey: creatorIdentity ?? 'pending',
          signedPreKey: creatorPrekey ?? 'pending',
          // 🚀 CRITICAL FIX: Safe parsing for incoming Supabase data!
          signedPreKeyId: int.tryParse(creatorPrekeyId?.toString() ?? '0') ?? 0,
        );

        return {'status': 'linked_and_finalised_locally'};
      }
    } catch (e) {
      throw Exception("Supabase linking failed: $e");
    }
    throw Exception("Authentication error.");
  }

  // INTERNAL: Sends the real keys to the Docker Gateway
  Future<void> _finaliseConnectionLocally({
    required String counterpartGId,
    required String counterpartUsername,
    required String counterpartUrl,
    required String identityKey,
    required String signedPreKey,
    required int signedPreKeyId,
  }) async {
    final response = await http.post(
      Uri.parse('$_gatewayUrl/internal/finalise_connection'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'counterpart_guptik_id': counterpartGId,
        'counterpart_username': counterpartUsername,
        'counterpart_url': counterpartUrl,
        'contact_identity_pubkey': identityKey,
        'contact_signed_prekey': signedPreKey,
        'contact_signed_prekey_id': signedPreKeyId,
      }),
    );
    if (response.statusCode != 200) throw Exception("Local DB failure");
    forceUIConversationsRefresh();
  }

  Future<void> finaliseHandshakeLocallyForNodeA({
    required String joinerGId,
    required String joinerUsername,
    required String joinerUrl,
    String identityKey = 'pending_key_exchange',
    String signedPreKey = 'pending_signed_prekey',
    int signedPreKeyId = 0,
  }) async {
    await _finaliseConnectionLocally(
      counterpartGId: joinerGId,
      counterpartUsername: joinerUsername,
      counterpartUrl: joinerUrl,
      identityKey: identityKey,
      signedPreKey: signedPreKey,
      signedPreKeyId: signedPreKeyId,
    );
  }

  // Fetch conversations from local DB for side list
  Future<List<ConversationSummary>> getConversations() async {
    final response = await http.get(
      Uri.parse('$_gatewayUrl/internal/conversations'),
    );

    if (response.statusCode == 404) {
      return [];
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return (data['conversations'] as List)
        .map((c) => ConversationSummary.fromJson(c as Map<String, dynamic>))
        .toList();
  }

  // ─── Messaging ────────────────────────────────────────────────────────
  
  // Sends standard text messages (Uses JSON)
  Future<Map<String, dynamic>> sendMessage({
    required String conversationId,
    required String content,
    String contentType = 'text',
  }) async {
    final myUserId =
        Supabase.instance.client.auth.currentUser?.id ?? 'unknown_user';
    final myUsername =
        await const FlutterSecureStorage().read(key: 'current_username') ??
        'Me';

    final response = await http.post(
      Uri.parse('$_gatewayUrl/internal/message/send'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'conversation_id': conversationId,
        'content': content,
        'content_type': contentType,
        'sender_id': myUserId,
        'sender_username': myUsername, 
      }),
    );
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  // 🚀 BRAND NEW: Streams massive media files (Bypasses JSON, no memory freezing!)
  Future<Map<String, dynamic>> streamMediaFile({
    required String conversationId,
    required String filePath,
    required String contentType,
  }) async {
    final myUserId =
        Supabase.instance.client.auth.currentUser?.id ?? 'unknown_user';
    final myUsername =
        await const FlutterSecureStorage().read(key: 'current_username') ??
        'Me';

    final file = File(filePath);
    final ext = filePath.split('.').last.toLowerCase();
    final length = await file.length();

    // 1. Create a raw StreamedRequest pointing to our new Docker endpoint
    final request = http.StreamedRequest(
      'POST',
      Uri.parse('$_gatewayUrl/internal/message/stream_send/$conversationId/$ext'),
    );

    // 2. Add the tracking headers so Docker knows who is sending it
    request.headers['x-sender-id'] = myUserId;
    request.headers['x-sender-username'] = myUsername;
    request.headers['x-content-type'] = contentType;
    request.contentLength = length;

    // 3. 🚀 The Magic: Pipe the file directly from the hard drive to the network!
    file.openRead().listen(
      request.sink.add,
      onDone: request.sink.close,
      onError: request.sink.addError,
    );

    // 4. Send and wait for the Gateway to say it was delivered
    final response = await request.send();
    final responseBody = await response.stream.bytesToString();

    if (response.statusCode != 200) {
      throw Exception("Stream Upload Failed: $responseBody");
    }

    return jsonDecode(responseBody) as Map<String, dynamic>;
  }

  // 🚀 UPDATED: Crash-proof message fetching!
  Future<List<Map<String, dynamic>>> getMessages(String conversationId) async {
    try {
      final response = await http.get(
        Uri.parse('$_gatewayUrl/internal/messages/$conversationId'),
      );

      // If Docker is rebooting or crashing, safely return an empty list instead of panicking
      if (response.statusCode != 200 || response.body.isEmpty) return [];

      final data = jsonDecode(response.body);
      if (data == null || data['messages'] == null) return [];

      return (data['messages'] as List).cast<Map<String, dynamic>>();
    } catch (e) {
      return []; // Safety net to prevent UI crashing
    }
  }

  // 🚀 THE FIX: Added the method to tell the local Gateway to clear the unread badge!
  Future<void> markConversationAsRead(String conversationId) async {
    try {
      await http.post(
        Uri.parse('$_gatewayUrl/internal/conversation/$conversationId/read'),
      );
    } catch (e) {
      print("Could not mark as read: $e");
    }
  }
}

class ConversationSummary {
  final String id;
  final String type;
  final String? contactUsername;
  final String? customUsername;
  final String? lastMessagePreview;
  final DateTime? lastMessageAt;
  
  int unreadCount; // 🚀 THE FIX: Removed 'final' so we can instantly set it to 0!
  
  final bool isOnline;
  final bool isPinned;
  final bool isMuted;

  // 🚀 MAGIC HELPER: If customUsername exists, show it. Otherwise, show the default username!
  String get displayName {
    if (customUsername != null && customUsername!.trim().isNotEmpty) {
      return customUsername!;
    }
    return contactUsername ?? "Unknown";
  }

  ConversationSummary({
    required this.id,
    required this.type,
    this.contactUsername,
    this.customUsername,
    this.lastMessagePreview,
    this.lastMessageAt,
    required this.unreadCount,
    required this.isOnline,
    required this.isPinned,
    required this.isMuted,
  });

  factory ConversationSummary.fromJson(Map<String, dynamic> json) =>
      ConversationSummary(
        id: json['id'] as String,
        type: json['type'] as String,
        contactUsername: json['contact_username'] as String?,
        customUsername: json['custom_username'] as String?,
        lastMessagePreview: json['last_message_preview'] as String?,
        lastMessageAt: json['last_message_at'] != null
            ? DateTime.parse(json['last_message_at'] as String)
            : null,
        unreadCount: (json['unread_count'] as int?) ?? 0,
        isOnline: (json['is_online'] as bool?) ?? false,
        isPinned: (json['is_pinned'] as bool?) ?? false,
        isMuted: (json['is_muted'] as bool?) ?? false,
      );
}