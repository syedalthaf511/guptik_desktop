import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:math' as math;

import '../../models/mediaplayer/player_video_model.dart';
import '../../models/mediaplayer/player_comment_model.dart';
import '../../services/mediaplayer/player_api_service.dart';
import '../../services/mediaplayer/player_organization_service.dart';
import '../../services/mediaplayer/player_comment_service.dart';
import '../../services/mediaplayer/watch_history_local_store.dart';
import '../../services/external/docker_service.dart';

import '../../widgets/mediaplayer/player_reaction_bar.dart';
import '../../widgets/mediaplayer/player_recommendation_card.dart';
import '../../widgets/mediaplayer/player_comment_widget.dart';
import '../../widgets/mediaplayer/player_controls_overlay.dart';
import '../../widgets/mediaplayer/player_ai_panel.dart';
import '../../widgets/mediaplayer/sticker_overlay.dart';
import '../../screens/mediaplayer/creator_profile_screen.dart';
import '../../services/mediaplayer/player_watcher_interest_service.dart';
import '../../services/mediaplayer/player_report_service.dart';


class DesktopMediaPlayerScreen extends StatefulWidget {
  final PlayerVideo video;

  const DesktopMediaPlayerScreen({super.key, required this.video});

  @override
  State<DesktopMediaPlayerScreen> createState() => _DesktopMediaPlayerScreenState();
}

class _DesktopMediaPlayerScreenState extends State<DesktopMediaPlayerScreen> with SingleTickerProviderStateMixin {
  late final player = Player();
  late final controller = VideoController(player);
  late final PlayerApiService _apiService;
  late final AnimationController _shakeController;
  late final Animation<double> _shakeAnimation;
  // 🚀 Normalized creator gateway URL — used to fetch stickers (and stream)
  // from the CREATOR's node so any viewer sees the creator's shoppable stickers.
  late final String safeUrl;

  late int _currentLikes;
  late int _currentComments;
  late int _currentViews;
  bool _isSaved = false;
  bool _isReposted = false;
  int _repostCount = 0;
  bool _nodeUnreachable = false;
  String _nodeError = '';
  bool _ageConfirmed = false;
  // 🚀 AGE GATE: tracks whether an 18+ video has been confirmed by the viewer.
   // Removed unused field _ageConfirmed

  // 🚀 WATCHER INTEREST: 'interested' / 'not_interested' / null (no choice yet).
  String? _watcherInterest;
  final PlayerWatcherInterestService _interestService =
      PlayerWatcherInterestService();
  final PlayerReportService _reportService = PlayerReportService();

