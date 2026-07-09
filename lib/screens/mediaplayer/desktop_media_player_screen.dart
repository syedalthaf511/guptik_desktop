import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;

import '../../models/mediaplayer/player_video_model.dart';
import '../../models/mediaplayer/player_comment_model.dart';
import '../../services/mediaplayer/player_api_service.dart';
import '../../services/mediaplayer/player_comment_service.dart';
import '../../services/mediaplayer/watch_history_local_store.dart';
import '../../services/external/docker_service.dart';

import '../../widgets/mediaplayer/player_reaction_bar.dart';
import '../../widgets/mediaplayer/player_recommendation_card.dart';
import '../../widgets/mediaplayer/player_comment_widget.dart';
import '../../widgets/mediaplayer/player_controls_overlay.dart';
import '../../widgets/mediaplayer/player_ai_panel.dart';
import '../../screens/mediaplayer/creator_profile_screen.dart';


class DesktopMediaPlayerScreen extends StatefulWidget {
  final PlayerVideo video;

  const DesktopMediaPlayerScreen({super.key, required this.video});

  @override
  State<DesktopMediaPlayerScreen> createState() => _DesktopMediaPlayerScreenState();
}

class _DesktopMediaPlayerScreenState extends State<DesktopMediaPlayerScreen> {
  late final player = Player();
  late final controller = VideoController(player);
  late final PlayerApiService _apiService;
  
  late int _currentLikes;
  late int _currentComments;
  late int _currentViews;
  bool _isSaved = false;
  bool _nodeUnreachable = false;
  String _nodeError = '';

  @override
  void initState() {
    super.initState();
    
    _currentLikes = widget.video.likeCount;
    _currentComments = widget.video.commentCount;
    _currentViews = widget.video.viewCount;
    
    // 🚀 Normalize the URL: strips whitespace, and uses http:// for local
    // addresses (Docker gateway is plain HTTP) and https:// for tunnels.
    final safeUrl = DockerService.normalizeGatewayUrl(widget.video.creatorUrl);
        
    debugPrint('🚨 SECURE STREAMING URL: $safeUrl');
    
    _apiService = PlayerApiService(gatewayUrl: safeUrl);

    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser != null) {
      _apiService.addVideoView(widget.video.videoId, currentUser.id);
    }

    _syncRealTimeStats();
    final streamUrl = '$safeUrl/player/video/stream/${widget.video.videoId}';
    
    debugPrint("🎬 ATTEMPTING TO STREAM: $streamUrl"); 

