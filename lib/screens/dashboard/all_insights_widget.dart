import 'package:flutter/material.dart';

/// Placeholder widget for displaying all MJAOI insights and connections.
/// In a real implementation this would aggregate data from various services
/// and present them in a dashboard view.
class AllInsightsWidget extends StatelessWidget {
  const AllInsightsWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'All MJAOI Insights & Connections',
        style: const TextStyle(color: Colors.white, fontSize: 18),
      ),
    );
  }
}
