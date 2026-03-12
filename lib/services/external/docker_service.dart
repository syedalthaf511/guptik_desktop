import 'dart:io';
import 'package:process_run/shell.dart';

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

    // 1. PRE-CREATE ALL DIRECTORIES
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

    // 2. Generate .env
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

    // 3. Generate Gateway Code
    await _generateGatewayFiles(publicUrl);

    // 4. Generate docker-compose.yml
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
    image: postgres:15-alpine # <--- SWITCHED TO FAST, LIGHTWEIGHT POSTGRES
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
    // 1. pubspec.yaml
    final pubspec = File('$_vaultPath/gateway/pubspec.yaml');
    await pubspec.writeAsString('''
name: guptik_gateway
environment: {sdk: '>=3.0.0 <4.0.0'}
dependencies: {shelf: ^1.4.0, shelf_router: ^1.1.0, http: ^1.1.0, mime: ^1.0.4,postgres: ^3.4.0}
''');

    // 2. server.dart (BULLETPROOF VERSION)
    final server = File('$_vaultPath/gateway/server.dart');
    await server.writeAsString(r'''
import 'dart:io';
import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:http/http.dart' as http;
import 'package:mime/mime.dart';
import 'package:postgres/postgres.dart';

void main() async {
  final router = Router();

  // DEBUG: Print startup
  print('Guptik Gateway Starting...');

  // Ensure storage directory exists
  final storageDir = Directory('/app/storage');
  if (!await storageDir.exists()) {
    print('Creating storage directory at /app/storage');
    await storageDir.create(recursive: true);
  }

  // 1. UPLOAD FILE (Robust Stream Handling)
  router.post('/vault/upload/<filename>', (Request req, String filename) async {
    IOSink? sink;
    try {
      print('Starting upload for: $filename');
      final file = File('/app/storage/$filename');

      // Use explicit sink control instead of pipe()
      sink = file.openWrite();
      await sink.addStream(req.read());
      await sink.flush();
      await sink.close();

      final size = await file.length();
      final mimeType = lookupMimeType(file.path) ?? 'application/octet-stream';
      print('Upload complete. Size: $size bytes');

      // --- NEW DATABASE SYNC LOGIC ---
      try {
        print('Connecting to Postgres database...');
        final connection = await Connection.open(
          Endpoint(
            host: 'db', 
            port: 5432,
            database: 'postgres',
            username: 'postgres',
            password: 'GuptikSystemPassword2026',
          ),
          settings: const ConnectionSettings(sslMode: SslMode.disable),
        );

        print('Inserting file metadata into vault_files table...');
        await connection.execute(
          Sql.named(
            'INSERT INTO vault_files (file_name, file_path, file_size, mime_type) VALUES (@fn, @fp, @fs, @mt)',
          ),
          parameters: {
            'fn': filename,
            'fp': file.path,
            'fs': size,
            'mt': mimeType,
          },
        );

        await connection.close();
        print('Database insert successful!');
      } catch (dbError) {
        print('DATABASE ERROR: $dbError');
      }
      // -------------------------------

      return Response.ok(
        jsonEncode({'status': 'saved', 'path': filename, 'size': size}),
      );
    } catch (e, stack) {
      print('UPLOAD FAILED: $e');
      print(stack);

      // Attempt to close sink if open
      try {
        await sink?.close();
      } catch (_) {}

      // Return plain text error so it shows in curl
      return Response.internalServerError(body: 'UPLOAD ERROR: $e');
    }
  });

  // 2. DOWNLOAD / VIEW FILE (WITH ENTERPRISE SECURITY & EMAIL VERIFICATION)
  router.get('/vault/files/<filename>', (Request req, String filename) async {
    print('\n--- NEW REQUEST FOR FILE: $filename ---');
    try {
      final token = req.url.queryParameters['token'];
      final email = req.url.queryParameters['email'];
      print('Token provided: $token');
      print('Email provided: $email');

      print('Connecting to Postgres...');
      final connection = await Connection.open(
        Endpoint(
          host: 'db',
          port: 5432,
          database: 'postgres',
          username: 'postgres',
          password: 'GuptikSystemPassword2026',
        ),
        settings: const ConnectionSettings(sslMode: SslMode.disable),
      );

      print('Connected. Looking up file share rules...');
      // 🛡️ FIXED: USING TRIPLE DOUBLE-QUOTES HERE
      final result = await connection.execute(
        Sql.named("""
          SELECT is_public, access_token, emails_access_to, expires_at 
          FROM vault_share_file 
          WHERE file_name = @fn 
          ORDER BY created_at DESC LIMIT 1
        """),
        parameters: {'fn': filename},
      );

      await connection.close();
      print('Database query complete.');

      if (result.isEmpty) {
        print('Result is empty - file not shared.');
        return Response.forbidden(
          'Access Denied: This file has not been shared.',
        );
      }

      final row = result.first;
      final isPublic = row[0] as bool;
      final dbToken = row[1]?.toString();

      // 🛡️ ULTRA-SAFE ARRAY PARSING (Handles both Lists and Strings perfectly)
      List<String> allowedEmails = [];
      if (row[2] != null) {
        if (row[2] is List) {
          allowedEmails = (row[2] as List)
              .map((e) => e.toString().toLowerCase().trim())
              .toList();
        } else if (row[2] is String) {
          String cleanString = row[2]
              .toString()
              .replaceAll('{', '')
              .replaceAll('}', '');
          allowedEmails = cleanString
              .split(',')
              .map((e) => e.toLowerCase().trim())
              .toList();
        }
      }
      final expiresAt = row[3] as DateTime?;

      print('Is Public: $isPublic');
      print('Allowed Emails: $allowedEmails');

      if (expiresAt != null && DateTime.now().toUtc().isAfter(expiresAt)) {
        print('Link expired.');
        return Response.forbidden('This link has expired.');
      }

      // PRIVATE FILE LOGIC
      if (!isPublic) {
        if (token != dbToken) {
          print('Token mismatch. Provided: $token, Required: $dbToken');
          return Response.forbidden('Invalid or missing access token.');
        }

        if (email == null || email.isEmpty) {
          print('No email provided, serving HTML login page...');
          // 🛡️ FIXED: USING TRIPLE DOUBLE-QUOTES HERE
          final html =
              """
            <!DOCTYPE html>
            <html>
            <head>
              <meta name="viewport" content="width=device-width, initial-scale=1">
              <title>Guptik Secure Vault</title>
            </head>
            <body style="font-family: Arial, sans-serif; display: flex; justify-content: center; align-items: center; height: 100vh; background-color: #0F172A; color: white; margin: 0;">
              <div style="background: #1E293B; padding: 40px; border-radius: 12px; text-align: center; box-shadow: 0 4px 15px rgba(0,0,0,0.5); max-width: 400px; width: 90%;">
                <h2 style="color: #00E5FF; margin-top: 0;">Secure File Access</h2>
                <p style="color: #94A3B8; font-size: 14px; margin-bottom: 24px;">This file is protected. Please enter your authorized email address to view it.</p>
                <form method="GET">
                  <input type="hidden" name="token" value="${token ?? ''}" />
                  <input type="email" name="email" placeholder="Enter your email" required style="box-sizing: border-box; padding: 12px; width: 100%; margin-bottom: 20px; border-radius: 6px; border: 1px solid #334155; background: #0F172A; color: white; outline: none;" />
                  <button type="submit" style="background: #00E5FF; color: black; padding: 12px 20px; width: 100%; border: none; border-radius: 6px; font-weight: bold; font-size: 16px; cursor: pointer;">Verify & View File</button>
                </form>
              </div>
            </body>
            </html>
          """;
          return Response.ok(html, headers: {'Content-Type': 'text/html'});
        }

        if (!allowedEmails.contains(email.toLowerCase().trim())) {
          print('Email unauthorized: $email');
          return Response.forbidden(
            'Access Denied: Your email is not authorized to view this file.',
          );
        }
      }

      print('Serving actual file: $filename');
      final file = File('/app/storage/$filename');
      if (!await file.exists()) {
        print('File physically missing from disk.');
        return Response.notFound('File not found on server storage.');
      }

      final mimeType = lookupMimeType(file.path) ?? 'application/octet-stream';
      return Response.ok(
        file.openRead(),
        headers: {
          'Content-Type': mimeType,
          'Content-Length': (await file.length()).toString(),
          'Content-Disposition': 'inline; filename="$filename"',
        },
      );
    } catch (e, stack) {
      print('CRITICAL SERVER ERROR: $e');
      print(stack);
      return Response.internalServerError(body: 'Server Error');
    }
  });

  // 3. LIST FILES
  router.get('/vault/list', (Request req) {
    try {
      final dir = Directory('/app/storage');
      if (!dir.existsSync()) return Response.ok('[]');

      final files = dir
          .listSync()
          .whereType<File>()
          .map(
            (f) => {
              'name': f.uri.pathSegments.last,
              'size': f.lengthSync(),
              'modified': f.lastModifiedSync().toIso8601String(),
            },
          )
          .toList();

      return Response.ok(
        jsonEncode(files),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(body: 'List Error: $e');
    }
  });

  // ---------------------------------------------------------
  // 4. NEW OLLAMA PROXY - GET MODELS (/api/tags)
  // ---------------------------------------------------------
  router.get('/api/tags', (Request req) async {
    try {
      // Forward the exact request to the Ollama container
      final response = await http.get(
        Uri.parse('http://ollama:11434/api/tags'),
      );
      return Response.ok(
        response.body,
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      print("Error fetching models from Ollama: $e");
      return Response.internalServerError(body: 'AI Offline');
    }
  });

  // ---------------------------------------------------------
  // 5. NEW OLLAMA PROXY - STREAMING CHAT (/api/chat)
  // ---------------------------------------------------------
  router.post('/api/chat', (Request req) async {
    try {
      final payload = await req.readAsString();

      // We use a streamed client so we can pass the typing effect back to the phone
      final client = http.Client();
      final proxyReq = http.Request(
        'POST',
        Uri.parse('http://ollama:11434/api/chat'),
      );
      proxyReq.headers['Content-Type'] = 'application/json';
      proxyReq.body = payload;

      final response = await client.send(proxyReq);

      // Pipe the stream directly back to the mobile app!
      return Response.ok(
        response.stream,
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      print("Error streaming from Ollama: $e");
      return Response.internalServerError(body: 'AI Offline');
    }
  });

  router.get('/', (Request req) => Response.ok('GUPTIK GATEWAY ONLINE'));

  // 6. RECEIVE SHARE RULES FROM MOBILE
  router.post('/vault/share', (Request req) async {
    try {
      final payload = await req.readAsString();
      final data = jsonDecode(payload);

      final connection = await Connection.open(
        Endpoint(
          host: 'db',
          port: 5432,
          database: 'postgres',
          username: 'postgres',
          password: 'GuptikSystemPassword2026',
        ),
        settings: const ConnectionSettings(sslMode: SslMode.disable),
      );

      await connection.execute(
        Sql.named("""
          INSERT INTO vault_share_file (file_name, file_path, is_public, access_token, emails_access_to, created_at, expires_at) 
          VALUES (@fn, @fp, @pub, @tok, @em, @ca, @ea)
        """),
        parameters: {
          'fn': data['file_name'],
          'fp': data['file_path'],
          'pub': data['is_public'],
          'tok': data['access_token'],
          'em': data['emails_access_to'],
          // Convert the strings from the mobile app back into real database times!
          'ca': DateTime.parse(data['created_at']), 
          'ea': data['expires_at'] != null ? DateTime.parse(data['expires_at']) : null,
        },
      );

      await connection.close();
      return Response.ok(jsonEncode({'status': 'success'}));
    } catch (e) {
      print('SHARE ERROR: $e');
      return Response.internalServerError(body: 'Share Error: $e');
    }
  });

  // 7. DELETE FILE (Removes physical file AND database row)
  router.delete('/vault/delete/<filename>', (
    Request req,
    String filename,
  ) async {
    try {
      print('Attempting to fully delete: $filename');

      // 1. Delete the physical file from the hard drive
      final file = File('/app/storage/$filename');
      if (await file.exists()) {
        await file.delete();
        print('Physical file deleted from storage.');
      } else {
        print('Physical file not found, but continuing to database cleanup.');
      }

      // 2. Delete the record from the Postgres database
      final connection = await Connection.open(
        Endpoint(
          host: 'db',
          port: 5432,
          database: 'postgres',
          username: 'postgres',
          password: 'GuptikSystemPassword2026',
        ),
        settings: const ConnectionSettings(sslMode: SslMode.disable),
      );

      await connection.execute(
        Sql.named('DELETE FROM vault_files WHERE file_name = @fn'),
        parameters: {'fn': filename},
      );

      await connection.close();
      print('Database record deleted.');

      return Response.ok(jsonEncode({'status': 'deleted', 'file': filename}));
    } catch (e) {
      print('DELETE ERROR: $e');
      return Response.internalServerError(body: 'Delete Error: $e');
    }
  });

  // 🛡️ FIXED: SERVER STARTUP IS NOW AT THE VERY BOTTOM!
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
      if (_vaultPath == null)
        throw Exception("Vault path not set"); // <--- Added underscore

      // Run docker-compose down
      final result = await Process.run(
        'docker-compose',
        ['-f', 'docker-compose.yml', 'down'],
        workingDirectory: _vaultPath, // <--- Added underscore
      );

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
      if (which.first.exitCode == 0)
        dockerCmd = which.first.stdout.toString().trim();
    }

    await shell.run('$dockerCmd compose pull');
    // Force rebuild to update server.dart
    await shell.run('$dockerCmd compose up -d --build --remove-orphans');
  }
}
