import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import '../../models/mediaplayer/video_sticker_model.dart';
import '../../services/mediaplayer/player_monetization_service.dart';
import '../../services/mediaplayer/player_api_service.dart';

/// StickerOverlay — Renders shoppable product stickers on top of the video
/// (YouTube/IG-style). Stickers appear at their [VideoSticker.timestampInVideo]
/// "show timing" and stay for [VideoSticker.durationOnScreen] seconds. Tapping a
/// sticker logs a click and opens the product link.
class StickerOverlay extends StatefulWidget {
  final Player player;
  final String videoId;
  /// The creator's gateway/tunnel URL. Stickers are fetched from the CREATOR's
  /// node (not the viewer's local DB) so a sticker added by user A is visible
  /// to user B — exactly like comments/likes. Pass null to fall back to the
  /// viewer's own local node (e.g. when watching your own video).
  final String? creatorUrl;

  const StickerOverlay({
    super.key,
    required this.player,
    required this.videoId,
    this.creatorUrl,
  });

  @override
  State<StickerOverlay> createState() => _StickerOverlayState();
}

class _StickerOverlayState extends State<StickerOverlay> {
  final PlayerMonetizationService _service = PlayerMonetizationService();
  List<VideoSticker> _stickers = [];
  VideoSticker? _activeSticker;
  bool _loading = true;
  StreamSubscription<Duration>? _positionSub;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _loadStickers();
    _positionSub = widget.player.stream.position.listen(_onPosition);
  }

  Future<void> _loadStickers() async {
    List<VideoSticker> stickers;
    if (widget.creatorUrl != null && widget.creatorUrl!.isNotEmpty) {
      // 🚀 Cross-user: fetch from the CREATOR's gateway node so any viewer sees
      // the stickers (this is what makes A's stickers appear for B).
      final api = PlayerApiService(gatewayUrl: widget.creatorUrl);
      stickers = await api.fetchStickers(widget.videoId);
    } else {
      // Fallback: viewer is the creator — read from their own local node.
      stickers = await _service.fetchStickers(widget.videoId);
    }
    if (mounted) {
      setState(() {
        _stickers = stickers;
        _loading = false;
      });
    }
  }

  void _onPosition(Duration position) {
    if (!mounted) return;
    final secs = position.inSeconds.toDouble();

    // Find a sticker whose show window contains the current time.
    VideoSticker? match;
    for (final s in _stickers) {
      final start = s.timestampInVideo;
      final end = s.timestampInVideo + s.durationOnScreen;
      if (secs >= start && secs <= end) {
        match = s;
        break;
      }
    }

    if (match != _activeSticker) {
      _hideTimer?.cancel();
      setState(() => _activeSticker = match);
    }
  }

  void _onStickerTap(VideoSticker sticker) {
    // Log the click for analytics.
    _service.logStickerClick(
      sticker.productId.isNotEmpty ? sticker.productId : sticker.id,
      sticker.stickerType,
    );

    // Tapping the sticker shows the product detail sheet (image, title,
    // description, price). The sheet's "View" button then navigates to the
    // product link — matching the requested two-step shoppable UX.
    _showProductSheet(sticker);
  }

  void _showProductSheet(VideoSticker sticker) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _ProductSheet(sticker: sticker),
    );
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _hideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _activeSticker == null) {
      return const SizedBox.shrink();
    }

    final sticker = _activeSticker!;
    final zone = sticker.clickableZone ??
        const ClickableZone(x: 0.68, y: 0.08, width: 0.3, height: 0.34);

    // Position the sticker using the ACTUAL video box size (via
    // LayoutBuilder) rather than the full screen, so it lands inside the
    // video frame at the normalized (x, y) coordinates.
    return LayoutBuilder(
      builder: (context, constraints) {
        final boxW = constraints.maxWidth;
        final boxH = constraints.maxHeight;
        // Keep the card inside the box even if the zone is near an edge.
        final left = (zone.x * boxW).clamp(8.0, boxW - 230);
        final top = (zone.y * boxH).clamp(8.0, boxH - 90);
        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              left: left,
              top: top,
              child: _StickerCard(
                sticker: sticker,
                onTap: () => _onStickerTap(sticker),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Extracts a short, human-readable domain from a product link so it can be
/// shown on the in-video sticker card (e.g. "amazon.in" from a long URL).
String _linkDomain(String url) {
  try {
    final uri = Uri.parse(url);
    final host = uri.host.replaceFirst(RegExp(r'^www\.'), '');
    return host.isEmpty ? url : host;
  } catch (_) {
    return url;
  }
}

/// Opens a URL in the OS default handler (same approach as the secure chats
/// screen — no extra package needed). Works on Windows/macOS/Linux.
void _launchUrl(String url) {
  try {
    if (Platform.isWindows) {
      Process.run('rundll32', ['url.dll,FileProtocolHandler', url]);
    } else if (Platform.isMacOS) {
      Process.run('open', [url]);
    } else {
      Process.run('xdg-open', [url]);
    }
  } catch (e) {
    debugPrint('Could not open sticker link: $e');
  }
}

/// Renders the sticker image from either a network URL or a local file path
/// (the editor saves bg-removed images to a local temp file). Uses
/// [BoxFit.contain] so the full product image is always visible (no cropping).
Widget _stickerImage(String? path, double size) {
  final fallback = Icon(Icons.shopping_bag, color: const Color(0xFF00E5FF), size: size * 0.5);
  if (path == null || path.isEmpty) return fallback;
  final isNetwork = path.startsWith('http://') || path.startsWith('https://');
  final img = isNetwork
      ? Image.network(path, fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => fallback)
      : Image.file(File(path), fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => fallback);
  return ClipRRect(
    borderRadius: BorderRadius.circular(10),
    child: SizedBox(width: size, height: size, child: img),
  );
}

/// The compact product card shown over the video: just the product image
/// and a "View Product" button (tapping opens the full detail popup).
class _StickerCard extends StatelessWidget {
  final VideoSticker sticker;
  final VoidCallback onTap;

  const _StickerCard({required this.sticker, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 132,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black.withAlpha(205),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFF00E5FF).withAlpha(150),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(130),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Product image (bg already removed upstream)
              Container(
                width: 116,
                height: 116,
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: _stickerImage(sticker.imagePath, 116),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 34,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00E5FF),
                    foregroundColor: Colors.black,
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: onTap,
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.shopping_bag, size: 15),
                      SizedBox(width: 5),
                      Flexible(
                        child: Text('View Product',
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            style: TextStyle(
                                fontSize: 12.5, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Beautiful product detail popup (IG shopping style) shown when the viewer
/// taps "View Product" on the in-video sticker. Shows the image, title,
/// description, MRP, sale price, and a "View" CTA that opens the link.
class _ProductSheet extends StatelessWidget {
  final VideoSticker sticker;

  const _ProductSheet({required this.sticker});

  @override
  Widget build(BuildContext context) {
    final hasLink =
        sticker.linkUrl != null && sticker.linkUrl!.isNotEmpty;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      // Scrollable so the sheet never overflows on short screens.
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Hero image
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Container(
                width: double.infinity,
                height: 200,
                color: Colors.white10,
                child: _stickerImage(sticker.imagePath, 200),
              ),
            ),
            const SizedBox(height: 16),
            // Title + discount badge
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    sticker.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      height: 1.2,
                    ),
                  ),
                ),
                if (sticker.discountPercent > 0)
                  Container(
                    margin: const EdgeInsets.only(left: 10, top: 2),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.greenAccent.withAlpha(30),
                      borderRadius: BorderRadius.circular(20),
                      border:
                          Border.all(color: Colors.greenAccent, width: 1),
                    ),
                    child: Text(
                      '${sticker.discountPercent.toStringAsFixed(0)}% OFF',
                      style: const TextStyle(
                        color: Colors.greenAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            // Price row: sale price + MRP strikethrough
            Row(
              children: [
                Text(
                  sticker.formattedSalePrice,
                  style: const TextStyle(
                    color: Color(0xFF00E5FF),
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (sticker.discountPercent > 0) ...[
                  const SizedBox(width: 10),
                  Text(
                    sticker.formattedMrp,
                    style: const TextStyle(
                      color: Colors.grey,
                      fontSize: 16,
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 14),
            // Description
            Text(
              sticker.description.isNotEmpty
                  ? sticker.description
                  : 'No description provided.',
              style: const TextStyle(
                  color: Colors.white70, fontSize: 14, height: 1.6),
            ),
            const SizedBox(height: 16),
            // Link domain chip (so the viewer sees where "View" goes)
            if (hasLink)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF00E5FF).withAlpha(18),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: const Color(0xFF00E5FF).withAlpha(80)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.link,
                        color: Color(0xFF00E5FF), size: 16),
                    const SizedBox(width: 8),
                    Text(
                      _linkDomain(sticker.linkUrl!),
                      style: const TextStyle(
                        color: Color(0xFF00E5FF),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 20),
            // "View" CTA → opens the product link
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00E5FF),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 6,
                  shadowColor: const Color(0xFF00E5FF).withAlpha(120),
                ),
                icon: const Icon(Icons.open_in_new, size: 20),
                label: const Text(
                  'View',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                onPressed: () {
                  Navigator.pop(context);
                  if (hasLink) _launchUrl(sticker.linkUrl!);
                },
              ),
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }
}
