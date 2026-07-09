import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../models/mediaplayer/player_video_model.dart';
import '../../services/mediaplayer/player_api_service.dart';
import 'desktop_upload__screen.dart'; // 🚀 Added to open the upload screen

class CreatorProfileScreen extends StatefulWidget {
  final String creatorUid;
  final String creatorNodeUrl;

  const CreatorProfileScreen({
    super.key, 
    required this.creatorUid, 
    required this.creatorNodeUrl
  });

  @override
  State<CreatorProfileScreen> createState() => _CreatorProfileScreenState();
}

class _CreatorProfileScreenState extends State<CreatorProfileScreen> {
  late PlayerApiService _apiService;
  
  Map<String, dynamic>? _profileData;
  List<PlayerVideo> _normalVideos = [];
  List<PlayerVideo> _reels = [];
  bool _isLoading = true;

  bool _isSubscribed = false;
  int _subscriberCount = 0;
  final bool _isToggling = false;

  int _selectedTabIndex = 0;
  int _selectedSidebarIndex = 1;

  final Set<String> _selectedVideoIds = {};

  @override
  void initState() {
    super.initState();
    final safeUrl = widget.creatorNodeUrl.startsWith('http') 
        ? widget.creatorNodeUrl 
        : 'https://${widget.creatorNodeUrl}';
        
    _apiService = PlayerApiService(gatewayUrl: safeUrl);
    
    _loadProfileData();
  }

  Future<void> _loadProfileData() async {
    final profileFuture = _apiService.fetchChannelProfile(widget.creatorNodeUrl, widget.creatorUid);
    final videosFuture = _apiService.fetchChannelVideos(widget.creatorNodeUrl, widget.creatorUid);

    final results = await Future.wait([profileFuture, videosFuture]);

    if (mounted) {
      setState(() {
        _profileData = results[0] as Map<String, dynamic>?;
        
        final List<PlayerVideo> allVideos = results[1] as List<PlayerVideo>;
        _reels = allVideos.where((v) => v.isReel).toList();
        _normalVideos = allVideos.where((v) => !v.isReel).toList();
        
        _subscriberCount = _profileData?['subscribers'] ?? 0;
        _selectedVideoIds.clear(); 
        _isLoading = false;
      });
      
      _checkIfSubscribed();
    }
  }

