import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../services/mediaplayer/player_monetization_service.dart';
import '../../utils/mediaplayer/background_remover.dart';

/// StickerEditorScreen — Creator-facing editor for in-video shoppable stickers.
///
/// Lets a creator add a product sticker with: title, description, MRP, sale
/// price, show timing (timestamp in video), link URL, and image. The image can
/// be run through the background remover so it composites cleanly over video
/// (YouTube/IG-style). Stickers are persisted via [PlayerMonetizationService].
class StickerEditorScreen extends StatefulWidget {
  final String channelId;
  final String? videoId;

  const StickerEditorScreen({
    super.key,
    required this.channelId,
    this.videoId,
  });

  @override
  State<StickerEditorScreen> createState() => _StickerEditorScreenState();
}

class _StickerEditorScreenState extends State<StickerEditorScreen> {
  final PlayerMonetizationService _service = PlayerMonetizationService();

  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  final _mrpController = TextEditingController();
  final _saleController = TextEditingController();
  final _linkController = TextEditingController();
  final _timingController = TextEditingController(text: '0');
  final _durationController = TextEditingController(text: '8');

  File? _pickedImage;
  Uint8List? _processedImageBytes; // after bg removal
  bool _bgRemoved = false;
  bool _isSaving = false;
  String _currency = 'USD';

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _mrpController.dispose();
    _saleController.dispose();
    _linkController.dispose();
    _timingController.dispose();
    _durationController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
    );
    if (result != null && result.files.single.path != null) {
      final file = File(result.files.single.path!);
      final bytes = await file.readAsBytes();
      setState(() {
        _pickedImage = file;
        _processedImageBytes = bytes;
        _bgRemoved = false;
      });
    }
  }

  /// Runs the background remover on the picked image (white backdrop removal).
  Future<void> _removeBackground() async {
    if (_pickedImage == null) return;
    final bytes = await _pickedImage!.readAsBytes();
    final out = BackgroundRemover.removeColorFromBytes(
      bytes,
      target: const Color(0xFFFFFFFF),
      tolerance: 70,
    );
    setState(() {
      _processedImageBytes = out;
      _bgRemoved = true;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Background removed — sticker is now transparent.'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _saveSticker() async {
    final title = _titleController.text.trim();
    final mrp = double.tryParse(_mrpController.text.trim()) ?? 0;
    final sale = double.tryParse(_saleController.text.trim()) ?? 0;
    final timing = double.tryParse(_timingController.text.trim()) ?? 0;
    final duration = double.tryParse(_durationController.text.trim()) ?? 8;

    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Title is required.'), backgroundColor: Colors.orange),
      );
      return;
    }
    if (widget.videoId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No video selected for this sticker.'), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() => _isSaving = true);

    // Upload the (optionally bg-removed) image to the SHARED store so that
    // ANY viewer (not just the creator) can see the sticker. We pass the raw
    // bytes; the service uploads them to Supabase Storage and stores the
    // public URL. Falls back to a local file path if no image was picked.
    Uint8List? imageBytes = _processedImageBytes;
    if (imageBytes == null && _pickedImage != null) {
      imageBytes = await _pickedImage!.readAsBytes();
    }

    final ok = await _service.addProductStickerShared(
      videoId: widget.videoId!,
      productName: title,
      timestampInVideo: timing,
      imageBytes: imageBytes,
      price: sale,
      currency: _currency,
      description: _descController.text.trim(),
      linkUrl: _linkController.text.trim().isEmpty
          ? null
          : _linkController.text.trim(),
      mrp: mrp,
      durationOnScreen: duration,
    );

    if (mounted) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok != null
              ? 'Sticker added! It will appear at ${timing}s in the video.'
              : 'Failed to add sticker.'),
          backgroundColor: ok != null ? Colors.green : Colors.redAccent,
        ),
      );
      if (ok != null) _resetForm();
    }
  }

  void _resetForm() {
    _titleController.clear();
    _descController.clear();
    _mrpController.clear();
    _saleController.clear();
    _linkController.clear();
    _timingController.text = '0';
    _durationController.text = '8';
    setState(() {
      _pickedImage = null;
      _processedImageBytes = null;
      _bgRemoved = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('In-Video Stickers',
                  style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF00E5FF).withAlpha(20),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF00E5FF).withAlpha(120)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.shopping_bag, color: Color(0xFF00E5FF), size: 16),
                    SizedBox(width: 6),
                    Text('Shoppable', style: TextStyle(color: Color(0xFF00E5FF), fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text('Add product stickers that appear over your video at a chosen time.',
              style: TextStyle(color: Colors.grey, fontSize: 14)),
          const SizedBox(height: 24),

          // Image picker + bg remover
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Sticker Image', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: _processedImageBytes != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.memory(_processedImageBytes!, fit: BoxFit.cover),
                            )
                          : const Center(
                              child: Icon(Icons.image, color: Colors.grey, size: 36),
                            ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF00E5FF),
                              foregroundColor: Colors.black,
                            ),
                            onPressed: _pickImage,
                            icon: const Icon(Icons.upload, size: 18),
                            label: const Text('Pick Image'),
                          ),
                          const SizedBox(height: 10),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _bgRemoved
                                  ? Colors.green
                                  : const Color(0xFF1E293B),
                              foregroundColor: _bgRemoved ? Colors.white : const Color(0xFF00E5FF),
                              side: const BorderSide(color: Color(0xFF00E5FF)),
                            ),
                            onPressed: _pickedImage == null ? null : _removeBackground,
                            icon: const Icon(Icons.auto_fix_high, size: 18),
                            label: Text(_bgRemoved ? 'Background Removed' : 'Remove Background'),
                          ),
                          if (_bgRemoved)
                            const Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: Text('Transparent PNG ready for video overlay.',
                                  style: TextStyle(color: Colors.greenAccent, fontSize: 12)),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Product fields
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              children: [
                _field('Product Title', _titleController, 'e.g. Wireless Earbuds'),
                const SizedBox(height: 16),
                _field('Description', _descController, 'Short product blurb…', maxLines: 3),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _field('MRP', _mrpController, '29.99',
                          keyboard: TextInputType.number),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _field('Sale Price', _saleController, '19.99',
                          keyboard: TextInputType.number),
                    ),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: 110,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Currency', style: TextStyle(color: Colors.grey, fontSize: 12)),
                          const SizedBox(height: 6),
                          DropdownButtonFormField<String>(
                            initialValue: _currency,
                            dropdownColor: const Color(0xFF0F172A),
                            decoration: const InputDecoration(
                              filled: true,
                              fillColor: Color(0xFF0F172A),
                              border: OutlineInputBorder(borderSide: BorderSide.none),
                            ),
                            style: const TextStyle(color: Colors.white),
                            items: const ['USD', 'EUR', 'GBP', 'INR']
                                .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                                .toList(),
                            onChanged: (v) => setState(() => _currency = v ?? 'USD'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _field('Product Link URL', _linkController, 'https://…'),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _field('Show Timing (sec)', _timingController, '0',
                          keyboard: TextInputType.number),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _field('Visible For (sec)', _durationController, '8',
                          keyboard: TextInputType.number),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00E5FF),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _isSaving ? null : _saveSticker,
              icon: _isSaving
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2),
                    )
                  : const Icon(Icons.add_shopping_cart, color: Colors.black),
              label: Text(_isSaving ? 'Saving…' : 'Add Sticker to Video',
                  style: const TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController controller, String hint,
      {int maxLines = 1, TextInputType keyboard = TextInputType.text}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboard,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.grey),
            filled: true,
            fillColor: const Color(0xFF0F172A),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF00E5FF)),
            ),
          ),
        ),
      ],
    );
  }
}