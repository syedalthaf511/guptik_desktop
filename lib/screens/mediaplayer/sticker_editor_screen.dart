import 'package:flutter/material.dart';
import '../../models/mediaplayer/video_sticker_model.dart';
import '../../services/mediaplayer/player_monetization_service.dart';

/// StickerEditorScreen — In-video product/service placement editor.
/// Allows creators to add, position, and manage clickable product stickers
/// that appear at specific timestamps during video playback.
class StickerEditorScreen extends StatefulWidget {
  final String channelId;

  const StickerEditorScreen({super.key, required this.channelId});

  @override
  State<StickerEditorScreen> createState() => _StickerEditorScreenState();
}

class _StickerEditorScreenState extends State<StickerEditorScreen> {
  final PlayerMonetizationService _service = PlayerMonetizationService();
  final TextEditingController _videoIdController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _timestampController = TextEditingController();
  final TextEditingController _descController = TextEditingController();
  final TextEditingController _linkController = TextEditingController();

  List<VideoSticker> _stickers = [];
  bool _isLoading = false;
  String _stickerType = 'product';

  @override
  void dispose() {
    _videoIdController.dispose();
    _nameController.dispose();
    _priceController.dispose();
    _timestampController.dispose();
    _descController.dispose();
    _linkController.dispose();
    super.dispose();
  }

  Future<void> _loadStickers() async {
    if (_videoIdController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Enter a video ID to load stickers.'),
            backgroundColor: Colors.orange),
      );
      return;
    }
    setState(() => _isLoading = true);
    final stickers =
        await _service.fetchStickers(_videoIdController.text.trim());
    if (mounted) {
      setState(() {
        _stickers = stickers;
        _isLoading = false;
      });
    }
  }

  Future<void> _addSticker() async {
    if (_nameController.text.trim().isEmpty ||
        _videoIdController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please enter video ID and sticker name.'),
            backgroundColor: Colors.redAccent),
      );
      return;
    }

    final ts = double.tryParse(_timestampController.text.trim()) ?? 0.0;
    final price = double.tryParse(_priceController.text.trim());

    String? stickerId;
    if (_stickerType == 'product') {
      stickerId = await _service.addProductSticker(
        videoId: _videoIdController.text.trim(),
        productName: _nameController.text.trim(),
        timestampInVideo: ts,
        price: price,
        description: _descController.text.trim(),
        linkUrl: _linkController.text.trim().isNotEmpty
            ? _linkController.text.trim()
            : null,
      );
    } else {
      stickerId = await _service.addServiceSticker(
        videoId: _videoIdController.text.trim(),
        serviceName: _nameController.text.trim(),
        timestampInVideo: ts,
        price: price,
        description: _descController.text.trim(),
      );
    }

    if (stickerId != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('$_stickerType sticker added successfully!'),
            backgroundColor: Colors.green),
      );
      _nameController.clear();
      _priceController.clear();
      _timestampController.clear();
      _descController.clear();
      _linkController.clear();
      _loadStickers();
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Failed to add sticker.'),
            backgroundColor: Colors.redAccent),
      );
    }
  }

  Future<void> _removeSticker(VideoSticker sticker) async {
    final success =
        await _service.removeSticker(sticker.stickerId, sticker.stickerType);
    if (success && mounted) {
      setState(() {
        _stickers.removeWhere((s) => s.stickerId == sticker.stickerId);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Sticker removed.'),
            backgroundColor: Colors.orange),
      );
    }
  }

  String _formatTimestamp(double seconds) {
    final mins = (seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds % 60).toStringAsFixed(0).padLeft(2, '0');
    return '$mins:$secs';
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('In-Video Sticker Editor',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text(
              'Add clickable product/service placements that appear at specific timestamps in your videos.',
              style: TextStyle(color: Colors.grey, fontSize: 14)),
          const SizedBox(height: 24),

          // Video ID input + load button
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _videoIdController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Video ID',
                    labelStyle: TextStyle(color: Colors.grey),
                    filled: true,
                    fillColor: Color(0xFF1E293B),
                    border: OutlineInputBorder(borderSide: BorderSide.none),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00E5FF),
                  foregroundColor: Colors.black,
                ),
                onPressed: _isLoading ? null : _loadStickers,
                icon: _isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh, size: 18),
                label: const Text('Load Stickers'),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Sticker type toggle
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Add New Sticker',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                // Type toggle
                Row(
                  children: [
                    ChoiceChip(
                      label: const Text('Product'),
                      selected: _stickerType == 'product',
                      selectedColor: const Color(0xFF00E5FF),
                      onSelected: (val) =>
                          setState(() => _stickerType = 'product'),
                    ),
                    const SizedBox(width: 12),
                    ChoiceChip(
                      label: const Text('Service'),
                      selected: _stickerType == 'service',
                      selectedColor: const Color(0xFF00E5FF),
                      onSelected: (val) =>
                          setState(() => _stickerType = 'service'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Name
                TextField(
                  controller: _nameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: _stickerType == 'product'
                        ? 'Product Name'
                        : 'Service Name',
                    labelStyle: const TextStyle(color: Colors.grey),
                    filled: true,
                    fillColor: const Color(0xFF0F172A),
                    border: const OutlineInputBorder(borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 12),
                // Timestamp + Price
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _timestampController,
                        style: const TextStyle(color: Colors.white),
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Timestamp (seconds)',
                          labelStyle: TextStyle(color: Colors.grey),
                          filled: true,
                          fillColor: Color(0xFF0F172A),
                          border: OutlineInputBorder(borderSide: BorderSide.none),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _priceController,
                        style: const TextStyle(color: Colors.white),
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Price (USD)',
                          labelStyle: TextStyle(color: Colors.grey),
                          filled: true,
                          fillColor: Color(0xFF0F172A),
                          border: OutlineInputBorder(borderSide: BorderSide.none),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Link (products only)
                if (_stickerType == 'product') ...[
                  TextField(
                    controller: _linkController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Product Link URL (optional)',
                      labelStyle: TextStyle(color: Colors.grey),
                      filled: true,
                      fillColor: Color(0xFF0F172A),
                      border: OutlineInputBorder(borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                // Description
                TextField(
                  controller: _descController,
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
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00E5FF),
                      foregroundColor: Colors.black,
                    ),
                    onPressed: _addSticker,
                    icon: const Icon(Icons.add_shopping_cart, size: 18),
                    label: const Text('Add Sticker',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),

          // Existing stickers list
          if (_stickers.isNotEmpty) ...[
            const Text('Active Stickers',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ..._stickers.map((sticker) => Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        sticker.stickerType == 'product'
                            ? Icons.shopping_bag
                            : Icons.handshake,
                        color: const Color(0xFF00E5FF),
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(sticker.name,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500)),
                            const SizedBox(height: 4),
                            Text(
                              '${_formatTimestamp(sticker.timestampInVideo)} • ${sticker.stickerType} • ${sticker.clickCount} clicks • ${sticker.conversionRate.toStringAsFixed(1)}% conversion',
                              style: TextStyle(
                                  color: Colors.grey.shade400, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      if (sticker.price != null)
                        Text('\$${sticker.price!.toStringAsFixed(2)}',
                            style: const TextStyle(
                                color: Colors.green,
                                fontSize: 16,
                                fontWeight: FontWeight.bold)),
                      const SizedBox(width: 12),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.redAccent, size: 18),
                        onPressed: () => _removeSticker(sticker),
                      ),
                    ],
                  ),
                )),
          ] else if (!_isLoading && _videoIdController.text.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Text('No active stickers for this video.',
                    style: TextStyle(color: Colors.grey, fontSize: 14)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}