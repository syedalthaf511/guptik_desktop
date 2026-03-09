// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:convert';
import 'package:guptik_desktop/services/external/postgres_service.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';

class NexusServer {
  HttpServer? _server;
  final int port = 8080;

  final PostgresService _db = PostgresService();

  Future<void> start(String vaultPath) async {
    await _db.connect();
    print("✅ Database Connected");

    final vaultDir = Directory(vaultPath);
    if (!await vaultDir.exists()) {
      await vaultDir.create(recursive: true);
    }

    final router = Router();

    // =================================================================
    // 1. VAULT: Upload Endpoint
    // =================================================================
    router.post('/vault/upload/<fileName>', (
      Request request,
      String fileName,
    ) async {
      try {
        // A. Save file to disk
        final savePath = '$vaultPath${Platform.pathSeparator}$fileName';
        final file = File(savePath);

        final sink = file.openWrite();
        await request.read().pipe(sink);
        await sink.close();

        // B. Save metadata to Database
        try {
          final int fileSize = await file.length();
          final String mimeType = _getMimeType(fileName);

          await _db.saveVaultFileLocal(
            fileName: fileName,
            filePath: savePath,
            fileSize: fileSize,
            mimeType: mimeType,
          );

          return Response.ok(
            jsonEncode({"status": "saved", "path": fileName}),
            headers: {'Content-Type': 'application/json'},
          );
        } catch (dbError) {
          // 👇 THIS IS THE FIX! We send the error back to the phone!
          return Response.internalServerError(body: 'DATABASE_ERROR: $dbError');
        }
      } catch (e) {
        return Response.internalServerError(body: 'Upload failed: $e');
      }
    });

    // =================================================================
    // 2. VAULT: Download Endpoint
    // =================================================================
    router.get('/vault/file/<fileId>', (Request request, String fileId) {
      if (fileId.contains('..')) return Response.forbidden('Invalid filename');
      final file = File('$vaultPath${Platform.pathSeparator}$fileId');
      if (!file.existsSync()) return Response.notFound('File not found');
      return Response.ok(
        file.openRead(),
        headers: {
          'Content-Type': 'application/octet-stream',
          'Content-Disposition': 'attachment; filename="$fileId"',
        },
      );
    });

    // =================================================================
    // 3. VAULT: List Files Endpoint
    // =================================================================
    router.get('/vault/get_synced_ids', (Request request) {
      final directory = Directory(vaultPath);
      List<String> fileNames = [];
      try {
        if (directory.existsSync()) {
          for (var entity in directory.listSync()) {
            if (entity is File) {
              fileNames.add(entity.path.split(Platform.pathSeparator).last);
            }
          }
        }
        return Response.ok(
          jsonEncode(fileNames),
          headers: {'Content-Type': 'application/json'},
        );
      } catch (e) {
        return Response.internalServerError(body: 'Error reading files');
      }
    });

    final handler = Pipeline()
        .addMiddleware(logRequests())
        .addHandler(router.call);
    _server = await io.serve(handler, InternetAddress.anyIPv4, port);
    print('✅ Nexus Server running on port ${_server?.port}');
  }

  Future<void> stop() async {
    await _db.close();
    await _server?.close();
  }

  String _getMimeType(String path) {
    final ext = path.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'pdf':
        return 'application/pdf';
      case 'mp4':
        return 'video/mp4';
      case 'mp3':
        return 'audio/mpeg';
      case 'zip':
        return 'application/zip';
      default:
        return 'application/octet-stream';
    }
  }
}
