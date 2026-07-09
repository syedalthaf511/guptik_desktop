 import 'package:flutter/material.dart';

import '../../models/mediaplayer/player_playlist_model.dart';
import '../../services/mediaplayer/player_organization_service.dart';

/// PlaylistManagementScreen — Create, view, and manage video playlists.
/// Allows creators to organize videos into themed collections.
class PlaylistManagementScreen extends StatefulWidget {
  final String channelId;

  const PlaylistManagementScreen({super.key, required this.channelId});

  @override
  State<PlaylistManagementScreen> createState() =>
      _PlaylistManagementScreenState();
}

class _PlaylistManagementScreenState extends State<PlaylistManagementScreen> {
  final PlayerOrganizationService _service = PlayerOrganizationService();
  List<PlayerPlaylist> _playlists = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPlaylists();
  }

  Future<void> _loadPlaylists() async {
    setState(() => _isLoading = true);
    final playlists = await _service.fetchPlaylists(widget.channelId);
    if (mounted) {
      setState(() {
        _playlists = playlists;
        _isLoading = false;
      });
    }
  }

  void _showCreatePlaylistDialog() {
    final nameController = TextEditingController();
    final descController = TextEditingController();
    bool isPublic = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: const Text('Create Playlist',
              style: TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Playlist Name',
                    labelStyle: TextStyle(color: Colors.grey),
                    filled: true,
                    fillColor: Color(0xFF0F172A),
                    border: OutlineInputBorder(borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: descController,
                  style: const TextStyle(color: Colors.white),
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Description (optional)',
                    labelStyle: TextStyle(color: Colors.grey),
                    filled: true,
                    fillColor: Color(0xFF0F172A),
                    border: OutlineInputBorder(borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text('Public Playlist',
                      style: TextStyle(color: Colors.white)),
                  subtitle: const Text('Allow others to see this playlist',
                      style: TextStyle(color: Colors.grey, fontSize: 12)),
                  activeThumbColor: const Color(0xFF00E5FF),
                  contentPadding: EdgeInsets.zero,
                  value: isPublic,
                  onChanged: (val) =>
                      setDialogState(() => isPublic = val),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel',
                  style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00E5FF)),
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isEmpty) return;

                final id = await _service.createPlaylist(
                  channelId: widget.channelId,
                  name: name,
                  description: descController.text.trim(),
                  isPublic: isPublic,
                );

                if (id != null && ctx.mounted) {
                  Navigator.pop(ctx);
                  _loadPlaylists();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text('Playlist "$name" created!'),
                        backgroundColor: Colors.green),
                  );
                }
              },
              child: const Text('Create',
                  style: TextStyle(
                      color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deletePlaylist(PlayerPlaylist playlist) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Delete Playlist?',
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
            'Are you sure you want to delete "${playlist.name}"? This cannot be undone.',
            style: const TextStyle(color: Colors.grey)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: Colors.white)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await _service.deletePlaylist(playlist.playlistId);
      if (success && mounted) {
        _loadPlaylists();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Playlist deleted.'),
              backgroundColor: Colors.orange),
        );
      }
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
        title: const Text('My Playlists',
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Color(0xFF00E5FF)),
            onPressed: _showCreatePlaylistDialog,
            tooltip: 'Create Playlist',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF)))
          : _playlists.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.playlist_play,
                          color: Colors.white24, size: 80),
                      const SizedBox(height: 16),
                      const Text('No playlists yet.',
                          style: TextStyle(color: Colors.grey, fontSize: 18)),
                      const SizedBox(height: 8),
                      const Text(
                          'Create a playlist to organize your videos.',
                          style:
                              TextStyle(color: Colors.grey, fontSize: 14)),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00E5FF),
                            foregroundColor: Colors.black),
                        onPressed: _showCreatePlaylistDialog,
                        icon: const Icon(Icons.add),
                        label: const Text('Create Playlist'),
                      ),
                    ],
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(32),
                  gridDelegate:
                      const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 400,
                    mainAxisSpacing: 24,
                    crossAxisSpacing: 16,
                    childAspectRatio: 0.85,
                  ),
                  itemCount: _playlists.length,
                  itemBuilder: (context, index) {
                    final playlist = _playlists[index];
                    return Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Thumbnail placeholder
                          Expanded(
                            child: Container(
                              width: double.infinity,
                              decoration: const BoxDecoration(
                                color: Color(0xFF0F172A),
                                borderRadius: BorderRadius.only(
                                  topLeft: Radius.circular(16),
                                  topRight: Radius.circular(16),
                                ),
                              ),
                              child: Stack(
                                children: [
                                  Center(
                                    child: Icon(
                                      playlist.isPublic
                                          ? Icons.public
                                          : Icons.lock,
                                      color: Colors.white24,
                                      size: 48,
                                    ),
                                  ),
                                  Positioned(
                                    top: 12,
                                    right: 12,
                                    child: PopupMenuButton<String>(
                                      icon: const Icon(Icons.more_vert,
                                          color: Colors.white54, size: 18),
                                      color: const Color(0xFF1E293B),
                                      onSelected: (value) {
                                        if (value == 'delete') {
                                          _deletePlaylist(playlist);
                                        }
                                      },
                                      itemBuilder: (context) => [
                                        const PopupMenuItem(
                                          value: 'delete',
                                          child: Row(children: [
                                            Icon(Icons.delete,
                                                color: Colors.redAccent,
                                                size: 16),
                                            SizedBox(width: 8),
                                            Text('Delete Playlist',
                                                style: TextStyle(
                                                    color: Colors.redAccent)),
                                          ]),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          // Info
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(playlist.name,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                                const SizedBox(height: 4),
                                Text(
                                  '${playlist.videoCount} videos • ${playlist.formattedDuration}',
                                  style: TextStyle(
                                      color: Colors.grey.shade400,
                                      fontSize: 13),
                                ),
                                const SizedBox(height: 8),
                                if (playlist.description.isNotEmpty)
                                  Text(playlist.description,
                                      style: TextStyle(
                                          color: Colors.grey.shade500,
                                          fontSize: 12),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
