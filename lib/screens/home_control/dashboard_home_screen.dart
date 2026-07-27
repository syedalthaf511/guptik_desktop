import 'package:flutter/material.dart';
import 'package:guptik_desktop/screens/home_control/nodedashboardscreen.dart';


import '../../screens/dashboard/all_insights_widget.dart';
import '../../screens/dashboard/dashboard_overview.dart';
// Make sure to import your NodeDashboardScreen file here
// import 'node_dashboard_screen.dart';

/// Dashboard screen that aggregates all existing dashboard widgets.
/// It is placed as the first tab in the HomeControl section.
class DashboardHomeScreen extends StatefulWidget {
  const DashboardHomeScreen({Key? key}) : super(key: key);

  @override
  State<DashboardHomeScreen> createState() => _DashboardHomeScreenState();
}

class _DashboardHomeScreenState extends State<DashboardHomeScreen> {
  // Keeps track of which sidebar item is selected (0 = Overview, 1 = Node)
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // 1. The Sidebar Navigation (Nav Items)
        NavigationRail(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (int index) {
            setState(() {
              _selectedIndex = index;
            });
          },
          labelType: NavigationRailLabelType.all,
          destinations: const [
            NavigationRailDestination(
              icon: Icon(Icons.dashboard),
              label: Text('Overview'),
            ),
            NavigationRailDestination(
              icon: Icon(Icons.router), // Icon for Node Dashboard
              label: Text('Trustme\nNode Dashboard', textAlign: TextAlign.center),
            
            ),
          ],
        ),
        
        const VerticalDivider(thickness: 1, width: 1),

        // 2. The Main Display Area
        Expanded(
          child: _buildMainContent(),
        ),
      ],
    );
  }

  // 3. Logic to switch between pages based on the selected nav item
  Widget _buildMainContent() {
    if (_selectedIndex == 1) {
      // Show your Node Dashboard here
      // You can pass the actual URL you need into nodeUrl
      return const NodeDashboardScreen(nodeUrl: "https://my-local-node.net");
    }

    // Default Dashboard (Index 0)
    // 4. Wrapped in SingleChildScrollView so it scrolls!
    return const SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DashboardOverview(),
            SizedBox(height: 16),
            // Note: I removed the 'Expanded' widget from AllInsightsWidget 
            // because you cannot use Expanded directly inside a SingleChildScrollView.
            AllInsightsWidget(), 
          ],
        ),
      ),
    );
  }
}