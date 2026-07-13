import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart'; 
import 'package:http/http.dart' as http; // 🚀 Added for local history fetching
import '../../models/mediaplayer/player_video_model.dart';
import '../../services/mediaplayer/player_api_service.dart';
import '../../services/mediaplayer/watch_history_local_store.dart';
import '../../services/external/docker_service.dart';
import '../../widgets/mediaplayer/player_video_card.dart';
import 'desktop_upload__screen.dart';
import 'creator_profile_screen.dart';
import 'playlist_management_screen.dart';
import 'notifications_screen.dart';
import 'monetization_dashboard_screen.dart';
import 'desktop_system_folder_screen.dart';

class DesktopMediaHomeScreen extends StatefulWidget {
  final String gatewayUrl; 

  const DesktopMediaHomeScreen({super.key, required this.gatewayUrl});

  @override
  State<DesktopMediaHomeScreen> createState() => _DesktopMediaHomeScreenState();
}

class _DesktopMediaHomeScreenState extends State<DesktopMediaHomeScreen> {
  List<PlayerVideo> _normalVideos = [];
  List<PlayerVideo> _reels = [];
  List<PlayerVideo> _historyVideos = []; 
  bool _isLoading = true;
  late final PlayerApiService _apiService;

  // 🚀 HISTORY DATE FILTER: when set, only videos watched on this date are shown.
  DateTime? _historyDateFilter;

  int _selectedIndex = 0; 
  bool _isSidebarExpanded = false; 

  // 🚀 SEARCH AND FILTER STATE
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";
  String _selectedFilter = "All";
  // 🚀 YouTube-style chips: aligned with the actual categories used when
  // uploading (see DesktopUploadScreen._categories) so every chip matches real
  // videos. "All" shows everything; the rest filter by category (case-insensitive)
  // and also by matching tags.
  final List<String> _filters = ['All', 'Entertainment', 'Tech', 'Education', 'Gaming', 'Music', 'Vlog', 'News'];