  @override
  void initState() {
    super.initState();
    
    // 🚀 SHAKE ANIMATION SETUP
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _shakeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.elasticOut),
    );
    
    _currentLikes = widget.video.likeCount;
    _currentComments = widget.video.commentCount;
    _currentViews = widget.video.viewCount;
    _repostCount = widget.video.repostCount;
    
    // 🚀 Normalize the URL: strips whitespace, and uses http:// for local
    // addresses (Docker gateway is plain HTTP) and https:// for tunnels.
    safeUrl = DockerService.normalizeGatewayUrl(widget.video.creatorUrl);
        
    debugPrint('🚨 SECURE STREAMING URL: $safeUrl');
    
    _apiService = PlayerApiService(gatewayUrl: safeUrl);

    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser != null) {
      _apiService.addVideoView(widget.video.videoId, currentUser.id);
      _loadWatcherInterest(currentUser.id);
    }

    _syncRealTimeStats();
    final streamUrl = '$safeUrl/player/video/stream/${widget.video.videoId}';
    
    debugPrint("🎬 ATTEMPTING TO STREAM: $streamUrl"); 

    // 🚀 AGE GATE (YouTube-style): for age-restricted (18+) content ONLY, do NOT
    // auto-play. Show a confirmation dialog first; only open the player after
    // the viewer confirms they are 18 or older. A "Made for Kids" video must
    // NEVER trigger this gate — kids' content plays normally (it is a
    // classification, not a restriction). The `!madeForKids` guard guarantees
    // a kids video can never be gated even if the stored age_rating is wrong.
    if (widget.video.ageRating == '18+' && !widget.video.madeForKids) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showAgeGate(safeUrl, streamUrl);
      });
    } else {
      // 🚀 Pre-check: verify the creator's node is reachable before opening the player,
      // so the user sees a clear error instead of a silent black screen.
      _checkNodeReachable(safeUrl, streamUrl);
    }
  }

  // 🚀 AGE GATE DIALOG: mirrors YouTube's mature-content confirmation.
  void _showAgeGate(String safeUrl, String streamUrl) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 28),
            SizedBox(width: 10),
            Text('Age-restricted content', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text(
          'This video may be inappropriate for some users. Confirm that you are at least 18 years old to continue.',
          style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              if (mounted) {
                setState(() {
                  _nodeUnreachable = true;
                  _nodeError = 'Playback blocked: age restriction not confirmed.';
                });
              }
            },
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E5FF)),
            onPressed: () {
              Navigator.pop(context);
              if (mounted) {
                 setState(() => _ageConfirmed = true);
   // Removed all references to _ageConfirmed
                _checkNodeReachable(safeUrl, streamUrl);
              }
            },
            child: const Text('I am 18 or older', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // 🚀 AUDIENCE BADGES: YouTube-style "Made for Kids" + "18+" indicators.
  List<Widget> _buildAudienceBadges() {
    final badges = <Widget>[];
    if (widget.video.madeForKids) {
      badges.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0xFF00E5FF).withAlpha(25),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0xFF00E5FF).withAlpha(120)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.child_care, size: 13, color: Color(0xFF00E5FF)),
              SizedBox(width: 4),
              Text('Made for Kids', style: TextStyle(color: Color(0xFF00E5FF), fontSize: 11, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      );
    }
    if (widget.video.ageRating == '18+') {
      badges.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.redAccent.withAlpha(25),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.redAccent.withAlpha(140)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.warning_amber_rounded, size: 13, color: Colors.redAccent),
              SizedBox(width: 4),
              Text('18+', style: TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      );
    }
    return badges;
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
        _repostCount = stats['reposts'] ?? _repostCount;
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

  /// 🚀 REPOST: Re-shares the current video to the viewer's own channel/profile
  /// while preserving original creator attribution. Calls the Docker gateway
  /// `/player/video/repost` endpoint via PlayerApiService (consistent with
  /// like/comment/save/view engagement actions).
  Future<void> _handleRepost() async {
    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to repost.'), backgroundColor: Colors.redAccent),
      );
      return;
    }

    // Don't let a creator repost their own video as a "repost".
    if (currentUser.id == widget.video.creatorUid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This is your own video.'), backgroundColor: Colors.orange),
      );
      return;
    }

    if (_isReposted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You already reposted this video.'), backgroundColor: Colors.orange),
      );
      return;
    }

    final success = await _apiService.repostVideo(
      originalVideoId: widget.video.videoId,
      originalCreatorUid: widget.video.creatorUid,
      originalCreatorName: widget.video.channelName,
      originalChannelName: widget.video.channelName,
      reposterUid: currentUser.id,
      reposterChannelName: widget.video.channelName,
    );

      if (success && mounted) {
        // 🚀 FEED ATTRIBUTION: Insert a NEW row in the admin Supabase
        // mp_videos table attributed to the REPOSTER (User A), with
        // repost_id pointing to the original video's row id. This is what
        // makes the repost show up in the global feed as User A's video,
        // with the original creator (User B) surfaced via the nested
        // `original:mp_videos!repost_id(*)` expansion. The stream/thumbnail
        // URLs still point to the original creator's node so the file plays.
        try {
          final supabase = Supabase.instance.client;
          // Look up the original video's UUID row id from its text video_id.
          final orig = await supabase
              .from('mp_videos')
              .select('id')
              .eq('video_id', widget.video.videoId)
              .maybeSingle();
          final origRowId = orig?['id']?.toString();
          if (origRowId != null) {
            final repostVideoId = math.Random(DateTime.now().millisecondsSinceEpoch).toString();
            await supabase.from('mp_videos').insert({
              'video_id': repostVideoId,
              'creator_uid': currentUser.id,
              'channel_name': widget.video.channelName,
              'title': widget.video.title,
              'description': widget.video.description,
              'creator_cloudflare_url': widget.video.originalCreatorUrl ?? widget.video.creatorUrl,
              'thumbnail_url': widget.video.thumbnailUrl ?? '',
              'category': widget.video.category,
              'visibility': 'public',
              'is_reel': widget.video.isReel,
              'is_monetized': false,
              'made_for_kids': widget.video.madeForKids,
              'age_rating': widget.video.ageRating,
              'repost_id': origRowId,
            });
          }
        } catch (e) {
          debugPrint('Repost feed insert (non-fatal): $e');
        }

        // 🚀 Also record the repost on the user's LOCAL node so it appears in
        // the "Repost Videos" folder. The gateway call above only writes to the
        // original video's node (to increment its repost_count_local), so the
        // reposter's own folder would otherwise stay empty.
        // 🚀 Also record the repost on the user's LOCAL node so it appears in
        // the "Repost Videos" folder. The gateway call above only writes to the
        // original video's node (to increment its repost_count_local), so the
        // reposter's own folder would otherwise stay empty.
        await PlayerOrganizationService().saveLocalRepost(
          originalVideoId: widget.video.videoId,
          originalCreatorUid: widget.video.creatorUid,
          originalCreatorName: widget.video.channelName,
          originalChannelName: widget.video.channelName,
          reposterUid: currentUser.id,
          reposterChannelName: widget.video.channelName,
        );
        setState(() {
          _isReposted = true;
          _repostCount++;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Video reposted to your profile!'), backgroundColor: Colors.green),
        );
      } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to repost video.'), backgroundColor: Colors.redAccent),
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

  // 🚀 WATCHER INTEREST: load the watcher's saved interest for this video so
  // the UI can show the correct "Interested" / "Not interested" chip state.
  Future<void> _loadWatcherInterest(String watcherUid) async {
    final interest = await _interestService.getInterest(
      videoId: widget.video.videoId,
      watcherUid: watcherUid,
    );
    if (mounted) setState(() => _watcherInterest = interest);
  }

  // 🚀 WATCHER INTEREST: set interested / not_interested / clear for this video.
  Future<void> _setWatcherInterest(String? interest) async {
    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser == null) return;

    if (interest == null) {
      // Clear feedback
      await _interestService.setInterest(
        videoId: widget.video.videoId,
        creatorUid: widget.video.creatorUid,
        watcherUid: currentUser.id,
        interest: '',
      );
    } else {
      await _interestService.setInterest(
        videoId: widget.video.videoId,
        creatorUid: widget.video.creatorUid,
        watcherUid: currentUser.id,
        interest: interest,
      );
    }
    if (mounted) setState(() => _watcherInterest = interest);
  }

  // 🚀 REPORT: opens a dialog to file a report for the current video.
  void _showReportDialog() {
    final descController = TextEditingController();
    String selectedType = 'spam';
    final reportTypes = [
      'spam',
      'nudity',
      'harassment',
      'misinformation',
      'copyright',
      'other',
    ];

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.flag, color: Colors.redAccent, size: 24),
                  SizedBox(width: 10),
                  Text('Report Video', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ],
              ),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Why are you reporting this video?',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: selectedType,
                      dropdownColor: const Color(0xFF0F172A),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFF0F172A),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      ),
                      style: const TextStyle(color: Colors.white),
                      items: reportTypes
                          .map((t) => DropdownMenuItem(value: t, child: Text(t[0].toUpperCase() + t.substring(1))))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) {
                          selectedType = v;
                          setStateDialog(() {});
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descController,
                      maxLines: 3,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Add details (optional)...',
                        hintStyle: const TextStyle(color: Colors.grey),
                        filled: true,
                        fillColor: const Color(0xFF0F172A),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
                  onPressed: () async {
                    final currentUser = Supabase.instance.client.auth.currentUser;
                    if (currentUser == null) {
                      Navigator.pop(context);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Please log in to report.'), backgroundColor: Colors.redAccent),
                        );
                      }
                      return;
                    }
                    final ok = await _reportService.fileReport(
                      byUser: currentUser.id,
                      videoId: widget.video.videoId,
                      type: selectedType,
                      description: descController.text.trim().isEmpty ? null : descController.text.trim(),
                    );
                    if (!context.mounted) return;
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(ok ? 'Report submitted. Thank you.' : 'Failed to submit report.'),
                        backgroundColor: ok ? Colors.green : Colors.redAccent,
                      ),
                    );
                  },
                  child: const Text('Submit'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // 🚀 SHAKE ANIMATION TRIGGER: Called when user touches top or bottom of video
  void _triggerShake() {
    _shakeController.forward(from: 0).then((_) {
      _shakeController.reset();
    });
  }

  // 🚀 SHAKE TRANSFORMATION: Creates a shaking effect for the border
  double _getShakeOffset(double value) {
    final shakeAmount = math.sin(value * 2 * math.pi * 8) * 8;
    return shakeAmount;
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
                    AnimatedBuilder(
                      animation: _shakeAnimation,
                      builder: (context, child) {
                        return Transform.translate(
                          offset: Offset(_getShakeOffset(_shakeAnimation.value), 0),
                          child: Container(
                            width: double.infinity,
                            height: 500,
                            decoration: BoxDecoration(
                              color: Colors.black,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: const Color(0xFF00E5FF).withAlpha(120),
                                width: 2,
                              ),
                              boxShadow: [
                                BoxShadow(color: Colors.black.withAlpha(50), blurRadius: 20, offset: const Offset(0, 10))
                              ]
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Stack(fit: StackFit.expand, children: [
                                Video(controller: controller),
                                PlayerControlsOverlay(player: player, controller: controller),
                                StickerOverlay(
                                  player: player,
                                  videoId: widget.video.videoId,
                                  creatorUrl: safeUrl,
                                ),
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
                        );
                      },
                    ),
                    // 🚀 TOP/BOTTOM TOUCH DETECTORS for shake effect
                    GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: _triggerShake,
                      child: Container(
                        width: double.infinity,
                        height: 60,
                        color: Colors.transparent,
                        alignment: Alignment.topCenter,
                      ),
                    ),
                    GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: _triggerShake,
                      child: Container(
                        width: double.infinity,
                        height: 30,
                        color: Colors.transparent,
                        alignment: Alignment.bottomCenter,
                      ),
                    ),
                    const SizedBox(height: 24),

                    Text(
                      widget.video.title,
                      style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),

                    // 🚀 REPOST ATTRIBUTION: when this video is a repost, show the
                    // reposter (this row's creator) as the actual creator, and
                    // surface the original creator as "reposted from".
                    if (widget.video.isRepost) ...[
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00E5FF).withAlpha(20),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF00E5FF).withAlpha(120)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.repeat, size: 14, color: Color(0xFF00E5FF)),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'Reposted from ${widget.video.originalChannelName?.isNotEmpty == true ? widget.video.originalChannelName : "original creator"}',
                                style: const TextStyle(color: Color(0xFF00E5FF), fontSize: 12, fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

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

                    // 🚀 AUDIENCE BADGES (Made for Kids / 18+) shown in the player header.
                    if (widget.video.madeForKids || widget.video.ageRating == '18+')
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _buildAudienceBadges(),
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
                              _buildActionButton(
                                _isReposted ? Icons.repeat : Icons.repeat_outlined,
                                _repostCount > 0
                                    ? '$_repostCount'
                                    : (_isReposted ? 'Reposted' : 'Repost'),
                                onTap: _isReposted ? null : _handleRepost,
                              ),
                              const SizedBox(width: 12),
                              _buildActionButton(Icons.share, 'Share', onTap: () {
                                final link = '${widget.video.creatorUrl}/watch/${widget.video.videoId}';
                                Clipboard.setData(ClipboardData(text: link));
                                // 🚀 Record the share so mp_shared_videos is populated
                                // and share_count_local increments on the node.
                                _apiService.shareVideo(
                                  videoId: widget.video.videoId,
                                  creatorUid: widget.video.creatorUid,
                                  shareMethod: 'link',
                                );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Video Link Copied to Clipboard!'), backgroundColor: Colors.green)
                                );
                              }),
                              const SizedBox(width: 12),
                              _buildActionButton(Icons.flag_outlined, 'Report', onTap: _showReportDialog),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // 🚀 WATCHER INTEREST: Interested / Not interested / Clear chips.
                    // Lets a watcher tell the recommendation engine whether this
                    // video is relevant, persisted to the local mp_watcher_interest
                    // table.
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('Interested', style: TextStyle(fontSize: 12)),
                          selected: _watcherInterest == 'interested',
                          selectedColor: const Color(0xFF00E5FF),
                          backgroundColor: const Color(0xFF1E293B),
                          labelStyle: TextStyle(
                            color: _watcherInterest == 'interested' ? Colors.black : Colors.white,
                          ),
                          onSelected: (_) => _setWatcherInterest('interested'),
                        ),
                        ChoiceChip(
                          label: const Text('Not interested', style: TextStyle(fontSize: 12)),
                          selected: _watcherInterest == 'not_interested',
                          selectedColor: Colors.redAccent,
                          backgroundColor: const Color(0xFF1E293B),
                          labelStyle: TextStyle(
                            color: _watcherInterest == 'not_interested' ? Colors.white : Colors.white,
                          ),
                          onSelected: (_) => _setWatcherInterest('not_interested'),
                        ),
                        if (_watcherInterest != null)
                          ChoiceChip(
                            label: const Text('Clear', style: TextStyle(fontSize: 12)),
                            selected: false,
                            backgroundColor: const Color(0xFF1E293B),
                            labelStyle: const TextStyle(color: Colors.grey),
                            onSelected: (_) => _setWatcherInterest(null),
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
                  border: Border.all(color:Color(0xFF00E5FF).withAlpha(120), width: 1.5),
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
