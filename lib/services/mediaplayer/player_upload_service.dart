import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:postgres/postgres.dart'; 
import '../external/docker_service.dart';

class PlayerUploadService {
  final _supabase = Supabase.instance.client;
  
  // Local Docker Postgres connection details
  final String _localDbHost = '127.0.0.1'; 
  final int _localDbPort = 55432; 
  final String _dbName = 'postgres';
  final String _dbUser = 'postgres';
  final String _dbPass = 'GuptikSystemPassword2026';

  // 🚀 MOVED: Helper function is now a class method
  Future<void> syncChannelToAdmin(String userId, String channelName) async {
    try {
      await _supabase.from('mp_channels').upsert({
        'owner_uid': userId,
        'channel_id': userId, 
        'channel_name': channelName,
      }, onConflict: 'channel_id');
      
      debugPrint("✅ Admin Sync: Channel '$channelName' registered in mp_channels.");
    } catch (e) {
      debugPrint("❌ Admin Sync Error: $e");
    }
  }

  Future<bool> publishVideo({
    required String title,
    required String description,
    required String realLocalFilePath, 
    required List<String> tags, 
    required String category,
    required String visibility,
    required bool isReel,
    required bool isMonetized,
    required bool madeForKids,
    required bool ageRestricted,
    required String channelName,
  }) async {
    final videoId = const Uuid().v4();
    final vaultFileName = '$videoId.mp4';
    final dockerFilePath = '/app/storage/$vaultFileName'; 

    final currentUser = _supabase.auth.currentUser;
    if (currentUser == null) {
      debugPrint("❌ ERROR: User is not logged into Supabase.");
      return false;
    }

    // ==========================================
    // STEP 1: PHYSICAL FILE COPY
    // ==========================================
    const secureStorage = FlutterSecureStorage();
    final dynamicVaultPath = await secureStorage.read(key: 'vault_path');
    final rawPublicUrl = await secureStorage.read(key: 'public_url') ?? 'https://your-node.trycloudflare.com';
    // 🚀 Strip any stray whitespace (e.g. "1 758") that corrupts the hostname and breaks DNS.
    final publicUrl = DockerService.sanitizeTunnelUrl(rawPublicUrl);
    
    if (dynamicVaultPath == null) return false; 

    try {
      final localVaultDirectory = Directory('$dynamicVaultPath\\vault_files\\'); 
      if (!await localVaultDirectory.exists()) await localVaultDirectory.create(recursive: true);
      await File(realLocalFilePath).copy('${localVaultDirectory.path}\\$vaultFileName');

      // 🚀 THE FIX: COPY THE THUMBNAIL NEXT TO THE VIDEO WITH THE SAME UUID
      final originalThumbPath = realLocalFilePath.replaceAll(RegExp(r'\.[^.]+$'), '.jpg');
      final vaultThumbName = '$videoId.jpg'; // Matches the new Video ID
      if (await File(originalThumbPath).exists()) {
        await File(originalThumbPath).copy('${localVaultDirectory.path}\\$vaultThumbName');
        debugPrint("✅ Thumbnail copied to Vault as $vaultThumbName");
      }

    } catch (e) {
      debugPrint("❌ STEP 1 ERROR: File copy failed. $e");
      return false;
    }

    // ==========================================
    // STEP 2: SUPABASE GLOBAL SYNC (mp_videos & mp_channels)
    // ==========================================
    try {
      // 1. Sync the Channel name to Admin
      await syncChannelToAdmin(currentUser.id, channelName);

      // 2. Sync the Video to Admin
      await _supabase.from('mp_videos').insert({
        'video_id': videoId,
        'creator_uid': currentUser.id,
        'channel_name': channelName,
        'title': title,
        'description': description,
        'tags': tags,
        'creator_cloudflare_url': publicUrl, 
        'thumbnail_url': '$publicUrl/player/video/thumbnail/$videoId', 
        'category': category.toLowerCase(),
        'visibility': visibility,
        'is_reel': isReel,
        'is_monetized': isMonetized,
        'made_for_kids': madeForKids,
        'age_rating': ageRestricted ? '18+' : 'all',
      });
      debugPrint("✅ STEP 2 SUCCESS: Synced to Global Supabase.");
    } catch (e) {
      debugPrint("❌ STEP 2 ERROR: Supabase Sync Failed. $e");
      return false; 
    }

    // ==========================================
    // STEP 3: DOCKER POSTGRES LOCAL SYNC (mp_videos)
    // ==========================================
    try {
      final connection = await Connection.open(
        Endpoint(host: _localDbHost, port: _localDbPort, database: _dbName, username: _dbUser, password: _dbPass),
        settings: const ConnectionSettings(sslMode: SslMode.disable),
      );

      await connection.execute(
        Sql.named("""
          INSERT INTO mp_channels (channel_id, user_id, channel_name, monetization_enabled) 
          VALUES (@cid, @uid, @cname, @mon) 
          ON CONFLICT (channel_id) 
          DO UPDATE SET channel_name = EXCLUDED.channel_name,
                        monetization_enabled = EXCLUDED.monetization_enabled
        """),
        parameters: {
          'cid': currentUser.id, 
          'uid': currentUser.id,
          'cname': channelName,
          'mon': isMonetized,
        }
      );

      await connection.execute(
        Sql.named("""
          INSERT INTO mp_videos 
          (id, channel_id, title, description, file_path, tags, category, visibility, is_reel, monetization_enabled, made_for_kids, age_rating) 
          VALUES (@vid::UUID, @cid, @title, @desc, @path, @tags, @cat, @vis, @reel, @mon, @kids, @age)
        """),
        parameters: {
          'vid': videoId,
          'cid': currentUser.id,
          'title': title,
          'desc': description,
          'path': dockerFilePath,
          'tags': tags,
          'cat': category.toLowerCase(),
          'vis': visibility,
          'reel': isReel,
          'mon': isMonetized,
          'kids': madeForKids,
          'age': ageRestricted ? '18+' : 'all',
        }
      );
      
      await connection.close();
      return true;
    } catch (e) {
      debugPrint("❌ STEP 3 ERROR: Docker Postgres Connection Failed. $e");
      return false; 
    }
  }
}