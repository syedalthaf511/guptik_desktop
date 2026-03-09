import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../settings/settings_screen.dart';
import '../vault/vault_screen.dart';
import '../trust_me/trust_me_screen.dart';
import '../whatsapp/whatsapp_screen.dart';
import '../home_control/home_control_screen.dart';
import '../guptik/guptik_screen.dart'; // <--- ADD THIS IMPORT
import '../../widgets/window_header.dart';
import '../datatables/datatables_screen.dart';
import '../facebook/meta_dashboard.dart';
import '../security/security_screen.dart';
import '../guptik/automation_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0; // Default to Home Control

  // Feature Views
  final List<Widget> _screens = const [
    HomeControlScreen(),
    WhatsAppScreen(),
    MetaDashboard(),
    VaultScreen(),
    TrustMeScreen(),
    GuptikScreen(),
    AutomationScreen(),
    SecurityScreen(),
    DatatablesScreen(),
    SettingsScreen(),
  ];

  final List<String> _screenLabels = [
    'Home Control',
    'WhatsApp',
    'Meta',
    'Vault',
    'Trust Me',
    'Guptik AI',
    'Automation',
    'Security',
    'Database',
    'Settings',
  ];

  final List<IconData> _screenIcons = [
    LucideIcons.home,
    LucideIcons.messageCircle,
    LucideIcons.facebook,
    LucideIcons.database,
    LucideIcons.shieldCheck,
    LucideIcons.bot,
    LucideIcons.workflow,
    LucideIcons.lock,
    LucideIcons.table,
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(48),
        child: WindowHeader(title: _screenLabels[_selectedIndex]),
      ),
      body: Row(
        children: [
          // SIDEBAR
          Container(
            width: 250,
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              border: Border(
                right: BorderSide(color: Colors.white.withOpacity(0.1)),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 30),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24.0),
                  child: Text(
                    "GUPTIK HOME",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                      color: Colors.cyanAccent,
                    ),
                  ),
                ),
                const SizedBox(height: 40),

                // FIXED: Wrapped the menu items in an Expanded + ScrollView
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: List.generate(
                        _screenIcons.length,
                        (index) => _buildNavItem(
                          index,
                          _screenLabels[index],
                          _screenIcons[index],
                        ),
                      ),
                    ),
                  ),
                ),

                // Settings at bottom (Routes to Index 9)
                _buildNavItem(9, "Settings", LucideIcons.settings),
                const SizedBox(height: 20),
              ],
            ),
          ),
          // MAIN CONTENT AREA
          Expanded(
            child: Container(
              color: const Color(0xFF0F172A),
              child: _screens[_selectedIndex],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(int index, String title, IconData icon) {
    bool isSelected = _selectedIndex == index;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
      child: ListTile(
        leading: Icon(
          icon,
          color: isSelected ? Colors.cyanAccent : Colors.grey,
          size: 20,
        ),
        title: Text(
          title,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.grey,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 14,
          ),
        ),
        tileColor: isSelected
            ? Colors.white.withOpacity(0.05)
            : Colors.transparent,
        onTap: () {
          setState(() => _selectedIndex = index);
        },
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}
