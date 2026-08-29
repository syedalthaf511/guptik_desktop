import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:postgres/postgres.dart';
import 'package:supabase_flutter/supabase_flutter.dart'; // 🚀 Added to fetch global reposts
import '../../models/mediaplayer/player_video_model.dart';
import '../../widgets/mediaplayer/player_video_card.dart';
import '../../services/external/postgres_service.dart';

class DesktopSystemFolderScreen extends StatefulWidget {
  final String folderType; // 'posted', 'saved', 'drafts', 'repost', or 'stickers'
  final String folderTitle;
  final IconData folderIcon;
  final Color folderColor;

  const DesktopSystemFolderScreen({
    super.key, 
    required this.folderType,
    required this.folderTitle,
    required this.folderIcon,
    required this.folderColor,
  });

  @override
  State<DesktopSystemFolderScreen> createState() => _DesktopSystemFolderScreenState();
}

class _DesktopSystemFolderScreenState extends State<DesktopSystemFolderScreen> {
  List<PlayerVideo> _videos = [];
  bool _isLoading = true;
  String? _publicUrl;

  @override
  void initState() {
    super.initState();
    _loadFolderData();
  }

  Future<void> _loadFolderData() async {
    try {
      // 1. Get the local node URL for the video cards
      const secureStorage = FlutterSecureStorage();
      _publicUrl = await secureStorage.read(key: 'public_url') ?? 'localhost';
      
      // 2. Parse fallback layout constraints directly on raw system properties
      final safeUrl = _publicUrl!.startsWith('http') 
          ? _publicUrl! 
          : (_publicUrl!.contains('localhost') || _publicUrl!.contains('127.0.0.1') || _publicUrl!.contains(':'))
              ? 'http://$_publicUrl'
              : 'https://$_publicUrl';

      final List<PlayerVideo> loadedVideos = [];

      // 🚀 THE FIX: Reposts must be fetched from Supabase, not local Postgres!
      // Since reposts belong to other creators, your local mp_videos table doesn't have the files.
    // 🚀 THE FIX: Reposts must be fetched from Supabase, not local Postgres!
      if (widget.folderType == 'repost') {
        final supabase = Supabase.instance.client;
        final currentUser = supabase.auth.currentUser;
        if (currentUser != null) {
          // 1. Fetch this user's repost rows (NO JOINS!)
          final response = await supabase
              .from('mp_videos')
              .select('*')
              .eq('creator_uid', currentUser.id)
              .not('repost_id', 'is', null)
              .order('published_at', ascending: false);

          final List<Map<String, dynamic>> userReposts = List<Map<String, dynamic>>.from(response as List);
          final List<String> repostIds = userReposts.map((v) => v['repost_id'].toString()).toList();

          // 2. Fetch the original physical videos
          if (repostIds.isNotEmpty) {
            final originalsResponse = await supabase
                .from('mp_videos')
                .select('*')
                .filter('id', 'in', repostIds);
                
            final Map<String, Map<String, dynamic>> origMap = {};
            for (final o in originalsResponse as List) {
              origMap[o['id'].toString()] = Map<String, dynamic>.from(o);
            }

            // 3. Inject the real physical video metadata into the UI
            for (final v in userReposts) {
              final orig = origMap[v['repost_id'].toString()];
              if (orig != null) {
                // 🚀 ID SWAP: Ensures the Vault player requests the real video file!
                v['video_id'] = orig['video_id'] ?? orig['id'];
                v['id'] = orig['id'];
                v['creator_uid'] = orig['creator_uid'];
                v['creator_cloudflare_url'] = orig['creator_cloudflare_url'];
                v['thumbnail_url'] = orig['thumbnail_url'];
                v['original_channel_name'] = orig['channel_name'];
                v['is_repost'] = true;

                final nodeUrl = v['creator_cloudflare_url'] ?? safeUrl;
                loadedVideos.add(PlayerVideo.fromJson(v, nodeUrl));
              }
            }
          }
        }
      } else {
        // 3. Connect directly to the local Postgres Node for local folders!
        final connection = await Connection.open(
          Endpoint(host: 'localhost', port: 55432, database: 'postgres', username: 'postgres', password: PostgresService.dockerMasterPassword),
          settings: const ConnectionSettings(sslMode: SslMode.disable),
        );

        Result? result;

        // 4. DYNAMIC ROUTING: Fetch different data based on the folder!
        if (widget.folderType == 'posted') {
          result = await connection.execute('''
            SELECT v.id, v.title, v.description, v.file_path, v.view_count_local, 
                   v.like_count_local, v.comment_count_local, c.channel_name, v.is_reel, v.upload_timestamp, c.channel_id
            FROM mp_videos v
            JOIN mp_channels c ON v.channel_id = c.channel_id
            WHERE v.is_deleted = false
            ORDER BY v.upload_timestamp DESC
          ''');
        } else if (widget.folderType == 'saved') {
          result = await connection.execute('''
            SELECT v.id, v.title, v.description, v.file_path, v.view_count_local, 
                   v.like_count_local, v.comment_count_local, c.channel_name, v.is_reel, s.saved_timestamp, c.channel_id
            FROM mp_saved_videos s
            JOIN mp_videos v ON s.video_id = v.id::text
            JOIN mp_channels c ON v.channel_id = c.channel_id
            ORDER BY s.saved_timestamp DESC
          ''');
        } else if (widget.folderType == 'drafts') {
          result = await connection.execute('''
            SELECT d.id, COALESCE(d.title, 'Untitled Draft'), COALESCE(d.description, ''),
                   COALESCE(d.file_path_temp, ''), 0, 0, 0,
                   COALESCE(c.channel_name, 'Draft'), false,
                   d.last_edited_at, COALESCE(d.channel_id, '')
            FROM mp_draft_videos d
            LEFT JOIN mp_channels c ON d.channel_id = c.channel_id
            ORDER BY d.last_edited_at DESC
          ''');
        } else if (widget.folderType == 'stickers') {
          // 🚀 FIX: JOIN with mp_videos AND mp_channels so we get the REAL
          // video's id/title/file_path AND the REAL channel's name/id —
          // previously this used the sticker's own id as the video id, and
          // hardcoded 'Sticker Asset' / 'local_sticker' instead of the actual
          // creator, so the media player showed wrong title + wrong channel
          // even after the video itself started playing correctly.
          result = await connection.execute('''
            SELECT v.id::text, v.title, v.file_path, v.view_count_local,
                   v.like_count_local, v.comment_count_local, c.channel_name,
                   v.is_reel, v.upload_timestamp, c.channel_id,
                   s.product_name, s.price, s.currency
            FROM mp_sticker_products_catalog s
            JOIN mp_videos v ON s.video_id::text = v.id::text
            LEFT JOIN mp_channels c ON v.channel_id = c.channel_id
            WHERE s.is_active = TRUE
            ORDER BY s.created_at DESC
          ''');
        }

        await connection.close();

        // 5. Map the DB rows directly to your PlayerVideo models!
        if (result != null) {
          for (final row in result) {
            if (widget.folderType == 'stickers') {
              final Map<String, dynamic> stickerJsonMap = {
                'video_id': row[0].toString(), // 🚀 FIX: the REAL video id
                'title': row[1].toString(), // 🚀 FIX: the REAL video title, not the product name
                'description': 'Sticker: ${row[10]} • Price: ${row[11]} ${row[12]}', // sticker info preserved here instead
                'file_path': row[2]?.toString() ?? '', // 🚀 FIX: the REAL video's file_path
                'view_count': row[3] ?? 0,
                'like_count': row[4] ?? 0,
                'comment_count': row[5] ?? 0,
                'channel_name': row[6]?.toString() ?? 'Creator', // 🚀 FIX: the REAL channel name, not 'Sticker Asset'
                'is_reel': row[7] as bool? ?? false,
                'created_at': row[8]?.toString() ?? DateTime.now().toString(),
                'creator_uid': row[9]?.toString() ?? '', // 🚀 FIX: the REAL channel id, not 'local_sticker'
              };
              loadedVideos.add(PlayerVideo.fromJson(stickerJsonMap, safeUrl));
            } else {
              final Map<String, dynamic> jsonMap = {
                'video_id': row[0].toString(),
                'title': row[1].toString(),
                'description': row[2]?.toString() ?? '',
                'file_path': row[3].toString(),
                'view_count': row[4] ?? 0,
                'like_count': row[5] ?? 0,
                'comment_count': row[6] ?? 0,
                'channel_name': row[7]?.toString() ?? 'Creator',
                'is_reel': row[8] as bool? ?? false,
                'created_at': row[9]?.toString() ?? DateTime.now().toString(),
                'creator_uid': row[10].toString(),
              };
              loadedVideos.add(PlayerVideo.fromJson(jsonMap, safeUrl));
            }
          }
        }
      }

      if (mounted) {
        setState(() {
          _videos = loadedVideos;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("❌ Error loading folder: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Icon(widget.folderIcon, color: widget.folderColor, size: 24),
            const SizedBox(width: 12),
            Text(widget.folderTitle, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: widget.folderColor))
          : _videos.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(widget.folderIcon, color: Colors.white24, size: 64),
                      const SizedBox(height: 16),
                      Text("This folder is empty.", style: TextStyle(color: Colors.grey.shade500, fontSize: 18)),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(40.0),
                  child: GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 400, 
                      mainAxisSpacing: 48,
                      crossAxisSpacing: 24,
                      childAspectRatio: 1.15, 
                    ),
                    itemCount: _videos.length,
                    itemBuilder: (context, index) => PlayerVideoCard(
                      video: _videos[index],
                      onReturn: _loadFolderData, 
                    ),
                  ),
                ),
    );
  }
}