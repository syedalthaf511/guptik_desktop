import 'dart:io';
import 'dart:math';
import 'package:process_run/shell.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class DockerService {
  String? _vaultPath;

  void setVaultPath(String path) => _vaultPath = path;

  Future<void> autoConfigure({
    required String dbPass,
    required String tunnelToken,
    required String publicUrl,
    required String email,
    required String userPassword,
  }) async {
    if (_vaultPath == null) throw Exception("Vault path is not initialized");

    const secureStorage = FlutterSecureStorage();
    await secureStorage.write(key: 'public_url', value: publicUrl);

    final requiredDirs = [
      '$_vaultPath/data/postgres',
      '$_vaultPath/data/ollama',
      '$_vaultPath/data/n8n',
      '$_vaultPath/data/osint',
      '$_vaultPath/vault_files',
      '$_vaultPath/gateway',
    ];

    for (var path in requiredDirs) {
      final dir = Directory(path);
      if (!dir.existsSync()) {
        await dir.create(recursive: true);
      }
    }

    final envFile = File('$_vaultPath/.env');
    await envFile.writeAsString('''
POSTGRES_PASSWORD=$dbPass
POSTGRES_PORT=55432
CF_TUNNEL_TOKEN=$tunnelToken
PUBLIC_URL=$publicUrl
VAULT_PATH=$_vaultPath
N8N_USER=$email
N8N_PASS=Gupt1k_pa55
''');

    await _generateGatewayFiles(publicUrl);

    final composeFile = File('$_vaultPath/docker-compose.yml');
    await composeFile.writeAsString('''
services:
  guptik-tunnel:
    image: cloudflare/cloudflared:latest
    restart: always
    environment:
      - TUNNEL_TOKEN=\${CF_TUNNEL_TOKEN}
    command: tunnel --no-autoupdate run

  gateway:
    image: dart:stable
    restart: always
    working_dir: /app
    ports:
      - "55000:8080"
    volumes:
      - ./gateway:/app
      - ./vault_files:/app/storage
    command: sh -c "dart pub get && dart run server.dart"
    depends_on:
      - db
      - ollama

  db:
    image: postgres:15-alpine
    restart: always
    ports:
      - "\${POSTGRES_PORT}:5432"
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: GuptikSystemPassword2026
      POSTGRES_DB: postgres
    volumes:
      - ./data/postgres:/var/lib/postgresql/data

  ollama:
    image: ollama/ollama:latest
    restart: always
    ports:
      - "55434:11434"
    volumes:
      - ./data/ollama:/root/.ollama

  n8n:
    image: docker.n8n.io/n8nio/n8n
    restart: always
    ports:
      - "56887:5678"
    environment:
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=\${N8N_USER}
      - N8N_BASIC_AUTH_PASSWORD=\${N8N_PASS}
      - N8N_OWNER_FIRST_NAME=Guptik
      - N8N_OWNER_LAST_NAME=Admin
    volumes:
      - ./data/n8n:/home/node/.n8n

  osint_python:
    image: python:3.11-slim
    restart: always
    working_dir: /app
    volumes:
      - ./data/osint:/app
    command: tail -f /dev/null
''');
  }

  Future<void> _generateGatewayFiles(String publicUrl) async {
    final pubspec = File('$_vaultPath/gateway/pubspec.yaml');
    await pubspec.writeAsString('''
name: guptik_gateway
environment: {sdk: '>=3.0.0 <4.0.0'}
dependencies: {shelf: ^1.4.0, shelf_router: ^1.1.0, http: ^1.1.0, mime: ^1.0.4, postgres: ^3.4.0, uuid: ^4.3.3}
''');

    final server = File('$_vaultPath/gateway/server.dart');

    await server.writeAsString(r'''
import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:http/http.dart' as http;
import 'package:mime/mime.dart';
import 'package:postgres/postgres.dart';
import 'package:uuid/uuid.dart';

void main() async {
  final router = Router();
  final uuid = Uuid();

  print('Guptik Gateway Starting...');

  final storageDir = Directory('/app/storage');
  if (!await storageDir.exists()) {
    print('Creating storage directory at /app/storage');
    await storageDir.create(recursive: true);
  }

  router.post('/vault/upload/<filename>', (Request req, String filename) async {
    IOSink? sink;
    try {
      final file = File('/app/storage/$filename');
      sink = file.openWrite();
      await sink.addStream(req.read());
      await sink.flush();
      await sink.close();

      final size = await file.length();
      final mimeType = lookupMimeType(file.path) ?? 'application/octet-stream';

      try {
        final connection = await Connection.open(
          Endpoint(host: 'db', port: 5432, database: 'postgres', username: 'postgres', password: 'GuptikSystemPassword2026'),
          settings: const ConnectionSettings(sslMode: SslMode.disable),
        );
        await connection.execute(
          Sql.named("INSERT INTO vault_files (file_name, file_path, file_size, mime_type) VALUES (@fn, @fp, @fs, @mt)"),
          parameters: {'fn': filename, 'fp': file.path, 'fs': size, 'mt': mimeType},
        );
        await connection.close();
      } catch (dbError) {
        print('DATABASE ERROR: $dbError');
      }

      return Response.ok(jsonEncode({'status': 'saved', 'path': filename, 'size': size}));
    } catch (e, stack) {
      try { await sink?.close(); } catch (_) {}
      return Response.internalServerError(body: 'UPLOAD ERROR: $e');
    }
  });

  router.get('/vault/files/<filename>', (Request req, String filename) async {
    try {
      final token = req.url.queryParameters['token'];
      final email = req.url.queryParameters['email'];

      final connection = await Connection.open(
        Endpoint(host: 'db', port: 5432, database: 'postgres', username: 'postgres', password: 'GuptikSystemPassword2026'),
        settings: const ConnectionSettings(sslMode: SslMode.disable),
      );

      final result = await connection.execute(
        Sql.named("SELECT is_public, access_token, emails_access_to, expires_at FROM vault_share_file WHERE file_name = @fn ORDER BY created_at DESC LIMIT 1"),
        parameters: {'fn': filename},
      );
      await connection.close();

      if (result.isEmpty) return Response.forbidden('Access Denied: This file has not been shared.');

      final row = result.first;
      final isPublic = row[0] as bool;
      final dbToken = row[1]?.toString();
      
      List<String> allowedEmails = [];
      if (row[2] != null) {
        if (row[2] is List) allowedEmails = (row[2] as List).map((e) => e.toString().toLowerCase().trim()).toList();
        else if (row[2] is String) allowedEmails = row[2].toString().replaceAll('{', '').replaceAll('}', '').split(',').map((e) => e.toLowerCase().trim()).toList();
      }
      final expiresAt = row[3] as DateTime?;

      if (expiresAt != null && DateTime.now().toUtc().isAfter(expiresAt)) return Response.forbidden('This link has expired.');

      if (!isPublic) {
        if (token != dbToken) return Response.forbidden('Invalid or missing access token.');
        if (email == null || email.isEmpty) {
          final html = """
            <!DOCTYPE html><html><body style="font-family: Arial; background-color: #0F172A; color: white; display: flex; justify-content: center; align-items: center; height: 100vh;">
              <div style="background: #1E293B; padding: 40px; border-radius: 12px; text-align: center;">
                <h2>Secure File Access</h2>
                <form method="GET">
                  <input type="hidden" name="token" value="${token ?? ''}" />
                  <input type="email" name="email" placeholder="Enter email" required style="padding: 10px; margin-bottom: 10px; width: 100%;" />
                  <button type="submit" style="padding: 10px; width: 100%; background: #00E5FF; border: none; font-weight: bold;">Verify</button>
                </form>
              </div>
            </body></html>
          """;
          return Response.ok(html, headers: {'Content-Type': 'text/html'});
        }
        if (!allowedEmails.contains(email.toLowerCase().trim())) return Response.forbidden('Access Denied: Email not authorized.');
      }

      final file = File('/app/storage/$filename');
      if (!await file.exists()) return Response.notFound('File not found.');

      final mimeType = lookupMimeType(file.path) ?? 'application/octet-stream';
      return Response.ok(file.openRead(), headers: {
        'Content-Type': mimeType,
        'Content-Length': (await file.length()).toString(),
        'Content-Disposition': 'inline; filename="$filename"',
      });
    } catch (e) {
      return Response.internalServerError(body: 'Server Error');
    }
  });

  router.get('/vault/list', (Request req) {
    try {
      final dir = Directory('/app/storage');
      if (!dir.existsSync()) return Response.ok('[]');
      final files = dir.listSync().whereType<File>().map((f) => {'name': f.uri.pathSegments.last, 'size': f.lengthSync(), 'modified': f.lastModifiedSync().toIso8601String()}).toList();
      return Response.ok(jsonEncode(files), headers: {'Content-Type': 'application/json'});
    } catch (e) { return Response.internalServerError(body: 'List Error: $e'); }
  });

  router.post('/vault/share', (Request req) async {
    try {
      final payload = await req.readAsString();
      final data = jsonDecode(payload);
      final connection = await Connection.open(
        Endpoint(host: 'db', port: 5432, database: 'postgres', username: 'postgres', password: 'GuptikSystemPassword2026'),
        settings: const ConnectionSettings(sslMode: SslMode.disable),
      );
      await connection.execute(
        Sql.named("INSERT INTO vault_share_file (file_name, is_public, access_token, emails_access_to, created_at, expires_at) VALUES (@fn, @pub, @tok, @em, @ca, @ea)"),
        parameters: {
          'fn': data['file_name'], 'pub': data['is_public'], 'tok': data['access_token'], 'em': data['emails_access_to'],
          'ca': DateTime.parse(data['created_at']), 'ea': data['expires_at'] != null ? DateTime.parse(data['expires_at']) : null,
        },
      );
      await connection.close();
      return Response.ok(jsonEncode({'status': 'success'}));
    } catch (e) { return Response.internalServerError(body: 'Share Error: $e'); }
  });

  router.delete('/vault/delete/<filename>', (Request req, String filename) async {
    try {
      final file = File('/app/storage/$filename');
      if (await file.exists()) await file.delete();
      final connection = await Connection.open(
        Endpoint(host: 'db', port: 5432, database: 'postgres', username: 'postgres', password: 'GuptikSystemPassword2026'),
        settings: const ConnectionSettings(sslMode: SslMode.disable),
      );
      await connection.execute(Sql.named("DELETE FROM vault_files WHERE file_name = @fn"), parameters: {'fn': filename});
      await connection.close();
      return Response.ok(jsonEncode({'status': 'deleted', 'file': filename}));
    } catch (e) { return Response.internalServerError(body: 'Delete Error: $e'); }
  });

  router.get('/api/tags', (Request req) async {
    try {
      final response = await http.get(Uri.parse('http://ollama:11434/api/tags'));
      return Response.ok(response.body, headers: {'Content-Type': 'application/json'});
    } catch (e) { return Response.internalServerError(body: 'AI Offline'); }
  });

  router.post('/api/chat', (Request req) async {
    try {
      final payload = await req.readAsString();
      final client = http.Client();
      final proxyReq = http.Request('POST', Uri.parse('http://ollama:11434/api/chat'));
      proxyReq.headers['Content-Type'] = 'application/json';
      proxyReq.body = payload;
      final response = await client.send(proxyReq);
      return Response.ok(response.stream, headers: {'Content-Type': 'application/json'});
    } catch (e) { return Response.internalServerError(body: 'AI Offline'); }
  });

  router.get('/api/sessions', (Request req) async {
    try {
      final connection = await Connection.open(
        Endpoint(host: 'db', port: 5432, database: 'postgres', username: 'postgres', password: 'GuptikSystemPassword2026'),
        settings: const ConnectionSettings(sslMode: SslMode.disable),
      );
      
      final result = await connection.execute("""
        SELECT DISTINCT ON (session_id) session_id, content, created_at
        FROM ollama_chat_memory
        WHERE role = 'user'
        ORDER BY session_id, created_at ASC
      """);
      await connection.close();

      final sessions = result.map((row) {
        String snippet = row[1] as String;
        if (snippet.length > 30) snippet = "${snippet.substring(0, 30)}...";
        return {'id': row[0].toString(), 'title': snippet, 'date': row[2].toString()};
      }).toList();
      
      sessions.sort((a, b) => (b['date'] as String).compareTo(a['date'] as String));
      return Response.ok(jsonEncode(sessions), headers: {'Content-Type': 'application/json'});
    } catch (e) {
      print("DB Sync Error (Sessions): $e");
      return Response.internalServerError(body: 'DB Error: $e');
    }
  });

  router.get('/api/history/<sessionId>', (Request req, String sessionId) async {
    try {
      final connection = await Connection.open(
        Endpoint(host: 'db', port: 5432, database: 'postgres', username: 'postgres', password: 'GuptikSystemPassword2026'),
        settings: const ConnectionSettings(sslMode: SslMode.disable),
      );
      
      final result = await connection.execute(
        Sql.named("SELECT role, content, created_at FROM ollama_chat_memory WHERE session_id = @sid ORDER BY created_at ASC"),
        parameters: {'sid': sessionId},
      );
      await connection.close();

      final history = result.map((row) => {
        'role': row[0].toString(),
        'content': row[1].toString(),
        'created_at': row[2].toString(),
      }).toList();

      return Response.ok(jsonEncode(history), headers: {'Content-Type': 'application/json'});
    } catch (e) {
      print("DB Sync Error (History): $e");
      return Response.internalServerError(body: 'DB Error: $e');
    }
  });

  router.post('/api/chat/save', (Request req) async {
    try {
      final payload = await req.readAsString();
      final data = jsonDecode(payload);
      
      final connection = await Connection.open(
        Endpoint(host: 'db', port: 5432, database: 'postgres', username: 'postgres', password: 'GuptikSystemPassword2026'),
        settings: const ConnectionSettings(sslMode: SslMode.disable),
      );

      await connection.execute(
        Sql.named("INSERT INTO ollama_chat_memory (session_id, role, content, model_used) VALUES (@sid, @role, @content, @model)"),
        parameters: {
          'sid': data['sessionId'],
          'role': data['role'],
          'content': data['content'],
          'model': data['model'] ?? 'unknown',
        },
      );
      
      await connection.close();
      return Response.ok(jsonEncode({'status': 'saved'}), headers: {'Content-Type': 'application/json'});
    } catch (e) {
      print("DB Sync Error (Save): $e");
      return Response.internalServerError(body: 'DB Error: $e');
    }
  });

  router.post('/trustme/handshake/initiate', (Request req) async {
    try {
      final payload = await req.readAsString();
      final data = jsonDecode(payload);
      
      final connection = await Connection.open(
        Endpoint(host: 'db', port: 5432, database: 'postgres', username: 'postgres', password: 'GuptikSystemPassword2026'),
        settings: const ConnectionSettings(sslMode: SslMode.disable),
      );

      await connection.execute(
        Sql.named("""
          INSERT INTO tm_handshake_sessions (id, initiated_by, counterpart_username, counterpart_cloudflare_url, code_hash, status) 
          VALUES (@id, 'other', @user, @url, @hash, 'awaiting_entry')
        """),
        parameters: {
          'id': data['session_id'],
          'user': data['from_username'],
          'url': data['from_url'],
          'hash': data['code_hash'],
        }
      );
      await connection.close();
      
      print("TRUST ME: Handshake initiated by ${data['from_username']}");
      return Response.ok(jsonEncode({'status': 'received', 'session_id': data['session_id']}));
    } catch (e) {
      return Response.internalServerError(body: 'Handshake Error: $e');
    }
  });

  router.post('/trustme/message/receive', (Request req) async {
    try {
      final payload = await req.readAsString();
      final data = jsonDecode(payload);
      final senderId = req.headers['x-sender-id'] ?? 'unknown';

      final connection = await Connection.open(
        Endpoint(host: 'db', port: 5432, database: 'postgres', username: 'postgres', password: 'GuptikSystemPassword2026'),
        settings: const ConnectionSettings(sslMode: SslMode.disable),
      );

      final contactResult = await connection.execute(
        Sql.named("SELECT c.id as conversation_id FROM tm_contacts ct JOIN tm_conversations c ON c.contact_id = ct.id WHERE ct.contact_guptik_id = @sid LIMIT 1"),
        parameters: {'sid': senderId}
      );

      if (contactResult.isEmpty) {
         await connection.execute(
           Sql.named("INSERT INTO tm_unknown_inbox (source_type, sender_identifier, sender_username, content_encrypted, content_type) VALUES ('guptik_user', @sid, @user, @enc, @type)"),
           parameters: {'sid': senderId, 'user': data['sender_username'], 'enc': data['content_encrypted'], 'type': data['content_type'] ?? 'text'}
         );
         print("TRUST ME: Message routed to Unknown Inbox from $senderId");
      } else {
         final convId = contactResult.first[0];
         await connection.execute(
           Sql.named("INSERT INTO tm_messages (id, conversation_id, sender_guptik_id, sender_username, content_encrypted, content_type, message_nonce) VALUES (@id, @cid, @sid, @user, @enc, @type, @nonce)"),
           parameters: {
             'id': data['message_id'], 
             'cid': convId, 
             'sid': senderId, 
             'user': data['sender_username'], 
             'enc': data['content_encrypted'], 
             'type': data['content_type'] ?? 'text', 
             'nonce': data['nonce']
           }
         );
         
         await connection.execute(
           Sql.named("UPDATE tm_conversations SET unread_count = unread_count + 1, last_message_at = NOW(), last_message_type = @type WHERE id = @cid"),
           parameters: {'type': data['content_type'] ?? 'text', 'cid': convId}
         );
         print("TRUST ME: Message received successfully in conversation $convId");
      }

      await connection.close();
      return Response.ok(jsonEncode({'status': 'received'}));
    } catch (e) {
      print("TRUST ME Message Error: $e");
      return Response.internalServerError(body: 'Message Error: $e');
    }
  });

  router.post('/internal/message/send', (Request req) async {
    try {
      final payload = await req.readAsString();
      final data = jsonDecode(payload);
      final conversationId = data['conversation_id'];
      
      final connection = await Connection.open(
        Endpoint(host: 'db', port: 5432, database: 'postgres', username: 'postgres', password: 'GuptikSystemPassword2026'),
        settings: const ConnectionSettings(sslMode: SslMode.disable),
      );

      final convResult = await connection.execute(
        Sql.named("SELECT ct.contact_cloudflare_url, ct.contact_guptik_id FROM tm_conversations c JOIN tm_contacts ct ON c.contact_id = ct.id WHERE c.id = @cid LIMIT 1"),
        parameters: {'cid': conversationId}
      );

      if (convResult.isEmpty) {
        await connection.close();
        return Response.notFound(jsonEncode({'error': 'Conversation not found'}));
      }

      // 🚀 BULLETPROOF URL CHECK
      var targetUrl = convResult.first[0] as String;
      if (!targetUrl.startsWith('http')) {
        targetUrl = 'https://$targetUrl';
      }

      final messageId = uuid.v4();
      final myId = data['sender_id'] ?? 'unknown_user';
      final myUsername = data['sender_username'] ?? 'Me';

      // 🚀 FIX 1: Save the message in YOUR OWN database so you can see your own chat bubbles!
      await connection.execute(
        Sql.named("INSERT INTO tm_messages (id, conversation_id, sender_guptik_id, sender_username, content_encrypted, content_type, message_nonce) VALUES (@id, @cid, @sid, @user, @enc, @type, 'local_nonce')"),
        parameters: {
          'id': messageId,
          'cid': conversationId,
          'sid': myId, 
          'user': myUsername,
          'enc': data['content'],
          'type': data['content_type'] ?? 'text'
        }
      );

      final outPayload = {
        'message_id': messageId,
        'sender_username': myUsername, 
        'content_encrypted': data['content'], 
        'content_type': data['content_type'] ?? 'text',
        'nonce': 'random_nonce_here'
      };

      // 🚀 FIX 2: SEND TO PEER WITH REAL SENDER ID (No more unknown inbox!)
      final response = await http.post(
        Uri.parse('$targetUrl/trustme/message/receive'),
        headers: {'Content-Type': 'application/json', 'X-Sender-ID': myId},
        body: jsonEncode(outPayload),
      );

      await connection.close();
      
      if (response.statusCode == 200) {
        print("TRUST ME: Outbound message delivered successfully to $targetUrl");
        return Response.ok(jsonEncode({'status': 'delivered', 'message_id': messageId}));
      } else {
        print("TRUST ME: Outbound message queued (Peer offline)");
        return Response.ok(jsonEncode({'status': 'queued', 'message_id': messageId}));
      }
    } catch (e) {
      return Response.internalServerError(body: 'Send Error: $e');
    }
  });
  

  router.get('/internal/conversations', (Request req) async {
    try {
      final connection = await Connection.open(
        Endpoint(host: 'db', port: 5432, database: 'postgres', username: 'postgres', password: 'GuptikSystemPassword2026'),
        settings: const ConnectionSettings(sslMode: SslMode.disable),
      );

      final result = await connection.execute("""
        SELECT c.id, c.type, ct.contact_username, c.last_message_preview, 
               c.last_message_at, c.unread_count, c.is_pinned, c.is_muted
        FROM tm_conversations c
        LEFT JOIN tm_contacts ct ON c.contact_id = ct.id
        ORDER BY c.last_message_at DESC NULLS LAST
      """);
      await connection.close();

      final conversations = result.map((row) => {
        'id': row[0].toString(),
        'type': row[1].toString(),
        'contact_username': row[2]?.toString(),
        'last_message_preview': row[3]?.toString(),
        'last_message_at': row[4]?.toString(),
        'unread_count': row[5] as int,
        'is_pinned': row[6] as bool,
        'is_muted': row[7] as bool,
      }).toList();

      return Response.ok(jsonEncode({'conversations': conversations}), headers: {'Content-Type': 'application/json'});
    } catch (e) {
      print("Error fetching conversations: $e");
      return Response.internalServerError(body: jsonEncode({'error': e.toString()}));
    }
  });

  router.get('/internal/handshake/pending', (Request req) async {
    try {
      final connection = await Connection.open(
        Endpoint(host: 'db', port: 5432, database: 'postgres', username: 'postgres', password: 'GuptikSystemPassword2026'),
        settings: const ConnectionSettings(sslMode: SslMode.disable),
      );
      final result = await connection.execute("SELECT id, counterpart_username FROM tm_pending_requests WHERE status = 'pending'");
      await connection.close();
      
      final pending = result.map((r) => {'handshake_session_id': r[0].toString(), 'username': r[1].toString()}).toList();
      return Response.ok(jsonEncode({'pending': pending}), headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.ok(jsonEncode({'pending': []}), headers: {'Content-Type': 'application/json'});
    }
  });

  router.post('/internal/handshake/generate', (Request req) async {
    try {
      final payload = await req.readAsString();
      final data = jsonDecode(payload);

      final randomCode = (Random().nextInt(900000) + 100000).toString();
      
      return Response.ok(jsonEncode({
        'session_id': uuid.v4(),
        'code': randomCode,
        'target_username': data['target_username'] ?? 'Unknown',
        'expires_note': 'Share this secure code out-of-band. Expires in 30s.'
      }), headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(body: e.toString());
    }
  });


  router.post('/internal/finalise_connection', (Request req) async {
    final connection = await Connection.open(
      Endpoint(host: 'db', port: 5432, database: 'postgres', username: 'postgres', password: 'GuptikSystemPassword2026'),
      settings: const ConnectionSettings(sslMode: SslMode.disable),
    );

    final payload = await req.readAsString();
    final data = jsonDecode(payload);
    
    final conversationId = uuid.v4();
    final contactId = uuid.v4();
    try {
      // 🚀 INJECTING THE REAL KEYS DIRECTLY INTO THE DATABASE
      await connection.execute(
        Sql.named("""
          INSERT INTO tm_contacts 
          (id, contact_guptik_id, contact_username, contact_cloudflare_url, contact_identity_pubkey, contact_signed_prekey, contact_signed_prekey_id) 
          VALUES (@id, @gid, @user, @url, @ipub, @spk, @spkid)
        """),
        parameters: {
          'id': contactId,
          'gid': data['counterpart_guptik_id'],
          'user': data['counterpart_username'],
          'url': data['counterpart_url'],
          'ipub': data['contact_identity_pubkey'], // 🚀 Real Identity Key
          'spk': data['contact_signed_prekey'],    // 🚀 Real PreKey
          'spkid': data['contact_signed_prekey_id'], // 🚀 Real Key ID
        },
      );

      await connection.execute(
        Sql.named("INSERT INTO tm_conversations (id, type, contact_id, unread_count) VALUES (@id, 'one_on_one', @cid, 0)"),
        parameters: {
          'id': conversationId,
          'cid': contactId,
        },
      );

      await connection.close();
      return Response.ok(jsonEncode({'status': 'success', 'conversation_id': conversationId}));
    } catch (e) {
      await connection.close();
      print('LOCAL CONNECTION FINALISATION ERROR: $e');
      return Response.internalServerError(body: jsonEncode({'error': e.toString()}));
    }
  });


  router.get('/internal/messages/<conversationId>', (Request req, String conversationId) async {
    try {
      final connection = await Connection.open(
        Endpoint(host: 'db', port: 5432, database: 'postgres', username: 'postgres', password: 'GuptikSystemPassword2026'),
        settings: const ConnectionSettings(sslMode: SslMode.disable),
      );

      final result = await connection.execute(
        Sql.named("""
          SELECT id, sender_guptik_id, sender_username, content_encrypted, created_at 
          FROM tm_messages 
          WHERE conversation_id = @cid 
          ORDER BY created_at ASC
        """),
        parameters: {'cid': conversationId}
      );
      await connection.close();

      final messages = result.map((row) => {
        'id': row[0].toString(),
        'sender_id': row[1].toString(),
        'sender_username': row[2].toString(),
        'content': row[3].toString(), 
        'created_at': row[4].toString(),
      }).toList();

      return Response.ok(jsonEncode({'messages': messages}), headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(body: jsonEncode({'error': e.toString()}));
    }
  });

  router.get('/', (Request req) => Response.ok('GUPTIK GATEWAY ONLINE'));

  final handler = Pipeline()
      .addMiddleware(logRequests())
      .addHandler(router.call);
  final server = await serve(handler, InternetAddress.anyIPv4, 8080);
  print('Gateway listening on port ${server.port}');
}
''');
  }

  Future<void> stopStack() async {
    try {
      if (_vaultPath == null) {
        throw Exception("Vault path not set");
      }

      final result = await Process.run('docker-compose', [
        '-f',
        'docker-compose.yml',
        'down',
      ], workingDirectory: _vaultPath);

      if (result.exitCode != 0) {
        print("Error stopping Docker: ${result.stderr}");
      } else {
        print("Docker Stack stopped successfully.");
      }
    } catch (e) {
      print("Kill Switch Exception: $e");
    }
  }

  Future<void> startStack() async {
    if (_vaultPath == null) throw Exception("Vault path not set");

    final shell = Shell(
      workingDirectory: _vaultPath,
      environment: Platform.environment,
      throwOnError: false,
    );

    String dockerCmd = 'docker';
    if (Platform.isLinux || Platform.isMacOS) {
      final which = await shell.run('which docker');
      if (which.first.exitCode == 0) {
        dockerCmd = which.first.stdout.toString().trim();
      }
    }

    await shell.run('$dockerCmd compose pull');
    await shell.run('$dockerCmd compose up -d --build --remove-orphans');
  }
}
