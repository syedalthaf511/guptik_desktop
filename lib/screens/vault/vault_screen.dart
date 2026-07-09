import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart'; 
import '../../models/vault_file.dart';
import '../../services/supabase_service.dart';
import '../../services/storage_service.dart';
import '../../services/external/postgres_service.dart';
import '../../screens/mediaplayer/desktop_system_folder_screen.dart'; // 🚀 IMPORT ADDED

class VaultScreen extends StatefulWidget {
  const VaultScreen({super.key});

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  final StorageService _storage = StorageService();
  final SupabaseService _supabase = SupabaseService();

  List<VaultFile> _files = [];
  bool _isLoading = true;
  String? _vaultPath; 
  String? _publicUrl;

  @override
  void initState() {
    super.initState();
    _loadConfigAndFiles();
  }

  Future<void> _loadConfigAndFiles() async {
    setState(() => _isLoading = true);

    final prefs = await SharedPreferences.getInstance();
    String? storedPath = prefs.getString('vault_path');
    String? storedUrl = await _storage.getPublicUrl();
    final userId = _supabase.currentUserId;

    if ((storedPath == null || storedUrl == null || storedUrl.isEmpty) && userId != null) {
      try {
        final data = await Supabase.instance.client
            .from('desktop_devices')
            .select('vault_path, public_url')
            .eq('user_id', userId)
            .not('public_url', 'is', null)
            .limit(1)
            .maybeSingle();

        if (data != null) {
          if (storedPath == null && data['vault_path'] != null) {
            storedPath = data['vault_path'];
            await prefs.setString('vault_path', storedPath!);
          }
          if ((storedUrl == null || storedUrl.isEmpty) && data['public_url'] != null) {
            storedUrl = data['public_url'];
            storedUrl = storedUrl!.replaceAll('https://', '').replaceAll('http://', '');
            if (storedUrl.endsWith('/')) storedUrl = storedUrl.substring(0, storedUrl.length - 1);
          }
        }
      } catch (e) {
        debugPrint("❌ Error fetching config from DB: $e");
      }
    }

    if (storedPath == null || storedPath.isEmpty) {
      if (Platform.isWindows) {
        storedPath = 'C:\\GuptikVault';
      } else {
        storedPath = '${Platform.environment['HOME']}/GuptikVault';
      }
    }

    final String correctVaultPath = "$storedPath${Platform.pathSeparator}vault_files";

    if (mounted) {
      setState(() {
        _vaultPath = correctVaultPath;
        _publicUrl = (storedUrl != null && storedUrl.isNotEmpty) ? storedUrl : null;
      });
      await _refreshFiles();
    }
  }

  Future<void> _refreshFiles() async {
    if (_vaultPath == null) return;
    final dir = Directory(_vaultPath!);

    if (!await dir.exists()) await dir.create(recursive: true);

    try {
      final List<FileSystemEntity> entities = dir.listSync(recursive: false); 
      final List<File> files = entities.whereType<File>().toList();

      files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));

      final userId = _supabase.currentUserId ?? 'local-user';

      List<VaultFile> loadedFiles = files.map((file) {
        final stat = file.statSync();
        return VaultFile(
          id: file.path.hashCode.toString(),
          userId: userId,
          fileName: file.path.split(Platform.pathSeparator).last,
          filePath: file.path,
          fileType: file.path.split('.').last,
          mimeType: _getMimeType(file.path),
          sizeBytes: BigInt.from(stat.size),
          isFavorite: false,
          syncedAt: stat.modified,
          createdAt: stat.changed,
        );
      }).toList();

