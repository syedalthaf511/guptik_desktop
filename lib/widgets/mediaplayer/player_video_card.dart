import 'package:flutter/material.dart';
import '../../models/mediaplayer/player_video_model.dart';
import '../../screens/mediaplayer/desktop_media_player_screen.dart';
import '../../services/mediaplayer/player_api_service.dart';

class PlayerVideoCard extends StatefulWidget {
  final PlayerVideo video;
  final VoidCallback? onReturn;

  const PlayerVideoCard({super.key, required this.video, this.onReturn});

  @override
  State<PlayerVideoCard> createState() => _PlayerVideoCardState();
}

class _PlayerVideoCardState extends State<PlayerVideoCard> {
  late int _liveViews;
  late final PlayerApiService _apiService;

  @override
  void initState() {
    super.initState();
    _liveViews = widget.video.viewCount; 
    
    // 🚀 SMART FIX: Handle protocol detection to bypass localhost SSL blocks
    final safeUrl = widget.video.creatorUrl.startsWith('http') 
        ? widget.video.creatorUrl 
        : (widget.video.creatorUrl.contains('localhost') || widget.video.creatorUrl.contains('127.0.0.1') || widget.video.creatorUrl.contains(':'))
            ? 'http://${widget.video.creatorUrl}'
            : 'https://${widget.video.creatorUrl}';
        
    _apiService = PlayerApiService(gatewayUrl: safeUrl);
    _fetchLiveStats(); 
  }

  Future<void> _fetchLiveStats() async {
    final stats = await _apiService.fetchVideoStats(widget.video.videoId);
    if (stats != null && mounted) {
      setState(() {
        _liveViews = stats['views'] ?? _liveViews;
      });
    }
  }

  String _formatViews(int views) {
    if (views >= 1000000) return '${(views / 1000000).toStringAsFixed(1)}M';
    if (views >= 1000) return '${(views / 1000).toStringAsFixed(1)}K';
    return views.toString();
  }

  String _getTimeAgo(String? dateString) {
    if (dateString == null || dateString.isEmpty) return 'recently'; 
    try {
      final date = DateTime.parse(dateString);
      final difference = DateTime.now().difference(date);
      if (difference.inDays > 365) return '${(difference.inDays / 365).floor()} years ago';
      if (difference.inDays > 30) return '${(difference.inDays / 30).floor()} months ago';
      if (difference.inDays > 0) return '${difference.inDays} days ago';
      if (difference.inHours > 0) return '${difference.inHours} hours ago';
      if (difference.inMinutes > 0) return '${difference.inMinutes} minutes ago';
      return 'just now';
    } catch (e) {
      return 'recently';
    }
  }