  @override
  void initState() {
    super.initState();
    _apiService = PlayerApiService(gatewayUrl: widget.gatewayUrl);
    _loadFeed();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadFeed() async {
    final allVideos = await _apiService.fetchNetworkFeed();
    if (mounted) {
      setState(() {
        _reels = allVideos.where((v) => v.isReel).toList();
        _normalVideos = allVideos.where((v) => !v.isReel).toList();
        _isLoading = false;
      });
    }
  }

  // 🚀 FETCH HISTORY FROM DOCKER GATEWAY
  // Tries the live Cloudflare tunnel URL first (proven reachable), then falls
  // back to the local gateway (localhost:55000). This makes watch history work
  // even when the local gateway port isn't published to the host.
  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    try {
      final candidates = <String>[];

      // 1. Live tunnel URL from secure storage (the one the gateway actually serves via cloudflared)
      try {
        final tunnelUrl = await DockerService().getActiveTunnelUrl();
        if (tunnelUrl.isNotEmpty && !tunnelUrl.startsWith('your-tunnel-url')) {
          candidates.add(DockerService.normalizeGatewayUrl(tunnelUrl));
        }
      } catch (_) {}

      // 2. Local gateway fallback
      candidates.add(DockerService.normalizeGatewayUrl(widget.gatewayUrl));

      List<dynamic>? data;
      String? usedUrl;
      for (final url in candidates) {
        try {
          final response = await http
              .get(Uri.parse('$url/player/video/history/list'))
              .timeout(const Duration(seconds: 8));
          if (response.statusCode == 200) {
            data = jsonDecode(response.body) as List<dynamic>;
            usedUrl = url;
            break;
          }
        } catch (_) {
          // try next candidate
        }
      }

      // 🚀 MERGE: The backend de-duplicates history by video_id (keeping only
      // the latest watch_timestamp), so a video watched yesterday and again
      // today would "move" out of Yesterday. We merge in our own append-only
      // local log so each watch event is preserved on its own day. The local
      // log is the source of truth for *when* something was watched; the
      // backend is used to enrich metadata / cover sessions before this feature
      // existed.
      final localEntries = await WatchHistoryLocalStore.getAll();

      if (mounted) {
        setState(() {
          _historyVideos = [];
          _watchTimes.clear();

          // Track (videoId|dayKey) pairs already represented so we never show
          // the same video twice on the same day. The local log is the source
          // of truth for *when* a video was watched.
          final seen = <String>{};

          // 1. Local append-only log first. Each entry keeps its own per-event
          // timestamp, so a re-watched video correctly appears on every day it
          // was watched (e.g. Yesterday AND Today).
          for (final entry in localEntries) {
            final vid = entry.video.videoId;
            if (vid.isEmpty) continue;
            final ts = entry.watchedAt;
            final dayKey = '${ts.year}-${ts.month}-${ts.day}';
            final key = '$vid|$dayKey';
            if (seen.contains(key)) continue;
            seen.add(key);
            _historyVideos.add(entry.video);
            _watchTimes.add(ts);
          }

          // 2. Backend entries (if reachable). The backend de-duplicates by
          // video_id and only keeps the LATEST watch_timestamp, so a video
          // watched yesterday and again today would otherwise "move" out of
          // Yesterday. We still merge these in to cover sessions before this
          // local log existed, but skip any (videoId, day) already represented
          // by the local log to avoid duplicates.
          if (data != null) {
            for (final json in data) {
              final vid = (json['video_id'] ?? json['id'] ?? '').toString();
              final rawTs = json['watch_timestamp']?.toString();
              final ts = DateTime.tryParse(rawTs ?? '') ?? DateTime.now();
              final dayKey = '${ts.year}-${ts.month}-${ts.day}';
              final key = '$vid|$dayKey';
              if (vid.isEmpty || seen.contains(key)) continue;
              seen.add(key);
              _historyVideos.add(PlayerVideo.fromJson(json, usedUrl!));
              _watchTimes.add(ts);
            }
          }

          // Clear any stale date filter when reloading.
          _historyDateFilter = null;
          _isLoading = false;
        });
      } else {
        debugPrint("Failed to fetch history from all candidates: $candidates");
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint("Error fetching history: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // 🚀 LOCAL FILTERING LOGIC
  List<PlayerVideo> get _filteredVideos {
    return _normalVideos.where((video) {
      final matchesSearch = video.title.toLowerCase().contains(_searchQuery.toLowerCase());
      
      // 🚀 UPDATED: Now uses the category field from the extended PlayerVideo model
      final matchesFilter = _selectedFilter == 'All' ||
          video.category.toLowerCase() == _selectedFilter.toLowerCase() ||
          video.tags.any((t) => t.toLowerCase() == _selectedFilter.toLowerCase());
      
      return matchesSearch && matchesFilter;
    }).toList();
  }

  // 🚀 HISTORY DATE HELPERS
  // Returns a human-friendly label for a watch timestamp:
  // Today, Yesterday, weekday name (Mon, Tue...), or a full date for older entries.
  String _historyDateLabel(DateTime ts) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final watchDay = DateTime(ts.year, ts.month, ts.day);
    final diffDays = today.difference(watchDay).inDays;

    if (diffDays == 0) return 'Today';
    if (diffDays == 1) return 'Yesterday';
    if (diffDays > 1 && diffDays < 7) {
      // Weekday name for entries within the last week
      const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return weekdays[watchDay.weekday - 1];
    }
    // Older than a week: show full date
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${watchDay.day} ${months[watchDay.month - 1]} ${watchDay.year}';
  }

  // 🚀 Parallel list of watch timestamps, aligned 1:1 with [_historyVideos].
  // A single video can legitimately appear on multiple days (watched yesterday
  // and again today), so we store a timestamp PER ENTRY rather than per
  // videoId. This is what lets a re-watched video stay in both days.
  final List<DateTime> _watchTimes = [];

  // Groups the history videos by their watch day and returns an ordered list of
  // (label, videos) pairs, newest day first. Because each entry carries its
  // own timestamp, a video watched on several days shows up under each of them.
  List<Map<String, dynamic>> get _groupedHistory {
    final Map<String, List<PlayerVideo>> buckets = {};
    final Map<String, DateTime> bucketDay = {};

    for (var i = 0; i < _historyVideos.length; i++) {
      final v = _historyVideos[i];
      if (i >= _watchTimes.length) continue;
      final ts = _watchTimes[i];
      final dayKey = '${ts.year}-${ts.month}-${ts.day}';
      buckets.putIfAbsent(dayKey, () => []).add(v);
      bucketDay[dayKey] = ts;
    }

    final keys = buckets.keys.toList()
      ..sort((a, b) => bucketDay[b]!.compareTo(bucketDay[a]!));

    return keys.map((k) => {
      'label': _historyDateLabel(bucketDay[k]!),
      'videos': buckets[k]!,
    }).toList();
  }

  // Applies the optional date filter (search by date) to the history list.
  List<PlayerVideo> get _filteredHistory {
    if (_historyDateFilter == null) return _historyVideos;
    final filterDay = DateTime(_historyDateFilter!.year, _historyDateFilter!.month, _historyDateFilter!.day);
    final result = <PlayerVideo>[];
    for (var i = 0; i < _historyVideos.length; i++) {
      if (i >= _watchTimes.length) continue;
      final ts = _watchTimes[i];
      final day = DateTime(ts.year, ts.month, ts.day);
      if (day.isAtSameMomentAs(filterDay)) result.add(_historyVideos[i]);
    }
    return result;
  }

  // 🚀 Opens a date picker so the user can search for videos watched on a
  // specific date. Only videos watched on that date are then shown.
  Future<void> _pickHistoryDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _historyDateFilter ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF00E5FF),
            onPrimary: Colors.black,
            surface: Color(0xFF1E293B),
            onSurface: Colors.white,
          ),
          dialogTheme: const DialogThemeData(backgroundColor: Color(0xFF1E293B)),
        ),
        child: child!,
      ),
    );
    if (picked != null && mounted) {
      setState(() => _historyDateFilter = picked);
    }
  }

  Widget _buildSidebarItem({required IconData icon, required String label, required int index, VoidCallback? customOnTap}) {
    final isSelected = _selectedIndex == index;
    final color = isSelected ? const Color(0xFF00E5FF) : Colors.white;
    final bgColor = isSelected ? const Color(0xFF00E5FF).withAlpha(20) : Colors.transparent;

    return InkWell(
      onTap: customOnTap ?? () {
        setState(() => _selectedIndex = index);
        if (index == 2) _loadHistory(); // Load history when History tab is clicked
      },
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        margin: _isSidebarExpanded 
            ? const EdgeInsets.symmetric(horizontal: 12, vertical: 4)
            : const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        padding: _isSidebarExpanded 
            ? const EdgeInsets.symmetric(horizontal: 16, vertical: 12)
            : const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: _isSidebarExpanded ? bgColor : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: _isSidebarExpanded
            ? Row(
                children: [
                  Icon(icon, color: color, size: 24),
                  const SizedBox(width: 24),
                  Flexible(
                    child: Text(
                      label, 
                      style: TextStyle(color: color, fontSize: 14, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal), 
                      overflow: TextOverflow.clip, 
                      maxLines: 1
                    ),
                  ),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: color, size: 24),
                  const SizedBox(height: 6),
                  Text(label, style: TextStyle(color: color, fontSize: 10)),
                ],
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.menu, color: Color(0xFF00E5FF)),
          onPressed: () {
            setState(() {
              _isSidebarExpanded = !_isSidebarExpanded;
            });
          },
        ),
        title: const Row(
          children: [
            Icon(LucideIcons.youtube, color: Color(0xFF00E5FF)),
            Text(' Guptik Mediaplayer', style: TextStyle(color: Colors.white)),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: ElevatedButton.icon(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DesktopUploadScreen())),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E5FF), foregroundColor: Colors.black),
              icon: const Icon(Icons.upload, size: 18),
              label: const Text("Upload Video", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          )
        ],
      ),
      body: Row(
        children: [
          // SIDEBAR
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            width: _isSidebarExpanded ? 240 : 80, 
            decoration: const BoxDecoration(
              color: Color(0xFF0F172A),
              border: Border(right: BorderSide(color: Colors.white12)),
            ),
            child: SingleChildScrollView(
              child: Column(
                children: [
                const SizedBox(height: 12),
                _buildSidebarItem(icon: Icons.home_filled, label: 'Home', index: 0),
                _buildSidebarItem(icon: Icons.amp_stories, label: 'Shorts', index: 1),
                
                // HISTORY TAB
                _buildSidebarItem(icon: Icons.history, label: 'History', index: 2),
                
                const SizedBox(height: 8),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.0),
                  child: Divider(color: Colors.white12, thickness: 1),
                ),
                const SizedBox(height: 8),
                
                _buildSidebarItem(
                  icon: Icons.account_circle_outlined, 
                  label: 'Channel', 
                  index: 3, 
                  customOnTap: () {
                    final currentUser = Supabase.instance.client.auth.currentUser;
                    if (currentUser != null) {
                      // 🚀 FIX: Open the channel the same way the media player
                      // screen does (creatorUid + creatorNodeUrl). For the home
                      // screen we use the current user's id as the creatorUid.
                      //
                      // For the node URL we use the LOCAL gateway
                      // (http://localhost:55000) normalized by DockerService,
                      // NOT the Cloudflare tunnel URL. The tunnel URL causes
                      // "HandshakeException: Connection terminated during
                      // handshake" because it is stale / not serving TLS, while
                      // the local gateway is plain HTTP and is proven reachable
                      // (the watch-history feature uses the exact same URL).
                      final navigator = Navigator.of(context);
                      final nodeUrl = DockerService.normalizeGatewayUrl(widget.gatewayUrl);
                      navigator.push(
                        MaterialPageRoute(
                          builder: (_) => CreatorProfileScreen(
                            creatorUid: currentUser.id,
                            creatorNodeUrl: nodeUrl,
                          ),
                        ),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please log in first.'), backgroundColor: Colors.redAccent),
                      );
                    }
                  }
                ),

                // 🚀 NEW: Watch Later — opens saved folder
                _buildSidebarItem(
                  icon: Icons.watch_later_outlined,
                  label: 'Watch Later',
                  index: 4,
                  customOnTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const DesktopSystemFolderScreen(
                          folderType: 'saved',
                          folderTitle: 'Watch Later',
                          folderIcon: Icons.watch_later_outlined,
                          folderColor: Color(0xFF00E5FF),
                        ),
                      ),
                    );
                  },
                ),

                // 🚀 NEW: Drafts — opens draft folder
                _buildSidebarItem(
                  icon: Icons.drafts_outlined,
                  label: 'Drafts',
                  index: 5,
                  customOnTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const DesktopSystemFolderScreen(
                          folderType: 'drafts',
                          folderTitle: 'Draft Videos',
                          folderIcon: Icons.drafts_outlined,
                          folderColor: Colors.orange,
                        ),
                      ),
                    );
                  },
                ),

                // 🚀 NEW: Playlists
                _buildSidebarItem(
                  icon: Icons.playlist_play,
                  label: 'Playlists',
                  index: 6,
                  customOnTap: () {
                    final currentUser = Supabase.instance.client.auth.currentUser;
                    if (currentUser != null) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PlaylistManagementScreen(channelId: currentUser.id),
                        ),
                      );
                    }
                  },
                ),

                // 🚀 NEW: Monetization Dashboard
                _buildSidebarItem(
                  icon: Icons.monetization_on_outlined,
                  label: 'Earnings',
                  index: 7,
                  customOnTap: () {
                    final currentUser = Supabase.instance.client.auth.currentUser;
                    if (currentUser != null) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => MonetizationDashboardScreen(channelId: currentUser.id),
                        ),
                      );
                    }
                  },
                ),

                // 🚀 NEW: Notifications
                _buildSidebarItem(
                  icon: Icons.notifications_outlined,
                  label: 'Alerts',
                  index: 8,
                  customOnTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const NotificationsScreen(),
                      ),
                    );
                  },
                ),
                ],
              ),
            ),
          ),

          // MAIN CONTENT
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF)))
                : RefreshIndicator(
                    color: const Color(0xFF00E5FF),
                    backgroundColor: const Color(0xFF1E293B),
                    onRefresh: _selectedIndex == 2 ? _loadHistory : _loadFeed, 
                    child: _buildMainFeed(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainFeed() {
    // Top Bar (Search + Filters)
    Widget buildSearchBarAndFilters() {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search Bar
          Container(
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white12),
            ),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white),
              onChanged: (val) => setState(() => _searchQuery = val),
              decoration: const InputDecoration(
                hintText: "Search videos...",
                hintStyle: TextStyle(color: Colors.grey),
                prefixIcon: Icon(Icons.search, color: Colors.grey),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 24),
          
          // YouTube Style Filter Chips
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _filters.length,
              // 🚀 THE FIX: Changed from (_, __) to (context, index)
              separatorBuilder: (context, index) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final filter = _filters[index];
                final isSelected = _selectedFilter == filter;
                return ChoiceChip(
                  label: Text(filter, style: TextStyle(color: isSelected ? Colors.black : Colors.white, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                  selected: isSelected,
                  selectedColor: Colors.white,
                  backgroundColor: const Color(0xFF1E293B),
                  side: BorderSide.none,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  onSelected: (selected) {
                    setState(() => _selectedFilter = filter);
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 32),
        ],
      );
    }

    final activeFeed = _filteredVideos;
    final int splitIndex = activeFeed.length > 4 ? 4 : activeFeed.length;
    final List<PlayerVideo> topVideos = activeFeed.sublist(0, splitIndex);
    final List<PlayerVideo> bottomVideos = activeFeed.sublist(splitIndex);

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(), 
      padding: const EdgeInsets.fromLTRB(32, 16, 32, 32), 
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          
          // VIEW 1: HOME SCREEN
          if (_selectedIndex == 0) ...[
            buildSearchBarAndFilters(),
            
            if (topVideos.isEmpty && _reels.isEmpty)
              const Text("No videos found matching your search/filter.", style: TextStyle(color: Colors.grey)),
            
            if (topVideos.isNotEmpty)
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(), 
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 520, 
                  mainAxisSpacing: 48,     
                  crossAxisSpacing: 24, 
                  childAspectRatio: 1.28,  
                ),
                itemCount: topVideos.length,
                itemBuilder: (context, index) => PlayerVideoCard(
                  video: topVideos[index],
                  onReturn: _loadFeed, 
                ),
              ),

            if (_reels.isNotEmpty && _searchQuery.isEmpty && _selectedFilter == 'All') ...[
              const SizedBox(height: 48),
              const Divider(color: Colors.white12),
              const SizedBox(height: 24),
              
              const Row(
                children: [
                  Icon(Icons.amp_stories, color: Color(0xFF00E5FF)),
                  SizedBox(width: 8),
                  Text("Shorts & Reels", style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 520, 
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _reels.length,
                  separatorBuilder: (context, index) => const SizedBox(width: 16),
                  itemBuilder: (context, index) => PlayerVideoCard(
                    video: _reels[index],
                    onReturn: _loadFeed, 
                  ),
                ),
              ),
              
              const SizedBox(height: 24),
              const Divider(color: Colors.white12),
              const SizedBox(height: 48),
            ],

            if (bottomVideos.isNotEmpty) ...[
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(), 
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 520, 
                  mainAxisSpacing: 48, 
                  crossAxisSpacing: 24, 
                  childAspectRatio: 1.28, 
                ),
                itemCount: bottomVideos.length,
                itemBuilder: (context, index) => PlayerVideoCard(
                  video: bottomVideos[index],
                  onReturn: _loadFeed,
                ),
              ),
            ],
          ],

          // VIEW 2: SHORTS ONLY GRID
          if (_selectedIndex == 1) ...[
            const Row(
              children: [
                Icon(Icons.amp_stories, color: Color(0xFF00E5FF), size: 28),
                SizedBox(width: 12),
                Text("All Shorts", style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 32),
            
            if (_reels.isEmpty)
              const Text("No Shorts available right now.", style: TextStyle(color: Colors.grey, fontSize: 16)),

            if (_reels.isNotEmpty)
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(), 
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 280, 
                  mainAxisSpacing: 48, 
                  crossAxisSpacing: 24, 
                  childAspectRatio: 0.48,  
                ),
                itemCount: _reels.length,
                itemBuilder: (context, index) => PlayerVideoCard(
                  video: _reels[index],
                  onReturn: _loadFeed,
                ),
              ),
          ],
          
          // VIEW 3: WATCH HISTORY
          if (_selectedIndex == 2) ...[
            const Row(
              children: [
                Icon(Icons.history, color: Color(0xFF00E5FF), size: 28),
                SizedBox(width: 12),
                Text("Watch History", style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 16),

            // 🚀 DATE SEARCH BAR: pick a date to filter history to that day only.
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _pickHistoryDate,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E293B),
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white24),
                  ),
                  icon: const Icon(Icons.calendar_today, size: 18, color: Color(0xFF00E5FF)),
                  label: Text(
                    _historyDateFilter == null
                        ? "Search by date"
                        : "Watched on: ${_historyDateFilter!.day}/${_historyDateFilter!.month}/${_historyDateFilter!.year}",
                  ),
                ),
                if (_historyDateFilter != null) ...[
                  const SizedBox(width: 12),
                  TextButton.icon(
                    onPressed: () => setState(() => _historyDateFilter = null),
                    icon: const Icon(Icons.clear, size: 16, color: Colors.grey),
                    label: const Text("Clear", style: TextStyle(color: Colors.grey)),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 24),

            if (_historyVideos.isEmpty)
              const Text("You haven't watched any videos yet.", style: TextStyle(color: Colors.grey, fontSize: 16)),

            // 🚀 When a date is selected we show ONLY that day's videos.
            if (_historyVideos.isNotEmpty && _historyDateFilter != null) ...[
              if (_filteredHistory.isEmpty)
                const Text(
                  "No videos were watched on this date.",
                  style: TextStyle(color: Colors.grey, fontSize: 16),
                )
              else
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 520,
                    mainAxisSpacing: 48,
                    crossAxisSpacing: 24,
                    childAspectRatio: 1.28,
                  ),
                  itemCount: _filteredHistory.length,
                  itemBuilder: (context, index) => PlayerVideoCard(
                    video: _filteredHistory[index],
                    onReturn: _loadHistory,
                  ),
                ),
            ],

            // 🚀 Otherwise show the full history grouped by date (Today, Yesterday, etc.)
            if (_historyVideos.isNotEmpty && _historyDateFilter == null) ...[
              for (final group in _groupedHistory) ...[
                Row(
                  children: [
                    Icon(Icons.calendar_month, color: Color(0xFF00E5FF).withAlpha(180), size: 20),
                    const SizedBox(width: 8),
                    Text(
                      group['label'] as String,
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 520,
                    mainAxisSpacing: 48,
                    crossAxisSpacing: 24,
                    childAspectRatio: 1.28,
                  ),
                  itemCount: (group['videos'] as List<PlayerVideo>).length,
                  itemBuilder: (context, index) => PlayerVideoCard(
                    video: (group['videos'] as List<PlayerVideo>)[index],
                    onReturn: _loadHistory,
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ],
          ],
        ],
      ),
    );
  }
}