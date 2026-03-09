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
            host:
                'db', // Matches the name of your Postgres container in docker-compose!
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
  
  // 2. DOWNLOAD FILE
  router.get('/vault/files/<filename>', (Request req, String filename) async {
    final file = File('/app/storage/$filename');
    if (!await file.exists()) return Response.notFound('File not found');
    final mimeType = lookupMimeType(file.path) ?? 'application/octet-stream';
    return Response.ok(file.openRead(), headers: {'Content-Type': mimeType});
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
      final response = await http.get(Uri.parse('http://ollama:11434/api/tags'));
      return Response.ok(response.body, headers: {'Content-Type': 'application/json'});
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
      final proxyReq = http.Request('POST', Uri.parse('http://ollama:11434/api/chat'));
      proxyReq.headers['Content-Type'] = 'application/json';
      proxyReq.body = payload;

      final response = await client.send(proxyReq);

      // Pipe the stream directly back to the mobile app!
      return Response.ok(
        response.stream, 
        headers: {'Content-Type': 'application/json'}
      );
    } catch (e) {
      print("Error streaming from Ollama: $e");
      return Response.internalServerError(body: 'AI Offline');
    }
  });
  
  router.get('/', (Request req) => Response.ok('GUPTIK GATEWAY ONLINE'));

  final handler = Pipeline().addMiddleware(logRequests()).addHandler(router.call);
  final server = await serve(handler, InternetAddress.anyIPv4, 8080);
  print('Gateway listening on port ${server.port}');

  // 6. DELETE FILE (Removes physical file AND database row)
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
        print(
          'Physical file not found, but continuing to database cleanup.',
        );
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