  // 🚀 MONETIZATION + AUDIENCE BADGES: YouTube-style indicators.
  List<Widget> _buildAudienceBadges() {
    final badges = <Widget>[];
    if (widget.video.isMonetized) {
      badges.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.green.withAlpha(25),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.green.withAlpha(120)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.attach_money, size: 11, color: Colors.green),
              SizedBox(width: 3),
              Text('Monetized', style: TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      );
    }
    if (widget.video.madeForKids) {
      badges.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFF00E5FF).withAlpha(25),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0xFF00E5FF).withAlpha(120)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.child_care, size: 11, color: Color(0xFF00E5FF)),
              SizedBox(width: 3),
              Text('Made for Kids', style: TextStyle(color: Color(0xFF00E5FF), fontSize: 10, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      );
    }
    if (widget.video.ageRating == '18+') {
      badges.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.redAccent.withAlpha(25),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.redAccent.withAlpha(140)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.warning_amber_rounded, size: 11, color: Colors.redAccent),
              SizedBox(width: 3),
              Text('18+', style: TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      );
    }
    return badges;
  }

  @override
  Widget build(BuildContext context) {
    final isReel = widget.video.isReel;

    final safeUrl = widget.video.creatorUrl.startsWith('http') 
        ? widget.video.creatorUrl 
        : (widget.video.creatorUrl.contains('localhost') || widget.video.creatorUrl.contains('127.0.0.1') || widget.video.creatorUrl.contains(':'))
            ? 'http://${widget.video.creatorUrl}'
            : 'https://${widget.video.creatorUrl}';
        
    final thumbnailUrl = '$safeUrl/player/video/thumbnail/${widget.video.videoId}';

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () async {
          await Navigator.push(
            context, 
            MaterialPageRoute(builder: (_) => DesktopMediaPlayerScreen(video: widget.video))
          );
          await _fetchLiveStats();
          if (widget.onReturn != null) widget.onReturn!();
        },
        child: Container(
          width: isReel ? 200 : null, 
          color: Colors.transparent, 
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch, 
            children: [
              // ==========================================
              // 1. PERFECT THUMBNAIL (FLEXIBLE HEIGHT FIX)
              // ==========================================
              Expanded(
                flex: 3,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: AspectRatio(
                    aspectRatio: isReel ? 9 / 16 : 16 / 9, 
                    child: Container(
                      color: Colors.black, 
                      child: Image.network(
                        thumbnailUrl,
                        fit: BoxFit.cover, 
                        errorBuilder: (context, error, stackTrace) => const Center(
                          child: Icon(Icons.play_circle_fill, color: Colors.white24, size: 50),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              
              // ==========================================
              // 2. AVATAR & METADATA
              // ==========================================
              Expanded(
                flex: 2,
                child: SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  child: Builder( // 🚀 Using a Builder to cleanly define our UI logic
                    builder: (context) {
                      // 🚀 If it's a repost, make User B the main display name. Otherwise, normal.
                      final String displayChannelName = widget.video.isRepost && (widget.video.originalChannelName?.isNotEmpty ?? false)
                          ? widget.video.originalChannelName!
                          : widget.video.channelName;

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: const Color(0xFF00E5FF),
                            child: Text(
                              displayChannelName.isNotEmpty ? displayChannelName[0].toUpperCase() : '?',
                              style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ),
                          const SizedBox(width: 8),
                          
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  widget.video.title, 
                                  maxLines: 2, 
                                  overflow: TextOverflow.ellipsis, 
                                  style: const TextStyle(
                                    color: Colors.white, 
                                    fontWeight: FontWeight.w600, 
                                    fontSize: 14,
                                    height: 1.2
                                  ),
                                ),
                                const SizedBox(height: 4),
                                
                                // 🚀 MAIN CHANNEL NAME (Displays User B)
                                Text(
                                  displayChannelName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                                ),
                                
                                // 🚀 ATTRIBUTION TEXT (Displays User A)
                                if (widget.video.isRepost &&
                                    (widget.video.originalChannelName?.isNotEmpty ?? false)) ...[
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      Icon(Icons.repeat, size: 11, color: const Color(0xFF00E5FF).withAlpha(180)),
                                      const SizedBox(width: 3),
                                      Flexible(
                                        child: Text(
                                          'Reposted by @${widget.video.channelName}', // 🚀 User A
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: const Color(0xFF00E5FF).withAlpha(200),
                                            fontSize: 11,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                                const SizedBox(height: 2),
                                Text(
                                  '${_formatViews(_liveViews)} views • ${_getTimeAgo(widget.video.createdAt)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: Colors.grey.shade400, fontSize: 11),
                                ),
                                
                                // 🚀 Engagement metrics row
                                if (widget.video.totalReactions > 0 ||
                                    widget.video.saveCount > 0 ||
                                    widget.video.repostCount > 0) ...[
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      if (widget.video.totalReactions > 0) ...[
                                        Icon(Icons.favorite, size: 11, color: Colors.pinkAccent.withAlpha(180)),
                                        const SizedBox(width: 2),
                                        Text(_formatViews(widget.video.totalReactions),
                                            style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
                                        const SizedBox(width: 8),
                                      ],
                                      if (widget.video.saveCount > 0) ...[
                                        Icon(Icons.bookmark, size: 11, color: Colors.grey.shade500),
                                        const SizedBox(width: 2),
                                        Text(_formatViews(widget.video.saveCount),
                                            style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
                                        const SizedBox(width: 8),
                                      ],
                                      if (widget.video.repostCount > 0) ...[
                                        Icon(Icons.repeat, size: 11, color: Colors.grey.shade500),
                                        const SizedBox(width: 2),
                                        Text(_formatViews(widget.video.repostCount),
                                            style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
                                      ],
                                    ],
                                  ),
                                ],
                                
                                // 🚀 AUDIENCE BADGES (Made for Kids / 18+)
                                if (widget.video.madeForKids || widget.video.ageRating == '18+') ...[
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    children: _buildAudienceBadges(),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Icon(Icons.more_vert, color: Colors.grey.shade400, size: 20),
                          ),
                        ],
                      ); // 🚀 THE FIX: Properly closed the Row with a semicolon!
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}