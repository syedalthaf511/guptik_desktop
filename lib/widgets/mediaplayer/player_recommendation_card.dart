import 'package:flutter/material.dart';
import '../../models/mediaplayer/player_video_model.dart';
import '../../screens/mediaplayer/desktop_media_player_screen.dart';
import '../../services/mediaplayer/player_api_service.dart';

class PlayerRecommendationCard extends StatefulWidget {
  final PlayerVideo video;

  const PlayerRecommendationCard({super.key, required this.video});

  @override
  State<PlayerRecommendationCard> createState() => _PlayerRecommendationCardState();
}

class _PlayerRecommendationCardState extends State<PlayerRecommendationCard> {
  late int _liveViews;
  late final PlayerApiService _apiService;

  @override
  void initState() {
    super.initState();
    // 1. Start with the Supabase count so the UI doesn't look empty
    _liveViews = widget.video.viewCount; 
    
    // 2. 🚀 SMART FIX: Check if local network target to avoid SSL handshake failures
    final safeUrl = widget.video.creatorUrl.startsWith('http') 
        ? widget.video.creatorUrl 
        : (widget.video.creatorUrl.contains('localhost') || widget.video.creatorUrl.contains('127.0.0.1') || widget.video.creatorUrl.contains(':'))
            ? 'http://${widget.video.creatorUrl}'
            : 'https://${widget.video.creatorUrl}';
        
    _apiService = PlayerApiService(gatewayUrl: safeUrl);
    
    // 3. Ping the node for the real-time stats immediately
    _fetchLiveStats(); 
  }

  // Grabs the live views straight from the Docker Node
  Future<void> _fetchLiveStats() async {
    final stats = await _apiService.fetchVideoStats(widget.video.videoId);
    if (stats != null && mounted) {
      setState(() {
        _liveViews = stats['views'] ?? _liveViews;
      });
    }
  }

  // Formats large numbers cleanly (e.g., 1.5K views)
  String _formatViews(int views) {
    if (views >= 1000000) return '${(views / 1000000).toStringAsFixed(1)}M';
    if (views >= 1000) return '${(views / 1000).toStringAsFixed(1)}K';
    return views.toString();
  }

  @override
  Widget build(BuildContext context) {
    // 🚀 SMART FIX: Re-verify layout engine URLs for Image asset rendering
    final safeUrl = widget.video.creatorUrl.startsWith('http') 
        ? widget.video.creatorUrl 
        : (widget.video.creatorUrl.contains('localhost') || widget.video.creatorUrl.contains('127.0.0.1') || widget.video.creatorUrl.contains(':'))
            ? 'http://${widget.video.creatorUrl}'
            : 'https://${widget.video.creatorUrl}';
        
    final thumbnailUrl = '$safeUrl/player/video/thumbnail/${widget.video.videoId}';

    return Material(
      color: Colors.transparent, 
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          Navigator.pushReplacement(
            context, 
            MaterialPageRoute(builder: (_) => DesktopMediaPlayerScreen(video: widget.video))
          );
        },
        child: Container(
          height: 90, 
          padding: const EdgeInsets.all(4), 
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- 1. The Thumbnail ---
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 150, 
                  height: 90,
                  child: Image.network(
                    thumbnailUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        color: Colors.grey[800],
                        child: const Center(child: Icon(Icons.broken_image, color: Colors.white54)),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(width: 12),
              
              // --- 2. The Video Details ---
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      widget.video.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.video.channelName, 
                      style: TextStyle(color: Colors.grey[400], fontSize: 12),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_formatViews(_liveViews)} views • Recommended', 
                      style: TextStyle(color: Colors.grey[500], fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}