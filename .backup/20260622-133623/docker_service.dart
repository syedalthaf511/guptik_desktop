import 'dart:io';
import 'dart:math';
import 'package:process_run/shell.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class DockerService {
  // 🚀 SINGLETON PATTERN FIX
  static final DockerService _instance = DockerService._internal();
  factory DockerService() => _instance;
  DockerService._internal();

  String? _vaultPath;
  String? _activeTunnelUrl;

  // --- PASTE IT HERE ---
  Future<String> getActiveTunnelUrl() async {
    const secureStorage = FlutterSecureStorage();
    String? storedUrl = await secureStorage.read(key: 'public_url');
    return storedUrl ?? "your-tunnel-url-here.guptik.myqrmart.com";
  }

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

    // 🚀 ADD THIS LINE: Save the dynamic installation path!
    await secureStorage.write(key: 'vault_path', value: _vaultPath);

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
    build: ./gateway
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

    final dockerfile = File('$_vaultPath/gateway/Dockerfile');
    await dockerfile.writeAsString('''
FROM dart:stable
# 🚀 THE INSTANT SPEED HACK: Copies a pre-compiled static binary in seconds 
COPY --from=mwader/static-ffmpeg:6.1.1 /ffmpeg /usr/local/bin/
''');

    final server = File('$_vaultPath/gateway/server.dart');

    await server.writeAsString(r'''
import 'dart:io';
import 'dart:async'; 
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

  router.get('/internal/media/<filename>', (Request req, String filename) async {
    try {
      final file = File('/app/storage/$filename');
      if (!await file.exists()) return Response.notFound('File not found.');
      
      final fileSize = await file.length();
      final mimeType = lookupMimeType(file.path) ?? 'video/mp4'; 
      final rangeHeader = req.headers['range'];

      if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
        final parts = rangeHeader.substring(6).split('-');
        final start = int.tryParse(parts[0]) ?? 0;
        final end = parts.length > 1 && parts[1].isNotEmpty 
            ? int.tryParse(parts[1]) ?? fileSize - 1 
            : fileSize - 1;

        if (start >= fileSize) {
          return Response(416, headers: {'Content-Range': 'bytes */$fileSize'});
        }

        final contentLength = end - start + 1;
        final stream = file.openRead(start, end + 1);

        return Response(
          206, 
          body: stream,
          headers: {
            'Content-Type': mimeType,
            'Content-Length': contentLength.toString(),
            'Content-Range': 'bytes $start-$end/$fileSize',
            'Accept-Ranges': 'bytes',
          },
        );
      } else {
        return Response.ok(file.openRead(), headers: {
          'Content-Type': mimeType,
          'Content-Length': fileSize.toString(),
          'Accept-Ranges': 'bytes',
        });
      }
    } catch (e) {
      return Response.internalServerError(body: 'Media Error');
    }
  });

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

  // =================================================================
  // ☁️ GUPTIK SECURE SYNC LOOP ENDPOINTS
  // =================================================================
  router.get('/vault/get_synced_ids', (Request request) async {
    try {
      final directory = Directory('/app/storage');
      List<String> fileNames = [];
      if (directory.existsSync()) {
        for (var entity in directory.listSync()) {
          if (entity is File) {
            fileNames.add(entity.path.split('/').last);
          }
        }
      }
      return Response.ok(jsonEncode(fileNames), headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(body: 'Error reading storage catalog: $e');
    }
  });

  router.get('/vault/system-folder/<type>', (Request request, String type) async {
    try {
      final connection = await Connection.open(
        Endpoint(host: 'db', port: 5432, database: 'postgres', username: 'postgres', password: 'GuptikSystemPassword2026'),
        settings: const ConnectionSettings(sslMode: SslMode.disable),
      );

      Result? result;
      // 🚀 THE FIX: Swapped out inner single-triple quotes for standard double quotes to preserve code layout structure limits cleanly
      if (type == 'posted') {
        result = await connection.execute(
          "SELECT id::text, title, file_path FROM user_videos WHERE is_deleted = false ORDER BY upload_timestamp DESC"
        );
      } else if (type == 'saved') {
        result = await connection.execute(
          "SELECT v.id::text, v.title, v.file_path FROM saved_videos s JOIN user_videos v ON s.video_id = v.id::text ORDER BY s.saved_timestamp DESC"
        );
      }
      await connection.close();

      final List<Map<String, dynamic>> loadedItems = [];
      if (result != null) {
        for (final row in result) {
          final String videoId = row[0].toString();
          final String title = row[1].toString();
          final String rawPath = row[2].toString();
          final String parsedName = rawPath.split(RegExp(r'[/\\]')).last;

          int sizeBytes = 0;
          try {
            final diskFile = File('/app/storage/$parsedName');
            if (diskFile.existsSync()) sizeBytes = diskFile.lengthSync();
          } catch (_) {}

          loadedItems.add({
            'video_id': videoId,
            'title': title,
            'size_bytes': sizeBytes,
          });
        }
      }
      return Response.ok(jsonEncode(loadedItems), headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(body: 'Database synchronization failed: $e');
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
        await connection.close();
        return Response.ok(jsonEncode({'status': 'received'}));
      }

      final convId = contactResult.first[0].toString();
      final rawContent = data['content_encrypted'] as String? ?? '';
      final preview = rawContent.length > 60 ? rawContent.substring(0, 60) : rawContent;

      await connection.execute(
        Sql.named("""
          INSERT INTO tm_messages
            (id, conversation_id, sender_guptik_id, sender_username,
             content_encrypted, content_type, message_nonce,
             is_delivered, delivered_at, received_at)
          VALUES
            (@id, @cid, @sid, @user, @enc, @type, @nonce, true, NOW(), NOW())
        """),
        parameters: {
          'id': data['message_id'],
          'cid': convId,
          'sid': senderId,
          'user': data['sender_username'],
          'enc': rawContent,
          'type': data['content_type'] ?? 'text',
          'nonce': data['nonce'] ?? 'nonce',
        }
      );

      await connection.execute(
        Sql.named('UPDATE tm_conversations SET unread_count = unread_count + 1, last_message_at = NOW(), last_message_type = @type, last_message_preview = @prev WHERE id = @cid'),
        parameters: {'type': data['content_type'] ?? 'text', 'prev': preview, 'cid': convId}
      );

      final senderUrlResult = await connection.execute(
        Sql.named('SELECT contact_cloudflare_url FROM tm_contacts WHERE contact_guptik_id = @sid LIMIT 1'),
        parameters: {'sid': senderId}
      );
      await connection.close();

      if (senderUrlResult.isNotEmpty) {
        var senderUrl = senderUrlResult.first[0].toString();
        if (!senderUrl.startsWith('http')) senderUrl = 'https://$senderUrl';
        try {
          await http.post(
            Uri.parse('$senderUrl/trustme/receipt/delivered'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'message_id': data['message_id']}),
          ).timeout(const Duration(seconds: 5));
        } catch (_) {}
      }

      return Response.ok(jsonEncode({'status': 'received'}));
    } catch (e) {
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

      var targetUrl = convResult.first[0] as String;
      if (!targetUrl.startsWith('http')) {
        targetUrl = 'https://$targetUrl';
      }

      final messageId = uuid.v4();
      final myId = data['sender_id'] ?? 'unknown_user';
      final myUsername = data['sender_username'] ?? 'Me';

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

      final response = await http.post(
        Uri.parse('$targetUrl/trustme/message/receive'),
        headers: {'Content-Type': 'application/json', 'X-Sender-ID': myId},
        body: jsonEncode(outPayload),
      ).timeout(const Duration(seconds: 4)); 

      final contentStr = (data['content'] as String? ?? '');
      final preview = contentStr.length > 60 ? contentStr.substring(0, 60) : contentStr;
      final msgType = data['content_type'] ?? 'text';

      if (response.statusCode == 200) {
        final dc = await Connection.open(
          Endpoint(host: 'db', port: 5432, database: 'postgres', username: 'postgres', password: 'GuptikSystemPassword2026'),
          settings: const ConnectionSettings(sslMode: SslMode.disable),
        );
        await dc.execute(
          Sql.named('UPDATE tm_messages SET is_delivered = true, delivered_at = NOW(), sent_at = COALESCE(sent_at, NOW()) WHERE id = @mid'),
          parameters: {'mid': messageId},
        );
        await dc.execute(
          Sql.named('UPDATE tm_conversations SET last_message_preview = @prev, last_message_at = NOW(), last_message_type = @type WHERE id = @cid'),
          parameters: {'prev': preview, 'type': msgType, 'cid': conversationId},
        );
        await dc.close();
        return Response.ok(jsonEncode({'status': 'delivered', 'message_id': messageId}));
      } else {
        throw Exception("Status not 200");
      }
    } catch (e) {
      try {
        final payload = await req.readAsString();
        final data = jsonDecode(payload);
        final sc = await Connection.open(
          Endpoint(host: 'db', port: 5432, database: 'postgres', username: 'postgres', password: 'GuptikSystemPassword2026'),
          settings: const ConnectionSettings(sslMode: SslMode.disable),
        );
        final contentStr = (data['content'] as String? ?? '');
        final preview = contentStr.length > 60 ? contentStr.substring(0, 60) : contentStr;
        await sc.execute(
          Sql.named('UPDATE tm_conversations SET last_message_preview = @prev, last_message_at = NOW(), last_message_type = @type WHERE id = @cid'),
          parameters: {'prev': preview, 'type': data['content_type'] ?? 'text', 'cid': data['conversation_id']},
        );
        await sc.close();
      } catch (_) {}
      return Response.ok(jsonEncode({'status': 'queued'}));
    }
  });

  router.post('/internal/message/stream_send/<conversationId>/<ext>', (Request req, String conversationId, String ext) async {
    try {
      final senderId = req.headers['x-sender-id'] ?? 'unknown';
      final senderUsername = req.headers['x-sender-username'] ?? 'Me';
      final contentType = req.headers['x-content-type'] ?? 'media';

      final connection = await Connection.open(
        Endpoint(host: 'db', port: 5432, database: 'postgres', username: 'postgres', password: 'GuptikSystemPassword2026'),
        settings: const ConnectionSettings(sslMode: SslMode.disable),
      );

      final convResult = await connection.execute(
        Sql.named("SELECT ct.contact_cloudflare_url FROM tm_conversations c JOIN tm_contacts ct ON c.contact_id = ct.id WHERE c.id = @cid LIMIT 1"),
        parameters: {'cid': conversationId}
      );
      if (convResult.isEmpty) {
        await connection.close();
        return Response.notFound('Conversation not found');
      }
      
      var targetUrl = convResult.first[0] as String;
      if (!targetUrl.startsWith('http')) targetUrl = 'https://$targetUrl';

      final messageId = uuid.v4();
      final filename = '${messageId}.$ext';
      final file = File('/app/storage/$filename');
      final sink = file.openWrite();
      await sink.addStream(req.read());
      await sink.flush();
      await sink.close();

      final contentPath = '[media]/internal/media/$filename';
      await connection.execute(
        Sql.named("INSERT INTO tm_messages (id, conversation_id, sender_guptik_id, sender_username, content_encrypted, content_type, message_nonce) VALUES (@id, @cid, @sid, @user, @enc, @type, 'local_nonce')"),
        parameters: {'id': messageId, 'cid': conversationId, 'sid': senderId, 'user': senderUsername, 'enc': contentPath, 'type': contentType}
      );

      final client = http.Client();
      final peerReq = http.StreamedRequest('POST', Uri.parse('$targetUrl/trustme/message/stream_receive/$messageId/$ext'));
      peerReq.headers['x-sender-id'] = senderId;
      peerReq.headers['x-sender-username'] = senderUsername;
      peerReq.headers['x-content-type'] = contentType;
      peerReq.contentLength = await file.length();
      
      file.openRead().listen(
        peerReq.sink.add,
        onDone: peerReq.sink.close,
        onError: peerReq.sink.addError
      );
      
      await client.send(peerReq);
      await connection.close();

      return Response.ok(jsonEncode({'status': 'delivered', 'message_id': messageId, 'path': contentPath}));
    } catch (e) {
      return Response.internalServerError(body: 'Stream Send Error: $e');
    }
  });

  router.post('/trustme/message/stream_receive/<messageId>/<ext>', (Request req, String messageId, String ext) async {
    try {
      final senderId = req.headers['x-sender-id'] ?? 'unknown';
      final senderUsername = req.headers['x-sender-username'] ?? 'Peer';
      final contentType = req.headers['x-content-type'] ?? 'media';

      final filename = '${messageId}.$ext';
      final file = File('/app/storage/$filename');
      final sink = file.openWrite();
      await sink.addStream(req.read());
      await sink.flush();
      await sink.close();

      final connection = await Connection.open(
        Endpoint(host: 'db', port: 5432, database: 'postgres', username: 'postgres', password: 'GuptikSystemPassword2026'),
        settings: const ConnectionSettings(sslMode: SslMode.disable),
      );

      final contactResult = await connection.execute(
        Sql.named("SELECT c.id as conversation_id FROM tm_contacts ct JOIN tm_conversations c ON c.contact_id = ct.id WHERE ct.contact_guptik_id = @sid LIMIT 1"),
        parameters: {'sid': senderId}
      );

      if (contactResult.isNotEmpty) {
         final convId = contactResult.first[0];
         final contentPath = '[media]/internal/media/$filename';

         await connection.execute(
           Sql.named("INSERT INTO tm_messages (id, conversation_id, sender_guptik_id, sender_username, content_encrypted, content_type, message_nonce) VALUES (@id, @cid, @sid, @user, @enc, @type, 'remote_nonce')"),
           parameters: {'id': messageId, 'cid': convId, 'sid': senderId, 'user': senderUsername, 'enc': contentPath, 'type': contentType}
         );
         await connection.execute(
           Sql.named("UPDATE tm_conversations SET unread_count = unread_count + 1, last_message_at = NOW(), last_message_type = @type WHERE id = @cid"),
           parameters: {'type': contentType, 'cid': convId}
         );
      }
      await connection.close();
      return Response.ok('Stream Received successfully');
    } catch (e) {
      return Response.internalServerError(body: 'Stream Receive Error: $e');
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
          SELECT id, sender_guptik_id, sender_username, content_encrypted, content_type, 
                 created_at, is_read, is_delivered, is_deleted_for_everyone
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
        'content': row[3]?.toString() ?? '', 
        'content_type': row[4]?.toString() ?? 'text',
        'created_at': row[5].toString(),
        'is_read': row[6] as bool,
        'is_delivered': row[7] as bool,
        'is_deleted_for_everyone': row[8] as bool,
      }).toList();

      return Response.ok(jsonEncode({'messages': messages}), headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(body: jsonEncode({'error': e.toString()}));
    }
  });

  router.post('/internal/message/edit', (Request req) async {
    try {
      final payload = await req.readAsString();
      final data = jsonDecode(payload);
      final msgId = data['message_id'];
      final newContent = data['new_content'];
      final conversationId = data['conversation_id'];

      final connection = await Connection.open(
        Endpoint(host: 'db', port: 5432, database: 'postgres', username: 'postgres', password: 'GuptikSystemPassword2026'),
        settings: const ConnectionSettings(sslMode: SslMode.disable),
      );

      await connection.execute(
        Sql.named('UPDATE tm_messages SET content_encrypted = @content WHERE id = @mid'),
        parameters: {'content': newContent, 'mid': msgId}
      );

      final convResult = await connection.execute(
        Sql.named("SELECT ct.contact_cloudflare_url FROM tm_conversations c JOIN tm_contacts ct ON c.contact_id = ct.id WHERE c.id = @cid LIMIT 1"),
        parameters: {'cid': conversationId}
      );

      if (convResult.isNotEmpty) {
        var targetUrl = convResult.first[0].toString();
        if (!targetUrl.startsWith('http')) targetUrl = 'https://$targetUrl';
        try {
          await http.post(
            Uri.parse('$targetUrl/trustme/message/sync_edit'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'message_id': msgId, 'new_content': newContent}),
          ).timeout(const Duration(seconds: 3));
        } catch (_) {}
      }
      
      await connection.close();
      return Response.ok(jsonEncode({'status': 'success'}));
    } catch (e) {
      return Response.internalServerError();
    }
  });

  router.post('/internal/message/delete', (Request req) async {
    try {
      final payload = await req.readAsString();
      final data = jsonDecode(payload);
      final msgId = data['message_id'];
      final forEveryone = data['for_everyone'] == true;
      final conversationId = data['conversation_id'];

      final connection = await Connection.open(
        Endpoint(host: 'db', port: 5432, database: 'postgres', username: 'postgres', password: 'GuptikSystemPassword2026'),
        settings: const ConnectionSettings(sslMode: SslMode.disable),
      );

      if (forEveryone) {
        await connection.execute(
          Sql.named('UPDATE tm_messages SET is_deleted_for_everyone = true, deleted_at = NOW() WHERE id = @mid'),
          parameters: {'mid': msgId}
        );

        final convResult = await connection.execute(
          Sql.named("SELECT ct.contact_cloudflare_url FROM tm_conversations c JOIN tm_contacts ct ON c.contact_id = ct.id WHERE c.id = @cid LIMIT 1"),
          parameters: {'cid': conversationId}
        );

        if (convResult.isNotEmpty) {
          var targetUrl = convResult.first[0].toString();
          if (!targetUrl.startsWith('http')) targetUrl = 'https://$targetUrl';
          try {
            await http.post(
              Uri.parse('$targetUrl/trustme/message/sync_delete'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'message_id': msgId}),
            ).timeout(const Duration(seconds: 3));
          } catch (_) {}
        }
      } else {
        await connection.execute(
          Sql.named('DELETE FROM tm_messages WHERE id = @mid'),
          parameters: {'mid': msgId}
        );
      }
      
      await connection.close();
      return Response.ok(jsonEncode({'status': 'success'}));
    } catch (e) {
      return Response.internalServerError();
    }
  });

  router.post('/trustme/message/sync_edit', (Request req) async {
    try {
      final payload = await req.readAsString();
      final data = jsonDecode(payload);
      
      final connection = await Connection.open(
        Endpoint(host: 'db', port: 5432, database: 'postgres', username: 'postgres', password: 'GuptikSystemPassword2026'),
        settings: const ConnectionSettings(sslMode: SslMode.disable),
      );
      await connection.execute(
        Sql.named('UPDATE tm_messages SET content_encrypted = @content WHERE id = @mid'),
        parameters: {'content': data['new_content'], 'mid': data['message_id']}
      );
      await connection.close();
      return Response.ok(jsonEncode({'status': 'ok'}));
    } catch (e) {
      return Response.internalServerError();
    }
  });

  router.post('/trustme/message/sync_delete', (Request req) async {
    try {
      final payload = await req.readAsString();
      final data = jsonDecode(payload);
      
      final connection = await Connection.open(
        Endpoint(host: 'db', port: 5432, database: 'postgres', username: 'postgres', password: 'GuptikSystemPassword2026'),
        settings: const ConnectionSettings(sslMode: SslMode.disable),
      );
      await connection.execute(
        Sql.named('UPDATE tm_messages SET is_deleted_for_everyone = true, deleted_at = NOW() WHERE id = @mid'),
        parameters: {'mid': data['message_id']}
      );
      await connection.close();
      return Response.ok(jsonEncode({'status': 'ok'}));
    } catch (e) {
      return Response.internalServerError();
    }
  });

  router.get('/internal/conversations', (Request req) async {
    try {
      final connection = await Connection.open(
        Endpoint(host: 'db', port: 5432, database: 'postgres', username: 'postgres', password: 'GuptikSystemPassword2026'),
        settings: const ConnectionSettings(sslMode: SslMode.disable),
      );

      final result = await connection.execute("""
        SELECT c.id, c.type, ct.contact_username,ct.custom_username, c.last_message_preview, 
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
        'custom_username': row[3]?.toString(),
        'last_message_preview': row[4]?.toString(), 
        'last_message_at': row[5]?.toString(),
        'unread_count': row[6] as int,
        'is_pinned': row[7] as bool,
        'is_muted': row[8] as bool,
      }).toList();

      return Response.ok(jsonEncode({'conversations': conversations}), headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(body: jsonEncode({'error': e.toString()}));
    }
  });

  router.get('/internal/conversation/<conversationId>/contact', (Request req, String conversationId) async {
    try {
      final connection = await Connection.open(
        Endpoint(host: 'db', port: 5432, database: 'postgres', username: 'postgres', password: 'GuptikSystemPassword2026'),
        settings: const ConnectionSettings(sslMode: SslMode.disable),
      );
      final result = await connection.execute(
        Sql.named("SELECT ct.contact_cloudflare_url FROM tm_conversations c JOIN tm_contacts ct ON c.contact_id = ct.id WHERE c.id = @cid LIMIT 1"),
        parameters: {'cid': conversationId}
      );
      await connection.close();
      if (result.isEmpty) return Response.notFound('Not found');
      return Response.ok(jsonEncode({'url': result.first[0].toString()}), headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.internalServerError();
    }
  });

  router.post('/internal/contact/rename', (Request req) async {
    try {
      final payload = await req.readAsString();
      final data = jsonDecode(payload);
      final conversationId = data['conversation_id'];
      final customName = data['custom_name'];

      final connection = await Connection.open(
        Endpoint(host: 'db', port: 5432, database: 'postgres', username: 'postgres', password: 'GuptikSystemPassword2026'),
        settings: const ConnectionSettings(sslMode: SslMode.disable),
      );

      final convResult = await connection.execute(
        Sql.named("SELECT contact_id FROM tm_conversations WHERE id = @cid"),
        parameters: {'cid': conversationId}
      );

      if (convResult.isNotEmpty) {
        final contactId = convResult.first[0];
        await connection.execute(
          Sql.named("UPDATE tm_contacts SET custom_username = @name WHERE id = @cid"),
          parameters: {'name': customName.toString().isEmpty ? null : customName, 'cid': contactId}
        );
      }
      await connection.close();
      return Response.ok(jsonEncode({'status': 'success'}));
    } catch (e) {
      return Response.internalServerError();
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
    
    try {
      final existingContact = await connection.execute(
        Sql.named("SELECT id FROM tm_contacts WHERE contact_guptik_id = @gid"),
        parameters: {'gid': data['counterpart_guptik_id']}
      );

      if (existingContact.isNotEmpty) {
        final contactId = existingContact.first[0].toString();
        await connection.execute(
          Sql.named("""
            UPDATE tm_contacts 
            SET contact_cloudflare_url = @url, 
                contact_identity_pubkey = @ipub, 
                contact_signed_prekey = @spk, 
                contact_signed_prekey_id = @spkid 
            WHERE id = @cid
          """),
          parameters: {
            'cid': contactId,
            'url': data['counterpart_url'],
            'ipub': data['contact_identity_pubkey'], 
            'spk': data['contact_signed_prekey'],    
            'spkid': data['contact_signed_prekey_id'], 
          },
        );

        final convResult = await connection.execute(
          Sql.named("SELECT id FROM tm_conversations WHERE contact_id = @cid LIMIT 1"),
          parameters: {'cid': contactId}
        );
        
        await connection.close();
        return Response.ok(jsonEncode({'status': 'success', 'conversation_id': convResult.first[0].toString()}));
      }

      final conversationId = uuid.v4();
      final contactId = uuid.v4();

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
          'ipub': data['contact_identity_pubkey'], 
          'spk': data['contact_signed_prekey'],    
          'spkid': data['contact_signed_prekey_id'], 
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
      return Response.internalServerError(body: jsonEncode({'error': e.toString()}));
    }
  });

  router.post('/internal/conversation/<conversationId>/read', (Request req, String conversationId) async {
    try {
      final connection = await Connection.open(
        Endpoint(host: 'db', port: 5432, database: 'postgres', username: 'postgres', password: 'GuptikSystemPassword2026'),
        settings: const ConnectionSettings(sslMode: SslMode.disable),
      );

      final peerResult = await connection.execute(
        Sql.named("SELECT ct.contact_guptik_id, ct.contact_cloudflare_url FROM tm_conversations c JOIN tm_contacts ct ON c.contact_id = ct.id WHERE c.id = @cid LIMIT 1"),
        parameters: {'cid': conversationId}
      );
      
      if (peerResult.isEmpty) {
        await connection.close();
        return Response.ok(jsonEncode({'status': 'no_peer'}));
      }
      
      final peerId = peerResult.first[0].toString();
      var peerUrl = peerResult.first[1].toString();
      if (!peerUrl.startsWith('http')) peerUrl = 'https://$peerUrl';

      final unreadResult = await connection.execute(
        Sql.named("""
          SELECT id 
          FROM tm_messages 
          WHERE conversation_id = @cid 
            AND is_read = false 
            AND sender_guptik_id = @pid
          LIMIT 100
        """),
        parameters: {'cid': conversationId, 'pid': peerId},
      );

      await connection.execute(
        Sql.named('UPDATE tm_messages SET is_read = true, read_at = NOW() WHERE conversation_id = @cid AND is_read = false AND sender_guptik_id = @pid'),
        parameters: {'cid': conversationId, 'pid': peerId},
      );

      await connection.execute(
        Sql.named('UPDATE tm_conversations SET unread_count = 0 WHERE id = @cid'),
        parameters: {'cid': conversationId},
      );
      
      await connection.close();

      if (unreadResult.isNotEmpty) {
        final messageIds = unreadResult.map((r) => r[0].toString()).toList();
        try {
          await http.post(
            Uri.parse('$peerUrl/trustme/receipt/read'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'message_ids': messageIds}),
          ).timeout(const Duration(seconds: 5));
        } catch (_) {}
      }

      return Response.ok(jsonEncode({'status': 'success'}));
    } catch (e) {
      return Response.internalServerError(body: jsonEncode({'error': e.toString()}));
    }
  });

  router.post('/trustme/receipt/delivered', (Request req) async {
    try {
      final payload = await req.readAsString();
      final data = jsonDecode(payload);
      final messageId = data['message_id']?.toString();
      if (messageId == null || messageId.isEmpty) {
        return Response.badRequest(body: 'Missing message_id');
      }
      final conn = await Connection.open(
        Endpoint(host: 'db', port: 5432, database: 'postgres', username: 'postgres', password: 'GuptikSystemPassword2026'),
        settings: const ConnectionSettings(sslMode: SslMode.disable),
      );
      await conn.execute(
        Sql.named('UPDATE tm_messages SET is_delivered = true, delivered_at = NOW() WHERE id = @mid'),
        parameters: {'mid': messageId},
      );
      await conn.close();
      return Response.ok(jsonEncode({'status': 'ok'}));
    } catch (e) {
      return Response.internalServerError(body: e.toString());
    }
  });

  router.post('/trustme/receipt/read', (Request req) async {
    try {
      final payload = await req.readAsString();
      final data = jsonDecode(payload);
      final messageIds = (data['message_ids'] as List?)?.map((e) => e.toString()).toList() ?? [];
      if (messageIds.isEmpty) return Response.badRequest(body: 'Missing message_ids');
      final conn = await Connection.open(
        Endpoint(host: 'db', port: 5432, database: 'postgres', username: 'postgres', password: 'GuptikSystemPassword2026'),
        settings: const ConnectionSettings(sslMode: SslMode.disable),
      );
      for (final mid in messageIds) {
        await conn.execute(
          Sql.named('UPDATE tm_messages SET is_read = true, read_at = NOW() WHERE id = @mid'),
          parameters: {'mid': mid},
        );
      }
      await conn.close();
      return Response.ok(jsonEncode({'status': 'ok', 'updated': messageIds.length}));
    } catch (e) {
      return Response.internalServerError(body: e.toString());
    }
  });

// =========================================================================
  // 🚀 GUPTIK PLAYER: MEDIA STREAMING & ENGAGEMENT
  // =========================================================================
// 1. VIDEO STREAMING ROUTE (With Ultimate Fallback)
  router.get('/player/video/stream/<videoId>', (Request req, String videoId) async {
    try {
      final connection = await Connection.open(
        Endpoint(host: 'db', port: 5432, database: 'postgres', username: 'postgres', password: 'GuptikSystemPassword2026'),
        settings: const ConnectionSettings(sslMode: SslMode.disable),
      );
      
      final result = await connection.execute(
        Sql.named("SELECT file_path FROM user_videos WHERE id = CAST(@vid AS UUID) LIMIT 1"),
        parameters: {'vid': videoId},
      );
      await connection.close();

      if (result.isEmpty) return Response(404, body: 'Video not found in local vault.');
      
      final rawDbPath = result.first[0].toString(); 
      final fileName = rawDbPath.split(RegExp(r'[/\\]')).last; 
      
      // 🚀 THE ULTIMATE FALLBACK HUNTER
      var file = File('/app/storage/$fileName'); // Check new proper location

      if (!await file.exists()) {
        file = File('/app/storage/vault_files/$fileName'); // Check old Russian Doll location
      }
      if (!await file.exists()) {
        file = File('/app/storage/$videoId.mp4'); // Check by UUID in new location
      }
      if (!await file.exists()) {
        file = File('/app/storage/vault_files/$videoId.mp4'); // Check by UUID in old location
      }

      if (!await file.exists()) return Response(404, body: 'File not found on disk.');
      
      final fileSize = await file.length();
      final mimeType = lookupMimeType(file.path) ?? 'video/mp4'; 
      final rangeHeader = req.headers['range'];

      if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
        final parts = rangeHeader.substring(6).split('-');
        final start = int.tryParse(parts[0]) ?? 0;
        final end = parts.length > 1 && parts[1].isNotEmpty ? int.tryParse(parts[1]) ?? fileSize - 1 : fileSize - 1;

        if (start >= fileSize) return Response(416, headers: {'Content-Range': 'bytes */$fileSize'});
        final contentLength = end - start + 1;
        final stream = file.openRead(start, end + 1);

        return Response(206, body: stream, headers: {
          'Content-Type': mimeType, 
          'Content-Length': contentLength.toString(),
          'Content-Range': 'bytes $start-$end/$fileSize', 
          'Accept-Ranges': 'bytes',
        });
      } else {
        return Response(200, body: file.openRead(), headers: {
          'Content-Type': mimeType, 
          'Content-Length': fileSize.toString(), 
          'Accept-Ranges': 'bytes',
        });
      }
    } catch (e) {
      return Response(500, body: 'Streaming Error: $e');
    }
  });
    
    router.post('/player/video/like', (Request req) async {
    try {
      final payload = await req.readAsString();
      final data = jsonDecode(payload);
      final connection = await Connection.open(
        Endpoint(host: 'db', port: 5432, database: 'postgres', username: 'postgres', password: 'GuptikSystemPassword2026'),
        settings: const ConnectionSettings(sslMode: SslMode.disable),
      );

      final String vid = data['video_id'].toString();
      final String uid = data['creator_uid'].toString();
      final String reaction = data['reaction_type'] ?? 'heart';

      // 1. 🚀 THE GATEKEEPER: Check if they already liked it!
      final checkExistingLike = await connection.execute(
        Sql.named("SELECT id FROM liked_videos WHERE video_id = @vid AND creator_uid = @uid LIMIT 1"),
        parameters: {'vid': vid, 'uid': uid}
      );

      if (checkExistingLike.isNotEmpty) {
        // They already liked it! Stop here and don't add another point.
        await connection.close();
        return Response(200, body: jsonEncode({'status': 'already_liked', 'message': 'You can only like once.'}));
      }

      // 2. Since they haven't liked it yet, save their like to the table.
      await connection.execute(
        Sql.named("""
          INSERT INTO liked_videos (video_id, creator_uid, reaction_type)
          VALUES (@vid, @uid, @reaction)
        """),
        parameters: {
          'vid': vid,
          'uid': uid,
          'reaction': reaction
        }
      );

      // 3. Now it is safe to increase the video's total score by +1.
      await connection.execute(
        Sql.named("UPDATE user_videos SET like_count_local = like_count_local + 1 WHERE id = CAST(@vid AS UUID)"),
        parameters: {'vid': vid}
      );
      
      await connection.close();
      return Response(200, body: jsonEncode({'status': 'liked'}));
    } catch (e) {
      print('🚀 DOCKER CRASH in /player/video/like: $e');
      return Response(500, body: 'Like Error: $e');
    }
  });

  // 3. POST COMMENT ROUTE (Corrected to use commented_videos)
  router.post('/player/video/comment', (Request req) async {
    try {
      final payload = await req.readAsString();
      final data = jsonDecode(payload);
      final connection = await Connection.open(
        Endpoint(host: 'db', port: 5432, database: 'postgres', username: 'postgres', password: 'GuptikSystemPassword2026'),
        settings: const ConnectionSettings(sslMode: SslMode.disable),
      );
      
      // 🚀 1. Actually save the text to your official commented_videos table!
      await connection.execute(
        Sql.named("""
          INSERT INTO commented_videos (video_id, creator_uid, comment_text) 
          VALUES (@vid, @uid, @txt)
        """),
        parameters: {
          'vid': data['video_id'], 
          'uid': data['creator_uid'], 
          'txt': data['comment_text']
        }
      );

      // 🚀 2. Increase the comment counter on the video
      await connection.execute(
        Sql.named("UPDATE user_videos SET comment_count_local = comment_count_local + 1 WHERE id = CAST(@vid AS UUID)"),
        parameters: {'vid': data['video_id']}
      );
      
      await connection.close();
      return Response(200, body: jsonEncode({'status': 'comment_added'}));
    } catch (e) {
      return Response(500, body: 'Comment Error: $e');
    }
  });

  // 4. GET COMMENTS ROUTE (Corrected to use commented_videos)
  router.get('/player/video/comments/<videoId>', (Request req, String videoId) async {
    try {
      final connection = await Connection.open(
        Endpoint(host: 'db', port: 5432, database: 'postgres', username: 'postgres', password: 'GuptikSystemPassword2026'),
        settings: const ConnectionSettings(sslMode: SslMode.disable),
      );

      // 🚀 Fetch from your official table, using comment_timestamp
      final result = await connection.execute(
        Sql.named("""
          SELECT comment_text, creator_uid, comment_timestamp 
          FROM commented_videos 
          WHERE video_id = @vid
          ORDER BY comment_timestamp DESC
        """),
        parameters: {'vid': videoId},
      );
      
      await connection.close();

      final List<Map<String, dynamic>> commentsList = [];
      for (final row in result) {
        commentsList.add({
          'comment_text': row[0].toString(),
          'creator_uid': row[1].toString(),
          'created_at': row[2].toString(), // Mapped so the UI still understands it
        });
      }

      return Response(200, body: jsonEncode(commentsList), headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response(500, body: jsonEncode({'error': 'Failed to fetch comments'}));
    }
  });

// 5. THUMBNAIL ROUTE (With Server-Side Auto-Generation)
  router.get('/player/video/thumbnail/<videoId>', (Request req, String videoId) async {
    try {
      final connection = await Connection.open(
        Endpoint(host: 'db', port: 5432, database: 'postgres', username: 'postgres', password: 'GuptikSystemPassword2026'),
        settings: const ConnectionSettings(sslMode: SslMode.disable),
      );
      
      final result = await connection.execute(
        Sql.named("SELECT file_path FROM user_videos WHERE id = CAST(@vid AS UUID) LIMIT 1"),
        parameters: {'vid': videoId},
      );
      await connection.close();

      if (result.isEmpty) return Response(404, body: 'Video not found in DB.');

      // 1. Locate the original video file on disk
      final mp4DbPath = result.first[0].toString();
      final mp4FileName = mp4DbPath.split(RegExp(r'[/\\]')).last;
      
      var mp4File = File('/app/storage/$mp4FileName');
      if (!await mp4File.exists()) {
        mp4File = File('/app/storage/vault_files/$mp4FileName');
      }
      if (!await mp4File.exists()) {
        mp4File = File('/app/storage/$videoId.mp4');
      }
      if (!await mp4File.exists()) {
        mp4File = File('/app/storage/vault_files/$videoId.mp4');
      }

      if (!await mp4File.exists()) {
        return Response(404, body: 'Original media file not found on disk. Cannot generate thumbnail.');
      }

      // 2. Define where the JPG should be based on the actual file found (handles .MOV, .MP4, etc.)
      final thumbDir = mp4File.parent.path;
      final resolvedFileName = mp4File.path.split(RegExp(r'[/\\]')).last;
      final int lastDotIndex = resolvedFileName.lastIndexOf('.');
      final String baseNameWithoutExt = lastDotIndex != -1 ? resolvedFileName.substring(0, lastDotIndex) : resolvedFileName;
      
      final thumbPath = '$thumbDir/$baseNameWithoutExt.jpg';
      var thumbFile = File(thumbPath);

      // 3. 🚀 If thumbnail doesn't exist, generate it seamlessly using FFmpeg
      if (!await thumbFile.exists()) {
        print('📸 Generating missing thumbnail for $videoId...');
        
        final processResult = await Process.run('ffmpeg', [
          '-i', mp4File.path,
          '-ss', '00:00:02.000', // Capture frame at the 2-second mark
          '-vframes', '1',
          '-q:v', '2',           // High quality JPEG configuration
          '-y',                  // Automatically overwrite file if duplicate thread spawns
          thumbPath
        ], runInShell: true);    // Required layer tracking for Linux environments

        if (processResult.exitCode != 0) {
          print('❌ FFmpeg failed: ${processResult.stderr}');
          return Response(404, body: 'Failed to generate thumbnail via FFmpeg.');
        }
        
        // Refresh instance targeting references now that it sits safely on disk
        thumbFile = File(thumbPath); 
      }

      // 4. Serve the image binary payload
      return Response(200, body: thumbFile.openRead(), headers: {
        'Content-Type': 'image/jpeg',
        'Content-Length': (await thumbFile.length()).toString(),
        'Cache-Control': 'public, max-age=86400', // Cache it for 24 hours to reduce CPU overhead
      });

    } catch (e) {
      print('🚀 Thumbnail API Error: $e');
      return Response(500, body: 'Thumbnail API Error: $e');
    }
  });
  
  router.post('/player/video/history', (Request req) async {
    try {
      final payload = await req.readAsString();
      final data = jsonDecode(payload);
      final connection = await Connection.open(
        Endpoint(host: 'db', port: 5432, database: 'postgres', username: 'postgres', password: 'GuptikSystemPassword2026'),
        settings: const ConnectionSettings(sslMode: SslMode.disable),
      );
      
      await connection.execute(
        Sql.named("""
          INSERT INTO watch_history 
          (video_id, creator_channel_id, creator_uid, watch_duration_seconds, percent_completed, session_id) 
          VALUES (@vid, @cid, @uid, @dur, @pct, @sid)
        """),
        parameters: {
          'vid': data['video_id'],
          'cid': data['channel_id'] ?? 'unknown',
          'uid': data['creator_uid'],
          'dur': data['watch_duration_seconds'] ?? 0,
          'pct': data['percent_completed'] ?? 0.0,
          'sid': data['session_id'] ?? 'session',
        }
      );
      await connection.close();
      return Response(200, body: jsonEncode({'status': 'history_logged'}));
    } catch (e) {
      return Response(500, body: 'History Error: $e');
    }
  });

  router.post('/player/video/save', (Request req) async {
    try {
      final payload = await req.readAsString();
      final data = jsonDecode(payload);
      final connection = await Connection.open(
        Endpoint(host: 'db', port: 5432, database: 'postgres', username: 'postgres', password: 'GuptikSystemPassword2026'),
        settings: const ConnectionSettings(sslMode: SslMode.disable),
      );
      
      await connection.execute(
        Sql.named("INSERT INTO saved_videos (video_id, creator_uid, folder_name) VALUES (@vid, @uid, @folder)"),
        parameters: {
          'vid': data['video_id'], 
          'uid': data['creator_uid'],
          'folder': data['folder_name'] ?? 'Default'
        }
      );
      
      await connection.execute(
        Sql.named("UPDATE user_videos SET save_count_local = save_count_local + 1 WHERE id = CAST(@vid AS UUID)"),
        parameters: {'vid': data['video_id']}
      );
      
      await connection.close();
      return Response(200, body: jsonEncode({'status': 'saved'}));
    } catch (e) {
      return Response(500, body: 'Save Error: $e');
    }
  });

  // 8. GET VIDEO STATS (Real-time sync for UI)
  router.get('/player/video/stats/<videoId>', (Request req, String videoId) async {
    try {
      final connection = await Connection.open(
        Endpoint(host: 'db', port: 5432, database: 'postgres', username: 'postgres', password: 'GuptikSystemPassword2026'),
        settings: const ConnectionSettings(sslMode: SslMode.disable),
      );
      
      // 🚀 FIXED: Now it grabs view_count_local from the database!
      final result = await connection.execute(
        Sql.named("SELECT like_count_local, comment_count_local, save_count_local, view_count_local FROM user_videos WHERE id = CAST(@vid AS UUID) LIMIT 1"),
        parameters: {'vid': videoId}
      );
      
      await connection.close();
      
      if (result.isEmpty) return Response(404, body: 'Video not found');
      
      return Response(200, body: jsonEncode({
        'likes': result.first[0] ?? 0,
        'comments': result.first[1] ?? 0,
        'saves': result.first[2] ?? 0,
        'views': result.first[3] ?? 0 // 🚀 FIXED: Sends views to the Media Player!
      }), headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response(500, body: 'Stats Error: $e');
    }
  });
  
  // =========================================================================
  // 🚀 9. CREATOR CHANNEL PROFILE & VIDEOS
  // =========================================================================
  
  // A. Fetch the Channel Bio and Subscriber Count
  router.get('/channel/profile/<channelId>', (Request req, String channelId) async {
    try {
      final connection = await Connection.open(
        Endpoint(host: 'db', port: 5432, database: 'postgres', username: 'postgres', password: 'GuptikSystemPassword2026'),
        settings: const ConnectionSettings(sslMode: SslMode.disable),
      );
      
      final result = await connection.execute(
        Sql.named("SELECT channel_name, bio, subscriber_count FROM user_channels WHERE channel_id = @cid LIMIT 1"),
        parameters: {'cid': channelId}
      );
      await connection.close();
      
      if (result.isEmpty) return Response(404, body: 'Channel not found');
      
      return Response(200, body: jsonEncode({
        'channel_name': result.first[0] ?? 'Unknown Creator',
        'bio': result.first[1] ?? 'Welcome to my decentralized channel!',
        'subscribers': result.first[2] ?? 0
      }), headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response(500, body: 'Profile Error: $e');
    }
  });

  // B. Fetch all videos hosted by this creator on this Node (REAL CHANNEL NAME VERSION)
  router.get('/channel/videos/<channelId>', (Request req, String channelId) async {
    try {
      final connection = await Connection.open(
        Endpoint(host: 'db', port: 5432, database: 'postgres', username: 'postgres', password: 'GuptikSystemPassword2026'),
        settings: const ConnectionSettings(sslMode: SslMode.disable),
      );
      
      // 🚀 THE FIX: JOIN user_channels to get the REAL channel name!
      // Also added is_reel so the UI knows how to shape the card!
      final result = await connection.execute(
        Sql.named("""
          SELECT v.id, v.title, v.description, v.file_path, v.view_count_local, v.like_count_local, v.comment_count_local, c.channel_name, v.is_reel 
          FROM user_videos v
          JOIN user_channels c ON v.channel_id = c.channel_id
          WHERE v.channel_id = @cid
        """),
        parameters: {'cid': channelId}
      );
      await connection.close();
      
      final List<Map<String, dynamic>> videos = [];
      for (final row in result) {
        videos.add({
          'video_id': row[0].toString(),
          'title': row[1].toString(),
          'description': row[2]?.toString() ?? 'No description',
          'file_path': row[3].toString(),
          'view_count': row[4] ?? 0,
          'like_count': row[5] ?? 0,
          'comment_count': row[6] ?? 0,
          'created_at': DateTime.now().toString(), // Safe fallback
          'creator_uid': channelId,
          'channel_name': row[7]?.toString() ?? 'Creator', // 🚀 REAL NAME HERE
          'is_reel': row[8] as bool? ?? false // 🚀 PULL REAL REEL STATUS
        });
      }
      return Response(200, body: jsonEncode(videos), headers: {'Content-Type': 'application/json'});
    } catch (e) {
      print('🚀 DOCKER CRASH in /channel/videos: $e');
      return Response(500, body: jsonEncode({'error': e.toString()}));
    }
  });

  
  // 🚀 NEW ROUTE: Gatekeeper for Unique Views
  router.post('/player/video/view', (Request req) async {
    try {
      final payload = await req.readAsString();
      final data = jsonDecode(payload);
      final connection = await Connection.open(
        Endpoint(host: 'db', port: 5432, database: 'postgres', username: 'postgres', password: 'GuptikSystemPassword2026'),
        settings: const ConnectionSettings(sslMode: SslMode.disable),
      );

      final String vid = data['video_id'].toString();
      final String uid = data['viewer_uid'].toString(); 

      // 1. 🚀 THE GATEKEEPER: Check if they already viewed it!
      // (You must run a SQL command in Docker to CREATE TABLE viewed_videos first!)
      final checkExisting = await connection.execute(
        Sql.named("SELECT id FROM viewed_videos WHERE video_id = @vid AND viewer_uid = @uid LIMIT 1"),
        parameters: {'vid': vid, 'uid': uid}
      );

      if (checkExisting.isNotEmpty) {
        await connection.close();
        return Response(200, body: jsonEncode({'status': 'already_viewed'}));
      }

      // 2. Insert into the lockbox so they can never view it again
      await connection.execute(
        Sql.named("INSERT INTO viewed_videos (video_id, viewer_uid) VALUES (@vid, @uid)"),
        parameters: {'vid': vid, 'uid': uid}
      );

      // 3. Increase the official score
      await connection.execute(
        Sql.named("UPDATE user_videos SET view_count_local = view_count_local + 1 WHERE id = CAST(@vid AS UUID)"),
        parameters: {'vid': vid}
      );
      
      await connection.close();
      return Response(200, body: jsonEncode({'status': 'view_added'}));
    } catch (e) {
      return Response(500, body: 'View Error: $e');
    }
  });

  // 🚀 C. Toggle Subscription (Subscribe / Unsubscribe)
  router.post('/channel/subscribe/toggle', (Request req) async {
    try {
      final payload = await req.readAsString();
      final data = jsonDecode(payload);
      final channelId = data['channel_id'];
      final subscriberUid = data['subscriber_uid'];

      final connection = await Connection.open(
        Endpoint(host: 'db', port: 5432, database: 'postgres', username: 'postgres', password: 'GuptikSystemPassword2026'),
        settings: const ConnectionSettings(sslMode: SslMode.disable),
      );

      // Check if they are already subscribed
      final check = await connection.execute(
        Sql.named("SELECT 1 FROM channel_subscriptions WHERE subscriber_uid = @uid AND channel_id = @cid"),
        parameters: {'uid': subscriberUid, 'cid': channelId}
      );

      bool isSubscribed;
      if (check.isNotEmpty) {
        // They are subscribed -> UN-SUBSCRIBE them
        await connection.execute(
          Sql.named("DELETE FROM channel_subscriptions WHERE subscriber_uid = @uid AND channel_id = @cid"),
          parameters: {'uid': subscriberUid, 'cid': channelId}
        );
        await connection.execute(
          Sql.named("UPDATE user_channels SET subscriber_count = GREATEST(subscriber_count - 1, 0) WHERE channel_id = @cid"),
          parameters: {'cid': channelId}
        );
        isSubscribed = false;
      } else {
        // They are not subscribed -> SUBSCRIBE them
        await connection.execute(
          Sql.named("INSERT INTO channel_subscriptions (subscriber_uid, channel_id) VALUES (@uid, @cid)"),
          parameters: {'uid': subscriberUid, 'cid': channelId}
        );
        await connection.execute(
          Sql.named("UPDATE user_channels SET subscriber_count = subscriber_count + 1 WHERE channel_id = @cid"),
          parameters: {'cid': channelId}
        );
        isSubscribed = true;
      }

      await connection.close();
      return Response(200, body: jsonEncode({'is_subscribed': isSubscribed}), headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response(500, body: 'Error: $e');
    }
  });

  // 🚀 D. Check if a user is subscribed when loading the profile
  router.get('/channel/subscribe/status/<channelId>/<subscriberUid>', (Request req, String channelId, String subscriberUid) async {
    try {
      final connection = await Connection.open(
        Endpoint(host: 'db', port: 5432, database: 'postgres', username: 'postgres', password: 'GuptikSystemPassword2026'),
        settings: const ConnectionSettings(sslMode: SslMode.disable),
      );

      final check = await connection.execute(
        Sql.named("SELECT 1 FROM channel_subscriptions WHERE subscriber_uid = @uid AND channel_id = @cid"),
        parameters: {'uid': subscriberUid, 'cid': channelId}
      );
      await connection.close();
      
      return Response(200, body: jsonEncode({'is_subscribed': check.isNotEmpty}), headers: {'Content-Type': 'application/json'});
    } catch(e) {
      return Response(200, body: jsonEncode({'is_subscribed': false}), headers: {'Content-Type': 'application/json'}); 
    }
  });

// =========================================================================
  // 🚀 MOBILE CROSS-CONNECTION PUBLISHING GATEWAY
  // =========================================================================
  router.post('/player/video/upload', (Request req) async {
    try {
      // Decode secure URL-encoded parameters out of incoming client headers
      final videoId = req.headers['x-video-id'] ?? '';
      final creatorUid = req.headers['x-creator-uid'] ?? '';
      final title = Uri.decodeComponent(req.headers['x-title'] ?? '');
      final description = Uri.decodeComponent(req.headers['x-description'] ?? '');
      final category = req.headers['x-category'] ?? 'entertainment';
      final visibility = req.headers['x-visibility'] ?? 'public';
      final isReel = req.headers['x-is-reel'] == 'true';
      final isMonetized = req.headers['x-is-monetized'] == 'true';
      final channelName = Uri.decodeComponent(req.headers['x-channel-name'] ?? 'Mobile Creator');
      final tagsStr = Uri.decodeComponent(req.headers['x-tags'] ?? '');
      List<String> tags = tagsStr.split(',').where((t) => t.isNotEmpty).toList();

      if (videoId.isEmpty || creatorUid.isEmpty) {
        return Response.badRequest(body: 'Missing core tracking identifiers');
      }

      // 🚀 TARGET PATH DESIGN: Matches your video streaming fallback criteria perfectly!
      final filename = "$videoId.mp4";
      final file = File('/app/storage/$filename');
      
      // 🚀 THE FIX: Use addStream instead of pipe to handle the byte stream correctly
    final sink = file.openWrite();
    await sink.addStream(req.read());
    await sink.close();

      // Connect internally to your containerized Postgres database cluster
      final connection = await Connection.open(
        Endpoint(host: 'db', port: 5432, database: 'postgres', username: 'postgres', password: 'GuptikSystemPassword2026'),
        settings: const ConnectionSettings(sslMode: SslMode.disable),
      );

      // Verify or generate matching channel info inside your local node cache
      await connection.execute(
        Sql.named("INSERT INTO user_channels (channel_id, user_id, channel_name) VALUES (@cid, @uid, @cname) ON CONFLICT (channel_id) DO UPDATE SET channel_name = EXCLUDED.channel_name"),
        parameters: {'cid': creatorUid, 'uid': creatorUid, 'cname': channelName}
      );

      // Insert full metadata block using the exact schema definitions expected by your player APIs
      await connection.execute(
        Sql.named("""
          INSERT INTO user_videos 
          (id, channel_id, title, description, file_path, tags, category, visibility, is_reel, monetization_enabled) 
          VALUES (@vid::UUID, @cid, @title, @desc, @path, @tags, @cat, @vis, @reel, @mon)
        """),
        parameters: {
          'vid': videoId,
          'cid': creatorUid,
          'title': title,
          'desc': description,
          'path': "/app/storage/$filename",
          'tags': tags,
          'cat': category.toLowerCase(),
          'vis': visibility,
          'reel': isReel,
          'mon': isMonetized
        }
      );

      await connection.close();
      print('✅ Mobile Stream Upload successfully integrated into local user_videos tables!');
      
      return Response.ok(jsonEncode({'status': 'success', 'video_id': videoId}));
    } catch (e) {
      print("❌ Mobile Cross-Connection processing error: $e");
      return Response.internalServerError(body: 'Gateway Media Sync breakdown: $e');
    }
  });


  // -------------------------------------------------------------------------
  // 🚀 TRUST ME WEBRTC (AUDIO/VIDEO) SIGNALING ENDPOINTS
  // -------------------------------------------------------------------------

  router.post('/trustme/call/initiate', (Request req) async {
    try {
      final payload = await req.readAsString();
      final data = jsonDecode(payload);
      final connection = await Connection.open(
        Endpoint(host: 'db', port: 5432, database: 'postgres', username: 'postgres', password: 'GuptikSystemPassword2026'),
        settings: const ConnectionSettings(sslMode: SslMode.disable),
      );
      
      final callId = uuid.v4();
      await connection.execute(
        Sql.named("INSERT INTO tm_call_log (call_id, contact_guptik_id, call_type, direction, status, sdp_offer) VALUES (@cid, @gid, @type, 'outgoing', 'ringing', @offer)"),
        parameters: {
          'cid': callId, 'gid': data['contact_guptik_id'], 'type': data['call_type'] ?? 'video', 'offer': data['sdp_offer']
        }
      );
      await connection.close();
      return Response.ok(jsonEncode({'status': 'initiated', 'call_id': callId}));
    } catch (e) {
      return Response.internalServerError(body: 'Call Init Error: $e');
    }
  });

  router.post('/trustme/call/accept/<callId>', (Request req, String callId) async {
    try {
      final payload = await req.readAsString();
      final data = jsonDecode(payload);
      final connection = await Connection.open(
        Endpoint(host: 'db', port: 5432, database: 'postgres', username: 'postgres', password: 'GuptikSystemPassword2026'),
        settings: const ConnectionSettings(sslMode: SslMode.disable),
      );
      
      await connection.execute(
        Sql.named("UPDATE tm_call_log SET status = 'answered', sdp_answer = @ans, answered_at = NOW() WHERE call_id = @cid"),
        parameters: {'cid': callId, 'ans': data['sdp_answer']}
      );
      await connection.close();
      return Response.ok(jsonEncode({'status': 'accepted'}));
    } catch (e) {
      return Response.internalServerError(body: 'Call Accept Error: $e');
    }
  });

  router.post('/trustme/call/ice-candidate/<callId>', (Request req, String callId) async {
    try {
      final payload = await req.readAsString();
      final data = jsonDecode(payload);
      final connection = await Connection.open(
        Endpoint(host: 'db', port: 5432, database: 'postgres', username: 'postgres', password: 'GuptikSystemPassword2026'),
        settings: const ConnectionSettings(sslMode: SslMode.disable),
      );
      
      await connection.execute(
        Sql.named("UPDATE tm_call_log SET ice_candidates = ice_candidates || @candidate::jsonb WHERE call_id = @cid"),
        parameters: {'cid': callId, 'candidate': jsonEncode([data['candidate']])}
      );
      await connection.close();
      return Response.ok(jsonEncode({'status': 'candidate_stored'}));
    } catch (e) {
      return Response.internalServerError(body: 'ICE Error: $e');
    }
  });

  router.get('/', (Request req) => Response.ok('GUPTIK GATEWAY ONLINE'));

  // 🚀 BACKGROUND WORKER: Automatically retries queued messages every 10 seconds!
  Timer.periodic(const Duration(seconds: 10), (timer) async {
    try {
      final conn = await Connection.open(
        Endpoint(host: 'db', port: 5432, database: 'postgres', username: 'postgres', password: 'GuptikSystemPassword2026'),
        settings: const ConnectionSettings(sslMode: SslMode.disable),
      );
      
      // Find texts sent by ME that haven't reached the peer yet
      final pending = await conn.execute("""
        SELECT m.id, m.sender_guptik_id, m.sender_username, m.content_encrypted, m.content_type, ct.contact_cloudflare_url
        FROM tm_messages m
        JOIN tm_conversations c ON c.id = m.conversation_id
        JOIN tm_contacts ct ON ct.id = c.contact_id
        WHERE m.is_delivered = false 
          AND m.sender_guptik_id != ct.contact_guptik_id 
          AND m.content_encrypted NOT LIKE '[media]%'
      """);
      
      for (final row in pending) {
        final msgId = row[0].toString();
        final senderId = row[1].toString();
        final senderUsername = row[2].toString();
        final content = row[3].toString();
        final type = row[4].toString();
        var targetUrl = row[5].toString();
        if (!targetUrl.startsWith('http')) targetUrl = 'https://$targetUrl';
        
        try {
          final response = await http.post(
            Uri.parse('$targetUrl/trustme/message/receive'),
            headers: {'Content-Type': 'application/json', 'X-Sender-ID': senderId},
            body: jsonEncode({
              'message_id': msgId,
              'sender_username': senderUsername,
              'content_encrypted': content,
              'content_type': type,
              'nonce': 'retry_nonce'
            }),
          ).timeout(const Duration(seconds: 5));
          
          if (response.statusCode == 200) {
            await conn.execute(
              Sql.named('UPDATE tm_messages SET is_delivered = true, delivered_at = NOW() WHERE id = @mid'),
              parameters: {'mid': msgId}
            );
          }
        } catch (_) {}
      }
      await conn.close();
    } catch (e) {}
  });

  final handler = Pipeline().addMiddleware(logRequests()).addHandler(router.call);
  final server = await serve(handler, InternetAddress.anyIPv4, 8080);
  print('Gateway listening on port ${server.port}');
}
''');
  }

  Future<void> stopStack() async {
    try {
      if (_vaultPath == null) throw Exception("Vault path not set");
      final result = await Process.run('docker-compose', ['-f', 'docker-compose.yml', 'down'], workingDirectory: _vaultPath);
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
    
    print("🚀 Starting Docker stack at: $_vaultPath");
    
    // Check if docker-compose.yml exists
    final composeFile = File('$_vaultPath/docker-compose.yml');
    if (!await composeFile.exists()) {
      print("⚠️ docker-compose.yml not found at $_vaultPath - skipping Docker startup");
      print("ℹ️ Assuming Docker is already running or containers are managed externally");
      return;
    }
    print("✅ Found docker-compose.yml");

    final shell = Shell(
      workingDirectory: _vaultPath, 
      environment: Platform.environment, 
      throwOnError: false
    );
    
    String dockerCmd = 'docker';
    if (Platform.isLinux || Platform.isMacOS) {
      final which = await shell.run('which docker');
      if (which.first.exitCode == 0) {
        dockerCmd = which.first.stdout.toString().trim();
      }
    }
    
    print("🐳 Docker command: $dockerCmd");

    try {
      print("📦 Pulling Docker images...");
      await shell.run('$dockerCmd compose pull --quiet');
      print("✅ Images pulled");
    } catch (e) {
      print("⚠️ Pull failed (might already have images): $e");
    }

    try {
      print("🔥 Starting containers with compose up...");
      final upResult = await shell.run('$dockerCmd compose up -d --build --remove-orphans');
      if (upResult.first.exitCode != 0) {
        print("⚠️ Compose up stderr: ${upResult.first.stderr}");
      }
      print("✅ Compose up completed");
    } catch (e) {
      print("❌ Failed to start Docker: $e");
      rethrow;
    }

    // 🚀 HEALTH CHECK: Wait for Postgres to actually be ready
    print("⏳ Waiting for Postgres to be ready...");
    int healthRetries = 0;
    bool isHealthy = false;
    
    while (healthRetries < 20 && !isHealthy) {
      try {
        final checkResult = await shell.run('$dockerCmd compose ps db');
        if (checkResult.first.exitCode == 0) {
          final psOutput = checkResult.first.stdout.toString();
          if (psOutput.contains('Up') && !psOutput.contains('Restarting')) {
            print("✅ Postgres container is Up");
            isHealthy = true;
            break;
          }
        }
      } catch (e) {
        print("Health check attempt ${healthRetries + 1}/20 failed: $e");
      }
      
      healthRetries++;
      await Future.delayed(const Duration(seconds: 2));
    }

    if (!isHealthy) {
      print("⚠️ Postgres health check failed, but continuing (container might be starting)");
    } else {
      print("✅ Docker stack is healthy and ready");
    }
  }
}