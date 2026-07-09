import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:guptik_desktop/models/mediaplayer/player_video_model.dart';
import 'package:guptik_desktop/services/external/docker_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:path/path.dart' as p;
import 'package:video_thumbnail/video_thumbnail.dart'; 
import 'package:path_provider/path_provider.dart'; 
import '../../services/mediaplayer/player_upload_service.dart';

class DesktopUploadScreen extends StatefulWidget {
  final PlayerVideo? videoToEdit;
  const DesktopUploadScreen({super.key, this.videoToEdit});

  @override
  State<DesktopUploadScreen> createState() => _DesktopUploadScreenState();
}

class _DesktopUploadScreenState extends State<DesktopUploadScreen> {
  final TextEditingController _channelNameController = TextEditingController(); 
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descController = TextEditingController();
  final TextEditingController _tagsController = TextEditingController();
  
  bool _isPublishing = false;
  String _selectedVaultFile = "No file selected";
  String? _selectedFilePath;
  String _selectedCategory = 'Entertainment';
  final List<String> _categories = ['Entertainment', 'Tech', 'Education', 'Gaming', 'Music', 'Vlog', 'News'];
  String _selectedVisibility = 'public';
  bool _isReel = false;
  bool _isMonetized = false;

  @override
  void initState() {
    super.initState();
    if (widget.videoToEdit != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        
        setState(() {
          _channelNameController.text = widget.videoToEdit!.channelName;
          _titleController.text = widget.videoToEdit!.title;
          _descController.text = widget.videoToEdit!.description;
          _selectedVisibility = _getValidVisibility(widget.videoToEdit!.visibility);
          _isReel = widget.videoToEdit!.isReel;
          _selectedVaultFile = widget.videoToEdit!.filePath.split('/').last;
          _selectedFilePath = widget.videoToEdit!.filePath;
        });
        
        debugPrint("🚀 FETCH SUCCESS: Loaded ${widget.videoToEdit!.title}");
      });
    } else {
      _fetchExistingChannelName();
    }
  }

  String _getValidVisibility(String val) {
    List<String> allowed = ['public', 'unlisted', 'private'];
    String normalized = val.toLowerCase();
    return allowed.contains(normalized) ? normalized : 'public';
  }

  @override
  void dispose() {
    _channelNameController.dispose();
    _titleController.dispose();
    _descController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  Future<void> _fetchExistingChannelName() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      final response = await Supabase.instance.client.from('mp_channels').select('channel_name').eq('owner_uid', user.id).maybeSingle();
      if (response != null && mounted) {
        setState(() => _channelNameController.text = response['channel_name']);
      }
    }
  }

  Future<void> _pickFromVault() async {
    const secureStorage = FlutterSecureStorage();
    String defaultRoot = Platform.isWindows ? 'C:\\GuptikVault' : '${Platform.environment['HOME']}/GuptikVault';
    String? vaultPath = await secureStorage.read(key: 'vault_path') ?? defaultRoot;
    
    String targetDir = p.join(vaultPath, 'vault_files');
    if (!await Directory(targetDir).exists()) {
      await Directory(targetDir).create(recursive: true);
    }

    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.video, 
      allowMultiple: false,
      initialDirectory: targetDir,
    );

    if (result != null && result.files.single.path != null) {
      setState(() {
        _selectedVaultFile = result.files.single.name;
        _selectedFilePath = result.files.single.path;
      });
    }
  }
    
  Future<void> _setupNodeFolder() async {
    try {
      String defaultPath = Platform.isWindows ? 'C:\\GuptikVault' : '${Platform.environment['HOME']}/GuptikVault';
      final prefs = await SharedPreferences.getInstance();
      final String finalVaultPath = prefs.getString('vault_path') ?? defaultPath;

      const secureStorage = FlutterSecureStorage();
      await secureStorage.write(key: 'vault_path', value: finalVaultPath);

      final String activeTunnelUrl = await DockerService().getActiveTunnelUrl(); 
      await secureStorage.write(key: 'public_url', value: activeTunnelUrl);

       final user = Supabase.instance.client.auth.currentUser;
       if (user != null) {
         await Supabase.instance.client.from('mp_channels').upsert({
           'channel_id': user.id,
           'owner_uid': user.id,
           'channel_name': _channelNameController.text.isNotEmpty ? _channelNameController.text : "My Channel",
           'tunnel_url': activeTunnelUrl, 
         }, onConflict: 'channel_id');
       }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Node Registered: $activeTunnelUrl'), backgroundColor: Colors.green),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to setup node: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  Future<void> _handlePublish() async {
    if (_titleController.text.isEmpty || _selectedFilePath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please provide a title and select a video.'), backgroundColor: Colors.redAccent),
      );
      return;
    }

    setState(() => _isPublishing = true);

    const secureStorage = FlutterSecureStorage();
    String? vaultPath = await secureStorage.read(key: 'vault_path');

    if (vaultPath == null) {
      setState(() => _isPublishing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please click "Configure Node" first.'), backgroundColor: Colors.orange),
      );
      return;
    }

    File originalFile = File(_selectedFilePath!);
    String finalVaultPath;

    if (p.isWithin(vaultPath, originalFile.path)) {
      finalVaultPath = originalFile.path;
    } else {
      String extension = p.extension(originalFile.path); 
      String newFileName = '${const Uuid().v4()}$extension'; 
      Directory targetDir = Directory(p.join(vaultPath, 'vault_files'));
      if (!await targetDir.exists()) await targetDir.create(recursive: true);
      finalVaultPath = p.join(targetDir.path, newFileName);
      await originalFile.copy(finalVaultPath);
    }

    try {
      final tempDir = await getTemporaryDirectory();
      final generatedThumbPath = await VideoThumbnail.thumbnailFile(
        video: finalVaultPath,
        thumbnailPath: tempDir.path,
        imageFormat: ImageFormat.JPEG,
        maxHeight: 720, 
        quality: 85,
      );
      
      if (generatedThumbPath != null) {
        String baseName = p.basenameWithoutExtension(finalVaultPath);
        String finalThumbPath = p.join(p.dirname(finalVaultPath), '$baseName.jpg');
        File(generatedThumbPath).copySync(finalThumbPath);
      }
    } catch (e) {
      debugPrint('⚠️ Thumbnail generation failed: $e');
    }

    List<String> tags = _tagsController.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

    final success = await PlayerUploadService().publishVideo(
      title: _titleController.text.trim(),
      description: _descController.text.trim(),
      realLocalFilePath: finalVaultPath, 
      tags: tags, 
      category: _selectedCategory,
      visibility: _selectedVisibility,
      isReel: _isReel,
      isMonetized: _isMonetized,
      channelName: _channelNameController.text.trim(), 
    );

    if (mounted) {
      setState(() => _isPublishing = false);
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Video Published Successfully!'), backgroundColor: Colors.green),
        );
        Navigator.pop(context); 
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to publish video.'), backgroundColor: Colors.redAccent),
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
        title: const Text("Creator Studio", style: TextStyle(color: Colors.white, fontSize: 16)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: TextButton.icon(
              onPressed: _setupNodeFolder,
              icon: const Icon(Icons.dns, color: Color(0xFFD4AF37), size: 18),
              label: const Text("Configure Node", style: TextStyle(color: Color(0xFFD4AF37), fontWeight: FontWeight.bold)),
              style: TextButton.styleFrom(
                backgroundColor: const Color(0xFF0F172A),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.videoToEdit != null ? "Edit Video Details" : "Upload to Node", style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text("Publish directly from your Vault to the decentralized network.", style: TextStyle(color: Colors.grey.shade400, fontSize: 16)),
            const SizedBox(height: 40),

            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white12)),
              child: Row(
                children: [
                  const Icon(Icons.video_file, color: Color(0xFFD4AF37), size: 40),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Selected Video", style: TextStyle(color: Colors.white70, fontSize: 12)),
                        Text(_selectedVaultFile, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _pickFromVault,
                    icon: const Icon(Icons.folder, color: Colors.black),
                    label: const Text("Browse Files", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD4AF37)),
                  )
                ],
              ),
            ),
            const SizedBox(height: 32),

            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: Column(
                    children: [
                      _buildTextField("Your Channel Name", _channelNameController, maxLines: 1),
                      const SizedBox(height: 20),
                      _buildTextField("Video Title", _titleController, maxLines: 1),
                      const SizedBox(height: 20),
                      _buildTextField("Description", _descController, maxLines: 4),
                      const SizedBox(height: 20),
                      _buildTextField("Tags (comma separated)", _tagsController, maxLines: 1, hint: "e.g., tech, privacy"),
                    ],
                  ),
                ),
                const SizedBox(width: 40),
                Expanded(
                  flex: 1,
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white12)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Settings", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 20),
                        _buildDropdown("Category", _selectedCategory, _categories, (val) => setState(() => _selectedCategory = val!)),
                        const SizedBox(height: 20),
                        _buildDropdown("Visibility", _selectedVisibility, ['public', 'unlisted', 'private'], (val) => setState(() => _selectedVisibility = val!)),
                        const SizedBox(height: 20),
                        SwitchListTile(
                          title: const Text("Publish as Reel/Short", style: TextStyle(color: Colors.white70)),
                          activeThumbColor: const Color(0xFFD4AF37),
                          contentPadding: EdgeInsets.zero,
                          value: _isReel,
                          onChanged: (val) => setState(() => _isReel = val),
                        ),
                        SwitchListTile(
                          title: const Text("Enable Monetization", style: TextStyle(color: Colors.white70)),
                          activeThumbColor: const Color(0xFFD4AF37),
                          contentPadding: EdgeInsets.zero,
                          value: _isMonetized,
                          onChanged: (val) => setState(() => _isMonetized = val),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _isPublishing ? null : _handlePublish,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD4AF37),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isPublishing 
                  ? const CircularProgressIndicator(color: Colors.black)
                  : Text(widget.videoToEdit != null ? "Save Changes" : "Publish to Network", style: const TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, {int maxLines = 1, String? hint}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          maxLines: maxLines,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey.shade600),
            filled: true,
            fillColor: const Color(0xFF1E293B),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFD4AF37))),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdown(String label, String currentValue, List<String> items, ValueChanged<String?> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(8)),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: currentValue,
              isExpanded: true,
              dropdownColor: const Color(0xFF1E293B),
              style: const TextStyle(color: Colors.white),
              items: items.map((String value) => DropdownMenuItem<String>(value: value, child: Text(value))).toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}