      if (mounted) {
        setState(() {
          _files = loadedFiles;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _handleShare(VaultFile file) {
    if (_publicUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Public URL not configured. Check Settings.")),
      );
      return;
    }

    bool isPublic = false;
    DateTime? selectedExpiration;
    final TextEditingController emailsController = TextEditingController();
    String? generatedLink;
    bool isGenerating = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateBuilder) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            title: Text("Share: ${file.fileName}", style: const TextStyle(color: Colors.white, fontSize: 16)),
            content: SizedBox(
              width: 400,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                      title: const Text("Make Public link", style: TextStyle(color: Colors.white)),
                      subtitle: Text(isPublic ? "Anyone with the link can view" : "Only allowed emails with token", style: TextStyle(color: Colors.grey[400], fontSize: 12)),
                      activeThumbColor: Colors.cyanAccent,
                      value: isPublic,
                      onChanged: (val) {
                        setStateBuilder(() {
                          isPublic = val;
                          generatedLink = null;
                        });
                      },
                    ),
                    const Divider(color: Colors.grey),
                    if (!isPublic) ...[
                      const Text("Allowed Emails (comma separated)", style: TextStyle(color: Colors.white, fontSize: 12)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: emailsController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: "user1@mail.com, user2@mail.com",
                          hintStyle: TextStyle(color: Colors.grey[600]),
                          filled: true,
                          fillColor: const Color(0xFF0F172A),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          selectedExpiration == null ? "No Expiration Date" : "Expires: ${selectedExpiration!.toLocal().toString().split(' ')[0]}",
                          style: TextStyle(color: Colors.grey[400], fontSize: 12),
                        ),
                        TextButton.icon(
                          icon: const Icon(Icons.calendar_today, size: 14, color: Colors.cyanAccent),
                          label: const Text("Set Date", style: TextStyle(color: Colors.cyanAccent)),
                          onPressed: () async {
                            final date = await showDatePicker(
                              context: context,
                              initialDate: DateTime.now().add(const Duration(days: 7)),
                              firstDate: DateTime.now(),
                              lastDate: DateTime.now().add(const Duration(days: 365)),
                            );
                            if (date != null) setStateBuilder(() => selectedExpiration = date);
                          },
                        ),
                      ],
                    ),
                    if (generatedLink != null) ...[
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8)),
                        child: SelectableText(
                          generatedLink!,
                          style: const TextStyle(color: Colors.cyanAccent, fontFamily: 'Courier', fontSize: 12),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text("Close", style: TextStyle(color: Colors.grey))),
              if (generatedLink == null)
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.cyanAccent, foregroundColor: Colors.black),
                  onPressed: isGenerating
                      ? null
                      : () async {
                          setStateBuilder(() => isGenerating = true);
                          try {
                            List<String> emails = emailsController.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
                            final token = await PostgresService().createShareSettings(
                                  fileName: file.fileName,
                                  isPublic: isPublic,
                                  emails: emails,
                                  expiresAt: selectedExpiration,
                                );
                            final safeName = Uri.encodeComponent(file.fileName);
                            String link = "https://$_publicUrl/vault/files/$safeName";
                            if (!isPublic && token != null) link += "?token=$token";
                            setStateBuilder(() {
                              generatedLink = link;
                              isGenerating = false;
                            });
                          } catch (e) {
                            setStateBuilder(() => isGenerating = false);
                            // 🚀 FIXED: Wrapped within explicit context mounted assertion logic checks
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
                            }
                          }
                        },
                  child: isGenerating ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text("Generate Link"),
                )
              else
                ElevatedButton.icon(
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text("Copy Link"),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.cyanAccent, foregroundColor: Colors.black),
                  onPressed: () async {
                    // 🚀 FIXED: Captured structural instance context snapshot before async gaps to bypass context leaks
                    final messenger = ScaffoldMessenger.of(context);
                    await Clipboard.setData(ClipboardData(text: generatedLink!));
                    messenger.showSnackBar(const SnackBar(content: Text("Link copied to clipboard!")));
                    if (context.mounted) Navigator.pop(context);
                  },
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openFile(String? path) async {
    if (path == null) return;
    try {
      if (Platform.isLinux) {
        await Process.run('xdg-open', [path]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [path]);
      } else if (Platform.isWindows) {
        await Process.run('explorer', [path]);
      }
    } catch (e) {
      debugPrint("Could not open file: $e");
    }
  }

  String _getMimeType(String? path) {
    if (path == null) return 'application/octet-stream';
    final ext = path.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg': case 'jpeg': return 'image/jpeg';
      case 'png': return 'image/png';
      case 'pdf': return 'application/pdf';
      case 'mp4': return 'video/mp4';
      default: return 'application/octet-stream';
    }
  }

  // 🚀 ROUTING: Triggers when a System Folder is clicked
  void _openSystemFolder(String folderName) {
    String type = 'drafts';
    IconData icon = LucideIcons.edit3;
    Color color = Colors.purpleAccent;

    if (folderName == "Posted Videos") {
      type = 'posted';
      icon = LucideIcons.uploadCloud;
      color = const Color(0xFF00E5FF);
    } else if (folderName == "Saved Videos") {
      type = 'saved';
      icon = LucideIcons.bookmark;
      color = Colors.amberAccent;
    } else if (folderName == "Repost Videos") {
      type = 'repost';
      icon = LucideIcons.repeat;
      color = Colors.lightGreenAccent;
    } else if (folderName == "Vault Folder") {
      type = 'vault_sys';
      icon = LucideIcons.shield;
      color = Colors.orangeAccent;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DesktopSystemFolderScreen(
          folderType: type,
          folderTitle: folderName,
          folderIcon: icon,
          folderColor: color,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text("Central Vault", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_open, color: Colors.white),
            tooltip: "Open in System Explorer",
            onPressed: () {
              if (_vaultPath != null) _openFile(_vaultPath);
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white), 
            onPressed: _refreshFiles
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF)))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Local Files", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                      Text(
                        "Root: ${_vaultPath?.split(Platform.pathSeparator).last ?? ''}", 
                        style: TextStyle(color: Colors.grey.shade500, fontFamily: 'Courier', fontSize: 12)
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  GridView.builder(
                    shrinkWrap: true, 
                    physics: const NeverScrollableScrollPhysics(), 
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 180, 
                      childAspectRatio: 0.85,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                    ),
                    itemCount: _files.length + 5,
                    itemBuilder: (context, index) {
                      
                      // 1. Render the "Posted Videos" Folder
                      if (index == 0) {
                        return _buildVirtualFolderCard("Posted Videos", LucideIcons.uploadCloud, const Color(0xFF00E5FF));
                      }
                      // 2. Render the "Saved Videos" Folder
                      if (index == 1) {
                        return _buildVirtualFolderCard("Saved Videos", LucideIcons.bookmark, Colors.amberAccent);
                      }
                      // 3. Render the "Drafts" Folder
                      if (index == 2) {
                        return _buildVirtualFolderCard("Drafts", LucideIcons.edit3, Colors.purpleAccent);
                      }
                      // 4. Render the "Repost Videos" Folder
                      if (index == 3) {
                        return _buildVirtualFolderCard("Repost Videos", LucideIcons.repeat, Colors.lightGreenAccent);
                      }
                      // 5. Render the "Vault Folder" Folder
                      if (index == 4) {
                        return _buildVirtualFolderCard("Vault Folder", LucideIcons.shield, Colors.orangeAccent);
                      }

                      // 6. Render the actual physical files
                      return _buildFileCard(_files[index - 5]);
                    },
                  ),
                ],
              ),
            ),
    );
  }

  // 🚀 WIDGET: A square folder that perfectly matches the File Card dimensions
  Widget _buildVirtualFolderCard(String title, IconData icon, Color color) {
    return InkWell(
      onTap: () => _openSystemFolder(title),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(12),
          // 🚀 FIXED: Swapped deprecated .withOpacity constraints for .withValues parameters
          border: Border.all(color: color.withValues(alpha: 0.3), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.05),
              blurRadius: 15,
              offset: const Offset(0, 5),
            )
          ]
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 36),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              "System Folder",
              style: TextStyle(color: Colors.grey.shade400, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileCard(VaultFile file) {
    final fType = (file.fileType ?? "").toLowerCase();
    final bool isImg = ['jpg', 'jpeg', 'png', 'webp'].contains(fType);
    final safePath = file.filePath;

    return InkWell(
      onTap: () => _openFile(safePath),
      onSecondaryTap: () => _handleShare(file),
      onLongPress: () => _handleShare(file),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(12),
          // 🚀 FIXED: Adjusted color rendering format layout targets to clear opacity deprecations
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: Column(
          children: [
            Expanded(
              child: isImg && safePath.isNotEmpty
                  ? ClipRRect(
                      borderRadius: const BorderRadius.only(topLeft: Radius.circular(12), topRight: Radius.circular(12)),
                      child: Image.file(File(safePath), fit: BoxFit.cover, width: double.infinity),
                    )
                  : Center(
                      child: Icon(
                        _getFileIcon(fType),
                        size: 40,
                        color: const Color(0xFF00E5FF),
                      ),
                    ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12.0),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Colors.white10))
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatSize(file.sizeBytes),
                    style: TextStyle(color: Colors.grey[500], fontSize: 10),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getFileIcon(String ext) {
    switch (ext) {
      case 'pdf': return LucideIcons.fileText;
      case 'mp4': return LucideIcons.video;
      case 'zip': return LucideIcons.archive;
      default: return LucideIcons.file;
    }
  }

  String _formatSize(BigInt? bytes) {
    if (bytes == null) return '0 B';
    int b = bytes.toInt();
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}