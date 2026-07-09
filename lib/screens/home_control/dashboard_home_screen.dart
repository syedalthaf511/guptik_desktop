import 'package:flutter/material.dart';

import '../../screens/dashboard/all_insights_widget.dart';
import '../../screens/dashboard/dashboard_overview.dart';

/// Dashboard screen that aggregates all existing dashboard widgets.
/// It is placed as the first tab in the HomeControl section.
class DashboardHomeScreen extends StatelessWidget {
  const DashboardHomeScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Main dashboard area (no sidebar for now)
        Expanded(
          child: Column(
            children: const [
              DashboardOverview(),
              Expanded(child: AllInsightsWidget()),
            ],
          ),
        ),
      ],
    );
  }
}
