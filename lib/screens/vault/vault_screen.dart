import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart'; // Needed for self-healing
import '../../models/vault_file.dart';
import '../../services/supabase_service.dart';
import '../../services/storage_service.dart';
import '../../services/external/postgres_service.dart';

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
  String? _vaultPath; // This will now point to .../vault_files
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
    String? deviceId = await _storage.getDeviceId();

    // SELF-HEALING: If path is missing locally, fetch from Database
    if (storedPath == null && deviceId != null) {
      try {
        final data = await Supabase.instance.client
            .from('desktop_devices')
            .select('vault_path')
            .eq('device_id', deviceId)
            .maybeSingle();

        if (data != null && data['vault_path'] != null) {
          storedPath = data['vault_path'];
          await prefs.setString(
            'vault_path',
            storedPath!,
          ); // Save for next time
        }
      } catch (e) {
        print("Error fetching path from DB: $e");
      }
    }

    // Fallback (Only if DB fetch also failed)
    if (storedPath == null) {
      if (Platform.isWindows) {
        storedPath = 'C:\\GuptikVault';
      } else {
        storedPath = '${Platform.environment['HOME']}/GuptikVault';
      }
    }

    // CRITICAL FIX: Append 'vault_files' to the path
    // The Docker container maps this specific subfolder to /app/storage
    final String correctVaultPath =
        "$storedPath${Platform.pathSeparator}vault_files";

    if (mounted) {
      setState(() {
        _vaultPath = correctVaultPath;
        _publicUrl = storedUrl;
      });
      await _refreshFiles();
    }
  }

  Future<void> _refreshFiles() async {
    if (_vaultPath == null) return;

    final dir = Directory(_vaultPath!);

    // Auto-create if missing (e.g. first run)
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    try {
      final List<FileSystemEntity> entities = dir.listSync(
        recursive: false,
      ); // recursive: false is safer for flat vaults
      final List<File> files = entities.whereType<File>().toList();

      files.sort(
        (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
      );

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
      print("Error reading vault: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _handleShare(VaultFile file) {
    if (_publicUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Public URL not configured. Check Settings."),
        ),
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
            title: Text(
              "Share: ${file.fileName}",
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
            content: SizedBox(
              width: 400,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // --- PUBLIC / PRIVATE TOGGLE ---
                    SwitchListTile(
                      title: const Text(
                        "Make Public link",
                        style: TextStyle(color: Colors.white),
                      ),
                      subtitle: Text(
                        isPublic
                            ? "Anyone with the link can view"
                            : "Only allowed emails with token",
                        style: TextStyle(color: Colors.grey[400], fontSize: 12),
                      ),
                      activeColor: Colors.cyanAccent,
                      value: isPublic,
                      onChanged: (val) {
                        setStateBuilder(() {
                          isPublic = val;
                          generatedLink = null; // Reset link if settings change
                        });
                      },
                    ),
                    const Divider(color: Colors.grey),

                    // --- RESTRICTED EMAILS INPUT ---
                    if (!isPublic) ...[
                      const Text(
                        "Allowed Emails (comma separated)",
                        style: TextStyle(color: Colors.white, fontSize: 12),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: emailsController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: "user1@mail.com, user2@mail.com",
                          hintStyle: TextStyle(color: Colors.grey[600]),
                          filled: true,
                          fillColor: const Color(0xFF0F172A),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // --- EXPIRATION DATE ---
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          selectedExpiration == null
                              ? "No Expiration Date"
                              : "Expires: ${selectedExpiration!.toLocal().toString().split(' ')[0]}",
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 12,
                          ),
                        ),
                        TextButton.icon(
                          icon: const Icon(
                            Icons.calendar_today,
                            size: 14,
                            color: Colors.cyanAccent,
                          ),
                          label: const Text(
                            "Set Date",
                            style: TextStyle(color: Colors.cyanAccent),
                          ),
                          onPressed: () async {
                            final date = await showDatePicker(
                              context: context,
                              initialDate: DateTime.now().add(
                                const Duration(days: 7),
                              ),
                              firstDate: DateTime.now(),
                              lastDate: DateTime.now().add(
                                const Duration(days: 365),
                              ),
                            );
                            if (date != null) {
                              setStateBuilder(() => selectedExpiration = date);
                            }
                          },
                        ),
                      ],
                    ),

                    // --- GENERATED LINK VIEW ---
                    if (generatedLink != null) ...[
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.black26,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: SelectableText(
                          generatedLink!,
                          style: const TextStyle(
                            color: Colors.cyanAccent,
                            fontFamily: 'Courier',
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  "Close",
                  style: TextStyle(color: Colors.grey),
                ),
              ),

              // --- ACTION BUTTON (Generate or Copy) ---
              if (generatedLink == null)
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.cyanAccent,
                    foregroundColor: Colors.black,
                  ),
                  onPressed: isGenerating
                      ? null
                      : () async {
                          setStateBuilder(() => isGenerating = true);

                          try {
                            // Process emails
                            List<String> emails = emailsController.text
                                .split(',')
                                .map((e) => e.trim())
                                .where((e) => e.isNotEmpty)
                                .toList();

                            // Save to Postgres
                            final token = await PostgresService()
                                .createShareSettings(
                                  fileName: file.fileName!,
                                  isPublic: isPublic,
                                  emails: emails,
                                  expiresAt: selectedExpiration,
                                );

                            // Build the URL
                            final safeName = Uri.encodeComponent(
                              file.fileName!,
                            );
                            String link =
                                "https://$_publicUrl/vault/files/$safeName";
                            if (!isPublic && token != null) {
                              link += "?token=$token";
                            }

                            setStateBuilder(() {
                              generatedLink = link;
                              isGenerating = false;
                            });
                          } catch (e) {
                            setStateBuilder(() => isGenerating = false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text("Error: $e")),
                            );
                          }
                        },
                  child: isGenerating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text("Generate Link"),
                )
              else
                ElevatedButton.icon(
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text("Copy Link"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.cyanAccent,
                    foregroundColor: Colors.black,
                  ),
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: generatedLink!),
                    );
                    if (context.mounted) Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Link copied to clipboard!"),
                      ),
                    );
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
      } else if (Platform.isMacOS)
        await Process.run('open', [path]);
      else if (Platform.isWindows)
        await Process.run('explorer', [path]);
    } catch (e) {
      print("Could not open file: $e");
    }
  }

  String _getMimeType(String? path) {
    if (path == null) return 'application/octet-stream';
    final ext = path.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'pdf':
        return 'application/pdf';
      case 'mp4':
        return 'video/mp4';
      default:
        return 'application/octet-stream';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text("Local Vault"),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_open),
            tooltip: "Open in File Manager",
            onPressed: () {
              if (_vaultPath != null) _openFile(_vaultPath);
            },
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refreshFiles),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _files.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    "Vault is Empty",
                    style: TextStyle(color: Colors.grey, fontSize: 18),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    "Folder: $_vaultPath",
                    style: TextStyle(
                      color: Colors.grey[700],
                      fontFamily: 'Courier',
                    ),
                  ),
                ],
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(24),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 6,
                childAspectRatio: 0.85,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
              ),
              itemCount: _files.length,
              itemBuilder: (context, index) => _buildFileCard(_files[index]),
            ),
    );
  }

  Widget _buildFileCard(VaultFile file) {
    final fType = (file.fileType ?? "").toLowerCase();
    final bool isImg = ['jpg', 'jpeg', 'png', 'webp'].contains(fType);
    final safePath = file.filePath ?? "";

    return InkWell(
      onTap: () => _openFile(safePath),
      onLongPress: () => _handleShare(file),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: Column(
          children: [
            Expanded(
              child: isImg && safePath.isNotEmpty
                  ? Image.file(File(safePath), fit: BoxFit.cover)
                  : Icon(
                      _getFileIcon(fType),
                      size: 40,
                      color: Colors.cyanAccent,
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.fileName ?? "Unknown",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
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
      case 'pdf':
        return LucideIcons.fileText;
      case 'mp4':
        return LucideIcons.video;
      case 'zip':
        return LucideIcons.archive;
      default:
        return LucideIcons.file;
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
