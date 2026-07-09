import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/mediaplayer/player_notification_model.dart';
import '../../services/mediaplayer/player_analytics_service.dart';

/// NotificationsScreen — Social notifications for comments, likes, reposts,
/// subscriptions, and supporter badges. Shows unread badge and allows
/// marking individual or all notifications as read.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final PlayerAnalyticsService _service = PlayerAnalyticsService();
  List<PlayerNotification> _notifications = [];
  bool _isLoading = true;
  int _unreadCount = 0;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser == null) {
      setState(() => _isLoading = false);
      return;
    }

    setState(() => _isLoading = true);

    final results = await Future.wait([
      _service.fetchNotifications(currentUser.id),
      _service.fetchUnreadNotificationCount(currentUser.id),
    ]);

    if (mounted) {
      setState(() {
        _notifications = results[0] as List<PlayerNotification>;
        _unreadCount = results[1] as int;
        _isLoading = false;
      });
    }
  }

  Future<void> _markAllRead() async {
    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser == null) return;

    final success = await _service.markAllNotificationsRead(currentUser.id);
    if (success) {
      _loadNotifications();
    }
  }

  Future<void> _markRead(PlayerNotification notification) async {
    if (notification.isRead) return;
    await _service.markNotificationRead(notification.notificationId);
    _loadNotifications();
  }

  IconData _getIconForType(String iconKey) {
    switch (iconKey) {
      case 'comment':
        return Icons.comment;
      case 'thumb_up':
        return Icons.thumb_up;
      case 'repeat':
        return Icons.repeat;
      case 'subscriptions':
        return Icons.subscriptions;
      case 'verified':
        return Icons.verified;
      case 'alternate_email':
        return Icons.alternate_email;
      default:
        return Icons.notifications;
    }
  }

  Color _getColorForType(String type) {
    switch (type) {
      case 'comment':
        return Colors.blue;
      case 'like':
        return Colors.pinkAccent;
      case 'repost':
        return Colors.green;
      case 'subscribe':
        return Colors.redAccent;
      case 'badge':
        return const Color(0xFFD4AF37);
      case 'mention':
        return Colors.purple;
      default:
        return const Color(0xFF00E5FF);
    }
  }

  String _getTimeAgo(String? dateString) {
    if (dateString == null || dateString.isEmpty) return 'recently';
    try {
      final date = DateTime.parse(dateString);
      final difference = DateTime.now().difference(date);
      if (difference.inDays > 0) return '${difference.inDays}d ago';
      if (difference.inHours > 0) return '${difference.inHours}h ago';
      if (difference.inMinutes > 0) return '${difference.inMinutes}m ago';
      return 'just now';
    } catch (_) {
      return 'recently';
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
        title: Row(
          children: [
            const Text('Notifications',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
            if (_unreadCount > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.redAccent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('$_unreadCount',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ],
        ),
        actions: [
          if (_unreadCount > 0)
            TextButton(
              onPressed: _markAllRead,
              child: const Text('Mark all read',
                  style: TextStyle(color: Color(0xFF00E5FF), fontSize: 13)),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF)))
          : RefreshIndicator(
              color: const Color(0xFF00E5FF),
              backgroundColor: const Color(0xFF1E293B),
              onRefresh: _loadNotifications,
              child: _notifications.isEmpty
                  ? ListView(
                      children: [
                        const SizedBox(height: 200),
                        Center(
                          child: Column(
                            children: [
                              const Icon(Icons.notifications_none,
                                  color: Colors.white24, size: 80),
                              const SizedBox(height: 16),
                              const Text('No notifications yet.',
                                  style: TextStyle(
                                      color: Colors.grey, fontSize: 18)),
                              const SizedBox(height: 8),
                              const Text(
                                  'You\'ll see updates about comments, likes, and more here.',
                                  style: TextStyle(
                                      color: Colors.grey, fontSize: 14)),
                            ],
                          ),
                        ),
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _notifications.length,
                      separatorBuilder: (context, index) =>
                          const Divider(color: Colors.white12, height: 1),
                      itemBuilder: (context, index) {
                        final notif = _notifications[index];
                        final iconColor =
                            _getColorForType(notif.notificationType);
                        final isUnread = !notif.isRead;

                        return GestureDetector(
                          onTap: () => _markRead(notif),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: isUnread
                                  ? const Color(0xFF00E5FF).withAlpha(10)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: iconColor.withAlpha(30),
                                    borderRadius: BorderRadius.circular(24),
                                  ),
                                  child: Icon(
                                    _getIconForType(notif.iconKey),
                                    color: iconColor,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        notif.displayMessage,
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: isUnread
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                        ),
                                      ),
                                      if (notif.commentText != null &&
                                          notif.commentText!.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          '"${notif.commentText}"',
                                          style: TextStyle(
                                              color: Colors.grey.shade400,
                                              fontSize: 13,
                                              fontStyle: FontStyle.italic),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                      const SizedBox(height: 4),
                                      Text(
                                        _getTimeAgo(notif.createdAt),
                                        style: TextStyle(
                                            color: Colors.grey.shade500,
                                            fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                                if (isUnread)
                                  Container(
                                    width: 8,
                                    height: 8,
                                    margin: const EdgeInsets.only(top: 8),
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF00E5FF),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}