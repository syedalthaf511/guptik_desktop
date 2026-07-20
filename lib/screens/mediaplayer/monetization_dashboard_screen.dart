import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/mediaplayer/player_monetization_service.dart';
import 'sticker_editor_screen.dart';

/// MonetizationDashboardScreen — Earnings tracking, ad integration settings,
/// membership tiers, and in-video sticker management for creators.
class MonetizationDashboardScreen extends StatefulWidget {
  final String channelId;

  const MonetizationDashboardScreen({super.key, required this.channelId});

  @override
  State<MonetizationDashboardScreen> createState() =>
      _MonetizationDashboardScreenState();
}

class _MonetizationDashboardScreenState
    extends State<MonetizationDashboardScreen> {
  final PlayerMonetizationService _service = PlayerMonetizationService();
  bool _isLoading = true;
  Map<String, dynamic> _earnings = {};
  Map<String, dynamic> _adSettings = {};
  List<Map<String, dynamic>> _tiers = [];
  int _selectedTab = 0;

  // 🚀 STICKER VIDEO SELECTOR: lets a creator pick which video to attach
  // shoppable stickers to (the editor requires a videoId).
  List<Map<String, dynamic>> _channelVideos = [];
  String? _selectedStickerVideoId;
  bool _loadingVideos = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadChannelVideos() async {
    if (_channelVideos.isNotEmpty) return;
    setState(() => _loadingVideos = true);
    try {
      final supabase = Supabase.instance.client;
      final rows = await supabase
          .from('mp_videos')
          .select('video_id, title')
          .eq('creator_uid', widget.channelId)
          .order('published_at', ascending: false)
          .limit(50);
      if (mounted) {
        setState(() {
          _channelVideos = (rows as List)
              .map((r) => {'video_id': r['video_id'], 'title': r['title']})
              .toList();
          if (_channelVideos.isNotEmpty) {
            _selectedStickerVideoId = _channelVideos.first['video_id'];
          }
          _loadingVideos = false;
        });
      }
    } catch (e) {
      debugPrint('Load channel videos error: $e');
      if (mounted) setState(() => _loadingVideos = false);
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    final results = await Future.wait([
      _service.fetchChannelEarnings(widget.channelId),
      _service.fetchAdSettings(widget.channelId),
      _service.fetchMembershipTiers(widget.channelId),
    ]);

    if (mounted) {
      setState(() {
        _earnings = results[0] as Map<String, dynamic>;
        _adSettings = results[1] as Map<String, dynamic>;
        _tiers = results[2] as List<Map<String, dynamic>>;
        _isLoading = false;
      });
    }
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 8),
              Text(title,
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 12),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildEarningsView() {
    final grossRevenue =
        (_earnings['gross_revenue'] ?? 0.0).toDouble();
    final channelEarnings =
        (_earnings['channel_earnings'] ?? 0.0).toDouble();
    final totalClicks = _earnings['total_clicks'] ?? 0;
    final totalPurchases = _earnings['total_purchases'] ?? 0;
    final conversionRate =
        (_earnings['conversion_rate'] ?? 0.0).toDouble();
    final monetizationEnabled =
        _earnings['monetization_enabled'] ?? false;
    final topVideos = _earnings['top_videos'] as List? ?? [];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Earnings Overview',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: monetizationEnabled
                      ? Colors.green.withAlpha(30)
                      : Colors.orange.withAlpha(30),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: monetizationEnabled
                        ? Colors.green
                        : Colors.orange,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      monetizationEnabled
                          ? Icons.check_circle
                          : Icons.info,
                      color: monetizationEnabled
                          ? Colors.green
                          : Colors.orange,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      monetizationEnabled
                          ? 'Monetization Active'
                          : 'Monetization Disabled',
                      style: TextStyle(
                        color: monetizationEnabled
                            ? Colors.green
                            : Colors.orange,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Stat cards grid
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 1.5,
            children: [
              _buildStatCard('Gross Revenue',
                  '\$${grossRevenue.toStringAsFixed(2)}', Icons.attach_money, Colors.green),
              _buildStatCard('Channel Earnings',
                  '\$${channelEarnings.toStringAsFixed(2)}', Icons.account_balance_wallet, const Color(0xFF00E5FF)),
              _buildStatCard('Total Clicks', '$totalClicks', Icons.touch_app, Colors.orange),
              _buildStatCard('Purchases', '$totalPurchases', Icons.shopping_cart, Colors.purple),
            ],
          ),
          const SizedBox(height: 24),
          // Conversion rate
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
                const Text('Conversion Rate',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: conversionRate / 100,
                  minHeight: 8,
                  backgroundColor: const Color(0xFF0F172A),
                  color: const Color(0xFF00E5FF),
                ),
                const SizedBox(height: 8),
                Text('${conversionRate.toStringAsFixed(1)}%',
                    style: const TextStyle(color: Colors.white70, fontSize: 14)),
              ],
            ),
          ),
          const SizedBox(height: 32),
          // Top performing videos
          const Text('Top Performing Videos',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          if (topVideos.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Text('No monetized videos yet. Add stickers to your videos to start earning.',
                    style: TextStyle(color: Colors.grey, fontSize: 14)),
              ),
            )
          else
            ...topVideos.map<Widget>((video) => Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.video_library, color: Color(0xFF00E5FF), size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(video['title'] ?? '',
                                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 4),
                            Text('${video['clicks'] ?? 0} clicks • ${video['purchases'] ?? 0} purchases',
                                style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
                          ],
                        ),
                      ),
                      Text('\$${((video['revenue'] ?? 0).toDouble()).toStringAsFixed(2)}',
                          style: const TextStyle(color: Colors.green, fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                )),
        ],
      ),
    );
  }

  Widget _buildAdSettingsView() {
    bool preRoll = _adSettings['pre_roll_enabled'] ?? false;
    bool midRoll = _adSettings['mid_roll_enabled'] ?? false;
    bool postRoll = _adSettings['post_roll_enabled'] ?? false;
    int frequency = _adSettings['ad_frequency_minutes'] ?? 10;
    int skipAfter = _adSettings['skip_after_seconds'] ?? 5;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Ad Integration',
              style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Configure when ads appear in your videos.',
              style: TextStyle(color: Colors.grey, fontSize: 14)),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Pre-roll Ads', style: TextStyle(color: Colors.white)),
                  subtitle: const Text('Show ads before video starts', style: TextStyle(color: Colors.grey, fontSize: 12)),
                  activeThumbColor: const Color(0xFF00E5FF),
                  contentPadding: EdgeInsets.zero,
                  value: preRoll,
                  onChanged: (val) => setState(() => preRoll = val),
                ),
                const Divider(color: Colors.white12),
                SwitchListTile(
                  title: const Text('Mid-roll Ads', style: TextStyle(color: Colors.white)),
                  subtitle: const Text('Show ads during video playback', style: TextStyle(color: Colors.grey, fontSize: 12)),
                  activeThumbColor: const Color(0xFF00E5FF),
                  contentPadding: EdgeInsets.zero,
                  value: midRoll,
                  onChanged: (val) => setState(() => midRoll = val),
                ),
                const Divider(color: Colors.white12),
                SwitchListTile(
                  title: const Text('Post-roll Ads', style: TextStyle(color: Colors.white)),
                  subtitle: const Text('Show ads after video ends', style: TextStyle(color: Colors.grey, fontSize: 12)),
                  activeThumbColor: const Color(0xFF00E5FF),
                  contentPadding: EdgeInsets.zero,
                  value: postRoll,
                  onChanged: (val) => setState(() => postRoll = val),
                ),
                const Divider(color: Colors.white12),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text('Ad Frequency (minutes)', style: TextStyle(color: Colors.white70, fontSize: 14)),
                    const Spacer(),
                    Text('$frequency min', style: const TextStyle(color: Color(0xFF00E5FF), fontSize: 14, fontWeight: FontWeight.bold)),
                  ],
                ),
                Slider(
                  value: frequency.toDouble(),
                  min: 5, max: 30, divisions: 5,
                  activeColor: const Color(0xFF00E5FF),
                  label: '$frequency min',
                  onChanged: (val) => setState(() => frequency = val.round()),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('Skip After (seconds)', style: TextStyle(color: Colors.white70, fontSize: 14)),
                    const Spacer(),
                    Text('$skipAfter sec', style: const TextStyle(color: Color(0xFF00E5FF), fontSize: 14, fontWeight: FontWeight.bold)),
                  ],
                ),
                Slider(
                  value: skipAfter.toDouble(),
                  min: 5, max: 30, divisions: 5,
                  activeColor: const Color(0xFF00E5FF),
                  label: '$skipAfter sec',
                  onChanged: (val) => setState(() => skipAfter = val.round()),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00E5FF),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () async {
                final success = await _service.updateAdSettings(
                  channelId: widget.channelId,
                  preRollEnabled: preRoll,
                  midRollEnabled: midRoll,
                  postRollEnabled: postRoll,
                  adFrequencyMinutes: frequency,
                  skipAfterSeconds: skipAfter,
                );
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(success ? 'Ad settings saved!' : 'Failed to save settings.'),
                      backgroundColor: success ? Colors.green : Colors.redAccent,
                    ),
                  );
                }
              },
              child: const Text('Save Ad Settings',
                  style: TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMembershipView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Membership Tiers',
                  style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
              const Spacer(),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00E5FF),
                  foregroundColor: Colors.black,
                ),
                onPressed: () => _showCreateTierDialog(),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Tier'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text('Offer paid memberships with exclusive perks.',
              style: TextStyle(color: Colors.grey, fontSize: 14)),
          const SizedBox(height: 24),
          if (_tiers.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: const Center(
                child: Column(
                  children: [
                    Icon(Icons.star_border, color: Colors.grey, size: 48),
                    SizedBox(height: 12),
                    Text('No membership tiers yet.', style: TextStyle(color: Colors.grey, fontSize: 16)),
                    SizedBox(height: 4),
                    Text('Create a tier to start earning from supporters.', style: TextStyle(color: Colors.grey, fontSize: 13)),
                  ],
                ),
              ),
            )
          else
            ..._tiers.map((tier) => Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF00E5FF).withAlpha(50)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00E5FF).withAlpha(20),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.star, color: Color(0xFF00E5FF), size: 24),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(tier['tier_name'] ?? '',
                                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text(tier['description'] ?? '',
                                style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                                maxLines: 2, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 4),
                            Text('${tier['subscriber_count'] ?? 0} subscribers',
                                style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                          ],
                        ),
                      ),
                      Text('\$${((tier['price'] ?? 0).toDouble()).toStringAsFixed(2)}/${tier['currency']}',
                          style: const TextStyle(color: Color(0xFF00E5FF), fontSize: 18, fontWeight: FontWeight.bold)),
                    ],
                  ),
                )),
        ],
      ),
    );
  }

  void _showCreateTierDialog() {
    final nameController = TextEditingController();
    final priceController = TextEditingController();
    final descController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Create Membership Tier',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Tier Name',
                  labelStyle: TextStyle(color: Colors.grey),
                  filled: true,
                  fillColor: Color(0xFF0F172A),
                  border: OutlineInputBorder(borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: priceController,
                style: const TextStyle(color: Colors.white),
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Price (USD/month)',
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
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  labelStyle: TextStyle(color: Colors.grey),
                  filled: true,
                  fillColor: Color(0xFF0F172A),
                  border: OutlineInputBorder(borderSide: BorderSide.none),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E5FF)),
            onPressed: () async {
              final name = nameController.text.trim();
              final price = double.tryParse(priceController.text.trim()) ?? 0;
              final desc = descController.text.trim();
              if (name.isEmpty || price <= 0) return;

              await _service.createMembershipTier(
                channelId: widget.channelId,
                tierName: name,
                price: price,
                description: desc,
              );
              if (ctx.mounted) Navigator.pop(ctx);
              _loadData();
            },
            child: const Text('Create', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  /// 🚀 STICKERS TAB: pick a video, then show the shoppable sticker editor for
  /// that video. This is what actually wires monetization (stickers) to a
  /// specific video so they appear during playback.
  Widget _buildStickersView() {
    if (_channelVideos.isEmpty && !_loadingVideos) {
      _loadChannelVideos();
    }

    if (_loadingVideos) {
      return const Center(
          child: CircularProgressIndicator(color: Color(0xFF00E5FF)));
    }

    if (_channelVideos.isEmpty) {
      return const Center(
        child: Text('No videos found for this channel.',
            style: TextStyle(color: Colors.grey, fontSize: 14)),
      );
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            border: Border(bottom: BorderSide(color: Colors.white12)),
          ),
          child: Row(
            children: [
              const Icon(Icons.movie, color: Color(0xFF00E5FF), size: 20),
              const SizedBox(width: 12),
              const Text('Attach stickers to video:',
                  style: TextStyle(color: Colors.white, fontSize: 14)),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _selectedStickerVideoId,
                  dropdownColor: const Color(0xFF0F172A),
                  decoration: const InputDecoration(
                    filled: true,
                    fillColor: Color(0xFF0F172A),
                    border: OutlineInputBorder(borderSide: BorderSide.none),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  ),
                  style: const TextStyle(color: Colors.white),
                  items: _channelVideos
                      .map((v) => DropdownMenuItem(
                            value: v['video_id']?.toString(),
                            child: Text(
                              v['title']?.toString() ?? 'Untitled',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ))
                      .toList(),
                  onChanged: (v) =>
                      setState(() => _selectedStickerVideoId = v),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: StickerEditorScreen(
            channelId: widget.channelId,
            videoId: _selectedStickerVideoId,
          ),
        ),
      ],
    );
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
        title: const Text('Monetization Dashboard',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF)))
          : Column(
              children: [
                // Tab bar
                Container(
                  decoration: const BoxDecoration(
                    color: Color(0xFF1E293B),
                    border: Border(bottom: BorderSide(color: Colors.white12)),
                  ),
                  child: Row(
                    children: [
                      _buildTab('Earnings', 0, Icons.attach_money),
                      _buildTab('Ad Settings', 1, Icons.ads_click),
                      _buildTab('Memberships', 2, Icons.star),
                      _buildTab('Stickers', 3, Icons.shopping_bag),
                    ],
                  ),
                ),
                Expanded(
                  child: _selectedTab == 0
                      ? _buildEarningsView()
                      : _selectedTab == 1
                          ? _buildAdSettingsView()
                          : _selectedTab == 2
                              ? _buildMembershipView()
                              : _buildStickersView(),
                ),
              ],
            ),
    );
  }

  Widget _buildTab(String label, int index, IconData icon) {
    final isSelected = _selectedTab == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedTab = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isSelected ? const Color(0xFF00E5FF) : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                color: isSelected ? const Color(0xFF00E5FF) : Colors.grey,
                size: 18),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                  color: isSelected ? const Color(0xFF00E5FF) : Colors.grey,
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                )),
          ],
        ),
      ),
    );
  }
}