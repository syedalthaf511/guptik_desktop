import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/mediaplayer/player_report_service.dart';

/// ReportsScreen — Shows the watcher's filed reports (local mp_reports) and
/// lets them file a new report for a video. Part of the Media Player section so
/// users can review the status of reports they submitted (new / submitted) and
/// see whether each one has synced to the admin Supabase `mp_reports` table.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final PlayerReportService _reportService = PlayerReportService();
  List<Map<String, dynamic>> _reports = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  Future<void> _loadReports() async {
    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    final reports = await _reportService.myReports(currentUser.id);
    if (mounted) {
      setState(() {
        _reports = reports;
        _isLoading = false;
      });
    }
  }

  String _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    try {
      final dt = DateTime.parse(raw);
      return '${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return raw;
    }
  }

  Color _statusColor(String? status) {
    switch (status) {
      case 'new':
        return Colors.orange;
      case 'submitted':
        return Colors.blueAccent;
      case 'resolved':
        return Colors.green;
      default:
        return Colors.grey;
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
        title: const Row(
          children: [
            Icon(Icons.flag_outlined, color: Color(0xFF00E5FF)),
            SizedBox(width: 12),
            Text('My Reports', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadReports,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF)))
          : _reports.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.flag_outlined, color: Colors.white24, size: 64),
                      const SizedBox(height: 16),
                      const Text('No reports filed yet.', style: TextStyle(color: Colors.grey, fontSize: 16)),
                      const SizedBox(height: 8),
                      const Text(
                        'Use the Report button on a video to report policy violations.',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(24),
                  itemCount: _reports.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final r = _reports[index];
                    final status = r['status']?.toString();
                    final synced = (r['synced_to_admin'] as bool?) ?? false;
                    return Container(
                      padding: const EdgeInsets.all(16),
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
                              const Icon(Icons.flag, color: Color(0xFF00E5FF), size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  r['type']?.toString().toUpperCase() ?? 'REPORT',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: _statusColor(status).withAlpha(40),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: _statusColor(status)),
                                ),
                                child: Text(
                                  status ?? 'new',
                                  style: TextStyle(color: _statusColor(status), fontSize: 11, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Video: ${r['video_id'] ?? ''}',
                            style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if ((r['description'] as String?)?.isNotEmpty ?? false) ...[
                            const SizedBox(height: 6),
                            Text(
                              r['description'].toString(),
                              style: const TextStyle(color: Colors.white70, fontSize: 13),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(
                                synced ? Icons.cloud_done : Icons.cloud_off,
                                size: 14,
                                color: synced ? Colors.greenAccent : Colors.orange,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                synced ? 'Synced to admin' : 'Pending admin sync',
                                style: TextStyle(
                                  color: synced ? Colors.greenAccent : Colors.orange,
                                  fontSize: 11,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                _formatDate(r['created_at']?.toString()),
                                style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}