    // 🚀 Pre-check: verify the creator's node is reachable before opening the player,
    // so the user sees a clear error instead of a silent black screen.
    _checkNodeReachable(safeUrl, streamUrl);
  }

  Future<void> _checkNodeReachable(String safeUrl, String streamUrl) async {
    try {
      final uri = Uri.parse('$safeUrl/player/video/stats/${widget.video.videoId}');
      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode >= 200 && response.statusCode < 400) {
        player.open(Media(streamUrl));
        player.play();
      } else {
        _showNodeError('Creator node responded with HTTP ${response.statusCode}. The video may be offline.');
      }
    } on SocketException catch (e) {
      _showNodeError('Cannot reach creator node ($safeUrl).\nDNS/network error: ${e.message}\n\nThe creator\'s Cloudflare tunnel is likely offline or the stored URL is invalid.');
    } on TimeoutException {
      _showNodeError('Creator node timed out after 8s ($safeUrl). It may be offline.');
    } catch (e) {
      _showNodeError('Unexpected error reaching creator node: $e');
    }
  }

  void _showNodeError(String message) {
    if (mounted) {
      setState(() {
        _nodeUnreachable = true;
        _nodeError = message;
      });
    }
  }

  Future<void> _syncRealTimeStats() async {
    final stats = await _apiService.fetchVideoStats(widget.video.videoId);
    final liveComments = await _apiService.fetchComments(widget.video.videoId);
    
    if (mounted) {
      setState(() {
        if (stats != null) {
          _currentLikes = stats['likes'] ?? _currentLikes;
          _currentViews = stats['views'] ?? _currentViews; 
        }
        _currentComments = liveComments.length; 
      });
    }
  }

  @override
  void dispose() {
    final durationSecs = player.state.duration.inSeconds;
    final positionSecs = player.state.position.inSeconds;
    
    double percent = durationSecs > 0 ? (positionSecs / durationSecs) * 100 : 0.0;
    
    _apiService.logWatchHistory(
      widget.video.videoId, 
      widget.video.creatorUid, 
      positionSecs, 
      percent, 
      'desktop_session_${DateTime.now().millisecondsSinceEpoch}'
    );

    // 🚀 Append-only local watch log: ensures a video watched yesterday and
    // again today appears in BOTH days (the backend de-dupes by video_id and
    // would otherwise drop it from the earlier day).
    WatchHistoryLocalStore.recordWatch(widget.video, DateTime.now());

    player.dispose();
    super.dispose();
  }

  void _handleReaction(String type) async {
    final currentUser = Supabase.instance.client.auth.currentUser;
    
    if (currentUser == null) {
      debugPrint("🛑 User is not logged in! Cannot like video.");
      return;
    }

    final realViewerId = currentUser.id; 
    final success = await _apiService.postReaction(widget.video.videoId, realViewerId, type);

    if (success) {
      setState(() => _currentLikes++);
    }
  }

  Future<void> _handleSave() async {
    final success = await _apiService.saveVideo(widget.video.videoId, widget.video.creatorUid);
    if (success && mounted) {
      setState(() => _isSaved = true); 
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Video saved to your local Vault!'), backgroundColor: Colors.green)
      );
    }
  }

  /// 🚀 ADVANCED COMMENT DIALOG — Uses PlayerCommentWidget with nested replies,
  /// reactions (like/heart/clap/laugh/disagree), edit/delete, and report.
  void _showCommentDialog() {
    final commentController = TextEditingController();
    final currentUser = Supabase.instance.client.auth.currentUser;
    final commentService = PlayerCommentService(gatewayUrl: _apiService.gatewayUrl);

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              title: Row(
                children: [
                  const Text("Comments",
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(width: 8),
                  Text('($_currentComments)',
                      style: const TextStyle(
                          color: Colors.grey, fontSize: 14)),
                ],
              ),
              content: SizedBox(
                width: 550,
                height: 500,
                child: Column(
                  children: [
                    Expanded(
                      child: FutureBuilder<List<PlayerComment>>(
                        future: commentService.fetchComments(
                          widget.video.videoId,
                          viewerUid: currentUser?.id,
                        ),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                                child: CircularProgressIndicator(
                                    color: Color(0xFF00E5FF)));
                          }
                          if (!snapshot.hasData ||
                              snapshot.data!.isEmpty) {
                            return const Center(
                                child: Text(
                                    "No comments yet. Be the first!",
                                    style:
                                        TextStyle(color: Colors.grey)));
                          }

                          final comments = snapshot.data!;
                          return ListView.builder(
                            itemCount: comments.length,
                            itemBuilder: (context, index) {
                              return PlayerCommentWidget(
                                comment: comments[index],
                                commentService: commentService,
                                videoId: widget.video.videoId,
                                videoCreatorUid:
                                    widget.video.creatorUid,
                                onCommentChanged: () {
                                  if (mounted) {
                                    setState(() {});
                                  }
                                },
                              );
                            },
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: commentController,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              hintText: "Add a comment...",
                              hintStyle:
                                  const TextStyle(color: Colors.grey),
                              filled: true,
                              fillColor: const Color(0xFF0F172A),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide.none),
                              focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(
                                      color: Color(0xFF00E5FF))),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          decoration: BoxDecoration(
                              color: const Color(0xFF00E5FF),
                              borderRadius: BorderRadius.circular(8)),
                          child: IconButton(
                            icon: const Icon(Icons.send,
                                color: Colors.black),
                            onPressed: () async {
                              if (commentController.text.isNotEmpty) {
                                final success =
                                    await commentService.postComment(
                                  widget.video.videoId,
                                  widget.video.creatorUid,
                                  commentController.text,
                                );

                                if (success) {
                                  commentController.clear();
                                  setStateDialog(() {});

                                  if (mounted) {
                                    setState(() => _currentComments++);
                                  }
                                }
                              }
                            },
                          ),
                        )
                      ],
                    )
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Close",
                      style: TextStyle(color: Colors.grey))
                ),
              ],
            );
          }
        );
      },
    );
  }

  Widget _buildActionButton(IconData icon, String label, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(20)),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  String _getTimeAgo(String? dateString) {
    if (dateString == null || dateString.isEmpty) return 'recently';
    try {
      final date = DateTime.parse(dateString);
      final now = DateTime.now();
      final difference = now.difference(date);

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
              player.seek(player.state.position + const Duration(seconds: 5));
              return KeyEventResult.handled;
            } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
              player.seek(player.state.position - const Duration(seconds: 5));
              return KeyEventResult.handled;
            } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
              player.setVolume((player.state.volume + 10.0).clamp(0.0, 100.0));
              return KeyEventResult.handled;
            } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
              player.setVolume((player.state.volume - 10.0).clamp(0.0, 100.0));
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // =================================================================
            // MAIN LEFT SECTION (70% Width)
            // =================================================================
            Expanded(
              flex: 7,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      height: 500,
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withAlpha(50), blurRadius: 20, offset: const Offset(0, 10))
                        ]
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Stack(fit: StackFit.expand, children: [
                          Video(controller: controller),
                          PlayerControlsOverlay(player: player, controller: controller),
                          if (_nodeUnreachable)
                            Container(
                              color: Colors.black.withAlpha(220),
                              padding: const EdgeInsets.all(24),
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.cloud_off, color: Color(0xFF00E5FF), size: 48),
                                    const SizedBox(height: 16),
                                    const Text(
                                      'Creator Node Unreachable',
                                      style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      _nodeError,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 24),

                    Text(
                      widget.video.title,
                      style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),

                    InkWell(
                      onTap: () {
                        player.pause();
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CreatorProfileScreen(
                              creatorUid: widget.video.creatorUid,
                              creatorNodeUrl: widget.video.creatorUrl,
                            ),
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4.0),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircleAvatar(
                              radius: 18,
                              backgroundColor: const Color(0xFF00E5FF),
                              child: Text(
                                widget.video.channelName.isNotEmpty ? widget.video.channelName[0].toUpperCase() : '?',
                                style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              widget.video.channelName,
                              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '$_currentViews views',
                              style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              '•  Published ${_getTimeAgo(widget.video.createdAt)}',
                              style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
                            ),
                          ],
                        ),

                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildActionButton(Icons.thumb_up_outlined, '$_currentLikes', onTap: () => _handleReaction('like')),
                              const SizedBox(width: 12),
                              _buildActionButton(Icons.comment, '$_currentComments', onTap: _showCommentDialog),
                              const SizedBox(width: 12),
                              _buildActionButton(
                                _isSaved ? Icons.bookmark : Icons.bookmark_border,
                                _isSaved ? 'Saved' : 'Save',
                                onTap: _isSaved ? null : _handleSave
                              ),
                              const SizedBox(width: 12),
                              _buildActionButton(Icons.share, 'Share', onTap: () {
                                final link = '${widget.video.creatorUrl}/watch/${widget.video.videoId}';
                                Clipboard.setData(ClipboardData(text: link));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Video Link Copied to Clipboard!'), backgroundColor: Colors.green)
                                );
                              }),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    PlayerReactionBar(onReactionSelected: _handleReaction),
                    const SizedBox(height: 24),

                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: const Color(0xFF1E293B).withAlpha(150), borderRadius: BorderRadius.circular(12)),
                      child: Text(widget.video.description, style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.5)),
                    ),
                    const SizedBox(height: 16),
                    PlayerAIPanel(video: widget.video),
                  ],
                ),
              ),
            ),

            // =================================================================
            // 🚀 ASYMMETRIC CURVED SIDEBAR (Right Section)
            // =================================================================
           Expanded(
              flex: 3,
              child: Container(
                margin: const EdgeInsets.only(left: 24), 
                decoration: BoxDecoration(
                  color: const Color(0xFF162032), 
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(48),
                    bottomLeft: Radius.circular(48),
                  ),
                  border: Border.all(color: Colors.white.withAlpha(20), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(90),
                      blurRadius: 30,
                      offset: const Offset(-8, 0),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(48),
                    bottomLeft: Radius.circular(48),
                  ),
                  child: Column(
                    children: [
                      // Sidebar Header
                      Container(
                        padding: const EdgeInsets.fromLTRB(32, 24, 24, 24), 
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B).withAlpha(200),
                          border: const Border(bottom: BorderSide(color: Colors.white10)),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.video_library_rounded, color: Color(0xFF00E5FF), size: 22),
                            SizedBox(width: 12),
                            Text('Network Hub', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                      
                      // 🚀 THE FIX: ListWheelScrollView for the 3D curved scroll effect!
                      Expanded(
                        child: FutureBuilder<List<PlayerVideo>>(
                          future: _apiService.fetchNetworkFeed(), 
                          builder: (context, snapshot) {
                            if (snapshot.connectionState == ConnectionState.waiting) {
                              return const Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF)));
                            }
                            
                            if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
                              return const Center(
                                child: Text("No other videos found.", style: TextStyle(color: Colors.white54))
                              );
                            }
                            
                            final suggestedVideos = snapshot.data!;
                            
                            // Replaced standard ListView with the 3D Wheel Scroll
                            return ListWheelScrollView.useDelegate(
                              itemExtent: 130, // The fixed height of your recommendation cards
                              diameterRatio: 2.5, // Adjusts the depth of the arc 
                              offAxisFraction: -0.15, // Tilts the scroll curve slightly inward to hug the sidebar
                              physics: const BouncingScrollPhysics(),
                              childDelegate: ListWheelChildBuilderDelegate(
                                childCount: suggestedVideos.length,
                                builder: (context, index) {
                                  final suggestion = suggestedVideos[index];
                                  if (suggestion.videoId == widget.video.videoId) return const SizedBox.shrink(); 
                                  
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                                    child: PlayerRecommendationCard(video: suggestion),
                                  );
                                },
                              ),
                            );
                          }
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
    ),
    );
  }
}
