/// VideoSticker — In-video product/service sticker model used for monetization.
///
/// A sticker is a clickable product card that appears over a video at a
/// specific timestamp (show timing), links out to a product page, and shows
/// an image with MRP + sale price (YouTube/IG-style shoppable overlay).
class VideoSticker {
  final String id;
  final String videoId;
  final String productId;
  final String? serviceId;

  /// Timestamp (in seconds) inside the video when the sticker should appear.
  final double timestampInVideo;

  /// How long (in seconds) the sticker stays on screen after [timestampInVideo].
  final double durationOnScreen;

  final ClickableZone? clickableZone;

  // ── Product / service identity ────────────────────────────────────────────
  final String title; // product_name / service_name
  final String description;

  /// MRP (maximum retail price) — the struck-through original price.
  final double mrp;

  /// Sale price — the actual price the viewer pays (the "price" column).
  final double salePrice;

  final String currency;
  final String? linkUrl;
  final String? imagePath;

  // ── Analytics / status ────────────────────────────────────────────────────
  final String stockStatus; // in_stock / out_of_stock / low_stock
  final int salesCountLocal;
  final int clickCountLocal;
  final int purchaseInitiatedCount;
  final int purchaseCompletedCount;
  final bool isActive;
  final String createdAt;
  final String updatedAt;

  /// Distinguishes a product sticker from a service (booking) sticker.
  final String stickerType; // 'product' | 'service'

  const VideoSticker({
    required this.id,
    required this.videoId,
    this.productId = '',
    this.serviceId,
    this.timestampInVideo = 0,
    this.durationOnScreen = 8,
    this.clickableZone,
    this.title = 'Untitled',
    this.description = '',
    this.mrp = 0,
    this.salePrice = 0,
    this.currency = 'USD',
    this.linkUrl,
    this.imagePath,
    this.stockStatus = 'in_stock',
    this.salesCountLocal = 0,
    this.clickCountLocal = 0,
    this.purchaseInitiatedCount = 0,
    this.purchaseCompletedCount = 0,
    this.isActive = true,
    this.createdAt = '',
    this.updatedAt = '',
    this.stickerType = 'product',
  });

