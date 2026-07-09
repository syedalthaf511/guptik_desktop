import 'dart:convert';

/// VideoSticker — In-video product/service placement model.
/// Maps to local Postgres `mp_sticker_products_catalog` and
/// `mp_sticker_services_catalog` tables for monetization.
class VideoSticker {
  final String stickerId;
  final String videoId;
  final String stickerType; // 'product' or 'service'
  final String name;
  final double timestampInVideo; // seconds
  final double? price;
  final String currency;
  final String description;
  final String? linkUrl;
  final String? imagePath;
  final String stockStatus; // 'in_stock', 'out_of_stock', 'limited'
  final int salesCount;
  final int clickCount;
  final int purchaseInitiatedCount;
  final int purchaseCompletedCount;
  final bool isActive;
  final ClickableZone? clickableZone;
  final String createdAt;
  final String updatedAt;

  VideoSticker({
    required this.stickerId,
    required this.videoId,
    required this.stickerType,
    required this.name,
    required this.timestampInVideo,
    this.price,
    this.currency = 'USD',
    this.description = '',
    this.linkUrl,
    this.imagePath,
    this.stockStatus = 'in_stock',
    this.salesCount = 0,
    this.clickCount = 0,
    this.purchaseInitiatedCount = 0,
    this.purchaseCompletedCount = 0,
    this.isActive = true,
    this.clickableZone,
    required this.createdAt,
    required this.updatedAt,
  });

  factory VideoSticker.fromJson(Map<String, dynamic> json) {
    ClickableZone? zone;
    final rawZone = json['clickable_zone'];
    if (rawZone is Map) {
      zone = ClickableZone.fromJson(Map<String, dynamic>.from(rawZone));
    } else if (rawZone is String && rawZone.isNotEmpty) {
      try {
        zone = ClickableZone.fromJson(
            Map<String, dynamic>.from(jsonDecode(rawZone)));
      } catch (_) {}
    }

    final isProduct = json['product_id'] != null;
    return VideoSticker(
      stickerId: json['product_id']?.toString() ??
          json['service_id']?.toString() ??
          json['id']?.toString() ??
          '',
      videoId: json['video_id']?.toString() ?? '',
      stickerType: isProduct ? 'product' : 'service',
      name: json['product_name']?.toString() ??
          json['service_name']?.toString() ??
          'Untitled',
      timestampInVideo: (json['timestamp_in_video'] ?? 0).toDouble(),
      price: json['price'] != null ? (json['price'] as num).toDouble() : null,
      currency: json['currency']?.toString() ?? 'USD',
      description: json['description']?.toString() ?? '',
      linkUrl: json['link_url']?.toString(),
      imagePath: json['image_path']?.toString(),
      stockStatus: json['stock_status']?.toString() ?? 'in_stock',
      salesCount: json['sales_count_local'] ?? 0,
      clickCount: json['click_count_local'] ?? 0,
      purchaseInitiatedCount: json['purchase_initiated_count'] ?? 0,
      purchaseCompletedCount: json['purchase_completed_count'] ?? 0,
      isActive: json['is_active'] ?? true,
      clickableZone: zone,
      createdAt: json['created_at']?.toString() ?? '',
      updatedAt: json['updated_at']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'product_id': stickerType == 'product' ? stickerId : null,
      'service_id': stickerType == 'service' ? stickerId : null,
      'video_id': videoId,
      'timestamp_in_video': timestampInVideo,
      'clickable_zone': clickableZone?.toJson(),
      'product_name': stickerType == 'product' ? name : null,
      'service_name': stickerType == 'service' ? name : null,
      'price': price,
      'currency': currency,
      'description': description,
      'link_url': linkUrl,
      'image_path': imagePath,
      'stock_status': stockStatus,
      'sales_count_local': salesCount,
      'click_count_local': clickCount,
      'purchase_initiated_count': purchaseInitiatedCount,
      'purchase_completed_count': purchaseCompletedCount,
      'is_active': isActive,
    };
  }

  /// Conversion rate for analytics (completed purchases / clicks)
  double get conversionRate =>
      clickCount > 0 ? (purchaseCompletedCount / clickCount) * 100 : 0.0;
}

/// ClickableZone — Defines the rectangular tappable area of a sticker
/// overlaid on the video, using normalized 0.0-1.0 coordinates.
class ClickableZone {
  final double x;
  final double y;
  final double width;
  final double height;

  ClickableZone({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  factory ClickableZone.fromJson(Map<String, dynamic> json) {
    return ClickableZone(
      x: (json['x'] ?? 0.0).toDouble(),
      y: (json['y'] ?? 0.0).toDouble(),
      width: (json['width'] ?? 0.1).toDouble(),
      height: (json['height'] ?? 0.1).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {'x': x, 'y': y, 'width': width, 'height': height};
  }
}