  Future<void> _checkIfSubscribed() async {
    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser != null) {
      final isSubbed = await _apiService.checkSubscriptionStatus(
        widget.creatorNodeUrl, 
        widget.creatorUid, 
        currentUser.id
      );
      if (mounted) setState(() => _isSubscribed = isSubbed);
    }
  }

  Future<void> _deleteVideo(PlayerVideo video) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator(color: Colors.redAccent)),
    );

    final success = await _apiService.deleteVideo(video.videoId, video.creatorUid);
    
    if (mounted) {
      Navigator.pop(context); 
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Video permanently deleted.'), backgroundColor: Colors.green));
        _loadProfileData(); 
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to delete video.'), backgroundColor: Colors.redAccent));
      }
    }
  }

  String _formatDate(String? dateString) {
    if (dateString == null || dateString.isEmpty) return 'Unknown'; 
    try {
      final date = DateTime.parse(dateString);
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${date.day} ${months[date.month - 1]} ${date.year}';
    } catch (e) { return 'Recently'; }
  }

  Widget _buildSidebarItem(IconData icon, String label, int index) {
    final isSelected = _selectedSidebarIndex == index;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFF1E293B) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        leading: Icon(icon, color: isSelected ? const Color(0xFF00E5FF) : Colors.grey.shade400, size: 20),
        title: Text(label, style: TextStyle(color: isSelected ? Colors.white : Colors.grey.shade300, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, fontSize: 14)),
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        onTap: () {
          setState(() { _selectedSidebarIndex = index; });
        },
      ),
    );
  }

  Widget _buildStudioSidebar(String channelName) {
    return Container(
      width: 240,
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        border: Border(right: BorderSide(color: Colors.white12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 0, 16),
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          Center(
            child: CircleAvatar(
              radius: 45,
              backgroundColor: const Color(0xFF00E5FF),
              child: Text(channelName.isNotEmpty ? channelName[0].toUpperCase() : '?', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 36)),
            ),
          ),
          const SizedBox(height: 16),
          const Center(child: Text("Your channel", style: TextStyle(color: Colors.grey, fontSize: 12))),
          const SizedBox(height: 4),
          Center(child: Text(channelName, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold))),
          const SizedBox(height: 32),
          
          _buildSidebarItem(Icons.dashboard_outlined, "Dashboard", 0),
          _buildSidebarItem(Icons.video_library_outlined, "Content", 1),
        ],
      ),
    );
  }

  Widget _buildVideoRow(PlayerVideo video) {
    final safeUrl = widget.creatorNodeUrl.startsWith('http') ? widget.creatorNodeUrl : 'https://${widget.creatorNodeUrl}';
    final thumbnailUrl = '$safeUrl/player/video/thumbnail/${video.videoId}';
    
    final bool isSelected = _selectedVideoIds.contains(video.videoId);

    IconData visIcon = Icons.public;
    Color visColor = Colors.green;
    String visText = "Public";
    
    if (video.visibility.toLowerCase() == 'private') {
      visIcon = Icons.lock_outline;
      visColor = Colors.grey;
      visText = "Private";
    } else if (video.visibility.toLowerCase() == 'unlisted') {
      visIcon = Icons.link;
      visColor = Colors.orangeAccent;
      visText = "Unlisted";
    }

    return Container(
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFF00E5FF).withAlpha(10) : Colors.transparent,
        border: const Border(bottom: BorderSide(color: Colors.white12)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 16, top: 12),
            child: Checkbox(
              value: isSelected,
              activeColor: const Color(0xFF00E5FF),
              checkColor: Colors.black,
              side: const BorderSide(color: Colors.grey),
              onChanged: (bool? checked) {
                setState(() {
                  if (checked == true) {
                    _selectedVideoIds.add(video.videoId);
                  } else {
                    _selectedVideoIds.remove(video.videoId);
                  }
                });
              },
            ),
          ),
          
          Expanded(
            flex: 5,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox(
                    width: video.isReel ? 50 : 120, 
                    height: video.isReel ? 88 : 68,
                    child: Image.network(
                      thumbnailUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (ctx, err, stk) => Container(color: Colors.grey.shade800),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(video.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 4),
                      Text(video.description.isNotEmpty ? video.description : "Add description", maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Row(
                children: [
                  Icon(visIcon, color: visColor, size: 16),
                  const SizedBox(width: 6),
                  Text(visText, style: TextStyle(color: Colors.grey.shade300, fontSize: 13)),
                ],
              ),
            ),
          ),
          
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_formatDate(video.createdAt), style: TextStyle(color: Colors.grey.shade300, fontSize: 13)),
                  const SizedBox(height: 4),
                  Text("Published", style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
                ],
              ),
            ),
          ),
          
          Expanded(
            flex: 1,
            child: Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(video.viewCount.toString(), style: TextStyle(color: Colors.grey.shade300, fontSize: 13)),
            ),
          ),
          
          Expanded(
            flex: 1,
            child: Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(video.commentCount.toString(), style: TextStyle(color: Colors.grey.shade300, fontSize: 13)),
                  
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, color: Colors.grey, size: 20),
                    color: const Color(0xFF1E293B),
                    tooltip: "Options",
                    onSelected: (value) {
                      if (value == 'edit') {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => DesktopUploadScreen(videoToEdit: video),
                          )
                        );
                      } else if (value == 'delete') {
                        showDialog(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            backgroundColor: const Color(0xFF1E293B),
                            title: const Text("Delete Video?", style: TextStyle(color: Colors.white)),
                            content: const Text("This action cannot be undone. Are you sure?", style: TextStyle(color: Colors.grey)),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel", style: TextStyle(color: Colors.white))),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  _deleteVideo(video);
                                },
                                child: const Text("Delete Forever", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              )
                            ],
                          )
                        );
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit, color: Colors.white, size: 18), SizedBox(width: 12), Text("Edit title and description", style: TextStyle(color: Colors.white))])),
                      const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_forever, color: Colors.redAccent, size: 18), SizedBox(width: 12), Text("Delete forever", style: TextStyle(color: Colors.redAccent))])),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildDashboardView() {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Channel dashboard", style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
          const SizedBox(height: 32),
          Container(
            width: 300,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white12)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Channel analytics", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                const Text("Current subscribers", style: TextStyle(color: Colors.grey, fontSize: 14)),
                const SizedBox(height: 8),
                Text(_subscriberCount.toString(), style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                const Divider(color: Colors.white12),
                const SizedBox(height: 16),
                const Text("Summary", style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Total Videos", style: TextStyle(color: Colors.grey, fontSize: 14)),
                    Text("${_normalVideos.length + _reels.length}", style: const TextStyle(color: Colors.white, fontSize: 14)),
                  ],
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildContentView() {
    final activeList = _selectedTabIndex == 0 ? _normalVideos : _reels;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(padding: EdgeInsets.fromLTRB(32, 32, 32, 16), child: Text("Channel content", style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold))),
        
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              InkWell(
                onTap: () => setState(() { _selectedTabIndex = 0; _selectedVideoIds.clear(); }),
                child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), decoration: BoxDecoration(border: Border(bottom: BorderSide(color: _selectedTabIndex == 0 ? Colors.white : Colors.transparent, width: 3))), child: Text("Videos", style: TextStyle(color: _selectedTabIndex == 0 ? Colors.white : Colors.grey.shade400, fontWeight: _selectedTabIndex == 0 ? FontWeight.bold : FontWeight.w500, fontSize: 15))),
              ),
              InkWell(
                onTap: () => setState(() { _selectedTabIndex = 1; _selectedVideoIds.clear(); }),
                child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), decoration: BoxDecoration(border: Border(bottom: BorderSide(color: _selectedTabIndex == 1 ? Colors.white : Colors.transparent, width: 3))), child: Text("Shorts", style: TextStyle(color: _selectedTabIndex == 1 ? Colors.white : Colors.grey.shade400, fontWeight: _selectedTabIndex == 1 ? FontWeight.bold : FontWeight.w500, fontSize: 15))),
              ),
            ],
          ),
        ),
        const Divider(color: Colors.white12, height: 1, thickness: 1),
        
        if (_selectedVideoIds.isNotEmpty)
          Container(
            color: Colors.black,
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Text("${_selectedVideoIds.length} selected", style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                const SizedBox(width: 24),
                
                // 🚀 THE FIX: This button now finds the video and passes it to the upload screen
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E293B), foregroundColor: Colors.white),
                  onPressed: () {
                    final selectedId = _selectedVideoIds.first;
                    PlayerVideo? selectedVideo;
                    
                    try {
                      selectedVideo = _normalVideos.firstWhere((v) => v.videoId == selectedId);
                    } catch (e) {
                      try {
                        selectedVideo = _reels.firstWhere((v) => v.videoId == selectedId);
                      } catch (e) {}
                    }

                    if (selectedVideo != null) {
                      Navigator.push(
                        context, 
                        MaterialPageRoute(
                          builder: (_) => DesktopUploadScreen(videoToEdit: selectedVideo), 
                        )
                      );
                    }
                  },
                  icon: const Icon(Icons.edit, size: 16),
                  label: const Text("Edit"),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() => _selectedVideoIds.clear()), 
                  child: const Text("Clear Selection", style: TextStyle(color: Colors.grey))
                )
              ],
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(children: [const Icon(Icons.filter_list, color: Colors.grey, size: 20), const SizedBox(width: 16), Text("Filter", style: TextStyle(color: Colors.grey.shade400, fontSize: 14))]),
          ),
        
        const Divider(color: Colors.white12, height: 1, thickness: 1),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              const SizedBox(width: 36), 
              Expanded(flex: 5, child: Text("Video", style: TextStyle(color: Colors.grey.shade400, fontSize: 13, fontWeight: FontWeight.w500))),
              Expanded(flex: 2, child: Text("Visibility", style: TextStyle(color: Colors.grey.shade400, fontSize: 13, fontWeight: FontWeight.w500))),
              Expanded(flex: 2, child: Row(children: [Text("Date", style: TextStyle(color: Colors.grey.shade400, fontSize: 13, fontWeight: FontWeight.w500)), const Icon(Icons.arrow_downward, color: Colors.grey, size: 14)])),
              Expanded(flex: 1, child: Text("Views", style: TextStyle(color: Colors.grey.shade400, fontSize: 13, fontWeight: FontWeight.w500))),
              Expanded(flex: 1, child: Text("Comments", style: TextStyle(color: Colors.grey.shade400, fontSize: 13, fontWeight: FontWeight.w500))),
            ],
          ),
        ),
        const Divider(color: Colors.white12, height: 1, thickness: 1),

        Expanded(
          child: activeList.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [Icon(Icons.video_library_outlined, size: 100, color: Colors.grey.withOpacity(0.2)), const SizedBox(height: 16), Text("No content available", style: TextStyle(color: Colors.grey.shade400, fontSize: 16))],
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: activeList.length,
                itemBuilder: (context, index) {
                  return _buildVideoRow(activeList[index]);
                },
              ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(backgroundColor: Color(0xFF0F172A), body: Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF))));
    final channelName = _profileData?['channel_name'] ?? 'Unknown Creator';

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStudioSidebar(channelName),
          Expanded(
            child: Container(
              color: const Color(0xFF0F172A),
              child: _selectedSidebarIndex == 0 ? _buildDashboardView() : _buildContentView(),
            ),
          ),
        ],
      ),
    );
  }
}