  /// Builds a [VideoSticker] from a JSON map (typically produced by
  /// [PlayerMonetizationService] when reading from Postgres).
  factory VideoSticker.fromJson(Map<String, dynamic> json) {
    final dynamic rawMrp = json['mrp'] ?? json['mrp_price'];
    final dynamic rawSale = json['sale_price'] ?? json['price'];
    return VideoSticker(
      id: json['id']?.toString() ?? '',
      videoId: json['video_id']?.toString() ?? '',
      productId: json['product_id']?.toString() ?? '',
      serviceId: json['service_id']?.toString(),
      timestampInVideo: _toDouble(json['timestamp_in_video'] ?? json['show_timing_start'] ?? 0),
      durationOnScreen: _toDouble(json['duration_on_screen'] ?? 8),
      clickableZone: json['clickable_zone'] != null
          ? ClickableZone.fromJson(json['clickable_zone'])
          : null,
      title: json['product_name']?.toString() ??
          json['service_name']?.toString() ??
          json['title']?.toString() ??
          'Untitled',
      description: json['description']?.toString() ?? '',
      mrp: _toDouble(rawMrp),
      salePrice: _toDouble(rawSale),
      currency: json['currency']?.toString() ?? 'USD',
      linkUrl: json['link_url']?.toString(),
      imagePath: json['image_path']?.toString(),
      stockStatus: json['stock_status']?.toString() ?? 'in_stock',
      salesCountLocal: _toInt(json['sales_count_local'] ?? json['sales_count'] ?? 0),
      clickCountLocal: _toInt(json['click_count_local'] ?? 0),
      purchaseInitiatedCount: _toInt(json['purchase_initiated_count'] ?? 0),
      purchaseCompletedCount: _toInt(json['purchase_completed_count'] ?? 0),
      isActive: json['is_active'] ?? true,
      createdAt: json['created_at']?.toString() ?? '',
      updatedAt: json['updated_at']?.toString() ?? '',
      stickerType: json['service_id'] != null ? 'service' : 'product',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'video_id': videoId,
        'product_id': productId,
        'service_id': serviceId,
        'timestamp_in_video': timestampInVideo,
        'duration_on_screen': durationOnScreen,
        'clickable_zone': clickableZone?.toJson(),
        'title': title,
        'description': description,
        'mrp': mrp,
        'sale_price': salePrice,
        'currency': currency,
        'link_url': linkUrl,
        'image_path': imagePath,
        'stock_status': stockStatus,
        'sales_count_local': salesCountLocal,
        'click_count_local': clickCountLocal,
        'purchase_initiated_count': purchaseInitiatedCount,
        'purchase_completed_count': purchaseCompletedCount,
        'is_active': isActive,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'sticker_type': stickerType,
      };

  /// Discount percentage off MRP (0 when MRP <= sale price or MRP == 0).
  double get discountPercent {
    if (mrp <= 0 || salePrice >= mrp) return 0;
    return ((mrp - salePrice) / mrp) * 100;
  }

  /// Formatted price label, e.g. "$19.99".
  String get formattedSalePrice => '$currencySymbol${salePrice.toStringAsFixed(2)}';

  /// Formatted MRP label, e.g. "$29.99".
  String get formattedMrp => '$currencySymbol${mrp.toStringAsFixed(2)}';

  String get currencySymbol {
    switch (currency.toUpperCase()) {
      case 'USD':
        return '\$';
      case 'EUR':
        return '€';
      case 'GBP':
        return '£';
      case 'INR':
        return '₹';
      default:
        return '';
    }
  }

  VideoSticker copyWith({
    String? id,
    String? videoId,
    String? productId,
    String? serviceId,
    double? timestampInVideo,
    double? durationOnScreen,
    ClickableZone? clickableZone,
    String? title,
    String? description,
    double? mrp,
    double? salePrice,
    String? currency,
    String? linkUrl,
    String? imagePath,
    String? stockStatus,
    int? salesCountLocal,
    int? clickCountLocal,
    int? purchaseInitiatedCount,
    int? purchaseCompletedCount,
    bool? isActive,
    String? createdAt,
    String? updatedAt,
    String? stickerType,
  }) {
    return VideoSticker(
      id: id ?? this.id,
      videoId: videoId ?? this.videoId,
      productId: productId ?? this.productId,
      serviceId: serviceId ?? this.serviceId,
      timestampInVideo: timestampInVideo ?? this.timestampInVideo,
      durationOnScreen: durationOnScreen ?? this.durationOnScreen,
      clickableZone: clickableZone ?? this.clickableZone,
      title: title ?? this.title,
      description: description ?? this.description,
      mrp: mrp ?? this.mrp,
      salePrice: salePrice ?? this.salePrice,
      currency: currency ?? this.currency,
      linkUrl: linkUrl ?? this.linkUrl,
      imagePath: imagePath ?? this.imagePath,
      stockStatus: stockStatus ?? this.stockStatus,
      salesCountLocal: salesCountLocal ?? this.salesCountLocal,
      clickCountLocal: clickCountLocal ?? this.clickCountLocal,
      purchaseInitiatedCount: purchaseInitiatedCount ?? this.purchaseInitiatedCount,
      purchaseCompletedCount: purchaseCompletedCount ?? this.purchaseCompletedCount,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      stickerType: stickerType ?? this.stickerType,
    );
  }

  static double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  static int _toInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }
}

/// ClickableZone — the rectangular region of the video frame where a sticker
/// is tappable. Stored as normalized coordinates (0.0–1.0) so it scales with
/// any video resolution.
class ClickableZone {
  final double x; // left (0–1)
  final double y; // top (0–1)
  final double width; // 0–1
  final double height; // 0–1

  const ClickableZone({
    this.x = 0.7,
    this.y = 0.1,
    this.width = 0.28,
    this.height = 0.28,
  });

  factory ClickableZone.fromJson(dynamic json) {
    if (json == null) return const ClickableZone();
    final Map<String, dynamic> map =
        json is Map<String, dynamic> ? json : <String, dynamic>{};
    final toDouble = (dynamic v) {
      if (v == null) return 0.0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0.0;
    };
    return ClickableZone(
      x: toDouble(map['x']),
      y: toDouble(map['y']),
      width: toDouble(map['width']),
      height: toDouble(map['height']),
    );
  }

  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        'width': width,
        'height': height,
      };
}