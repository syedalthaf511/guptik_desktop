import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:postgres/postgres.dart';
import '../../models/mediaplayer/player_video_model.dart';
import '../../widgets/mediaplayer/player_video_card.dart';
import '../../services/external/postgres_service.dart';

class DesktopSystemFolderScreen extends StatefulWidget {
  final String folderType; // 'posted', 'saved', or 'drafts'
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
      
      // 2. 🚀 SMART FIX: Parse fallback layout constraints directly on raw system properties
      final safeUrl = _publicUrl!.startsWith('http') 
          ? _publicUrl! 
          : (_publicUrl!.contains('localhost') || _publicUrl!.contains('127.0.0.1') || _publicUrl!.contains(':'))
              ? 'http://$_publicUrl'
              : 'https://$_publicUrl';

      // 3. Connect directly to the local Postgres Node!
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
      }

      await connection.close();

      // 5. Map the DB rows directly to your PlayerVideo models!
      final List<PlayerVideo> loadedVideos = [];
      
      if (result != null) {
        for (final row in result) {
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