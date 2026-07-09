import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// A simple overview screen that displays MJAOI insights and connection information.
/// This is a placeholder implementation; replace the dummy data with real widgets
/// that fetch and display the required insights.
class DashboardOverview extends StatelessWidget {
  const DashboardOverview({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'MJAOI Insights',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 12),
          // Placeholder cards for insights
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: List.generate(4, (index) => _insightCard('Insight ${index + 1}')),
          ),
          const SizedBox(height: 24),
          const Text(
            'Connections',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 12),
          // Placeholder list for connections
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 5,
            itemBuilder: (context, i) => ListTile(
              leading: const Icon(LucideIcons.link, color: Colors.cyanAccent),
              title: Text('Connection ${i + 1}', style: const TextStyle(color: Colors.white70)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _insightCard(String title) {
    return Card(
      color: const Color(0xFF1E293B),
      child: SizedBox(
        width: 150,
        height: 100,
        child: Center(
          child: Text(title, style: const TextStyle(color: Colors.white70)),
        ),
      ),
    );
  }
}
