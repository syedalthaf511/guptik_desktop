import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import '../../models/home.dart';
import '../../models/room.dart';
import '../../models/board.dart';
import '../../models/switch.dart' as smart_switch;
import '../../services/supabase_service.dart';
import '../../utils/management_dialogs.dart';
import 'dashboard_home_screen.dart';
import '../settings/settings_screen.dart';
import '../guptik/guptik_screen.dart';
import '../vault/vault_screen.dart';
import '../mediaplayer/desktop_media_home_screen.dart';
import '../trust_me/trust_me_screen.dart';
import '../facebook/meta_dashboard.dart';
import '../whatsapp/whatsapp_screen.dart';
import '../datatables/datatables_screen.dart';
import '../../services/external/postgres_service.dart';
import 'dart:io';

class HomeControlScreen extends StatefulWidget {
  const HomeControlScreen({super.key});

  @override
  State<HomeControlScreen> createState() => _HomeControlScreenState();
}

class _HomeControlScreenState extends State<HomeControlScreen> with SingleTickerProviderStateMixin {
  late final SupabaseService _supabaseService;
  late Future<List<Home>> _homesFuture;
  Home? _selectedHome;
  late TabController _tabController;
  String _gatewayUrl = "localhost:55000"; // Default value

  @override
  void initState() {
    super.initState();
    _supabaseService = SupabaseService();
    _homesFuture = _supabaseService.getHomes();
    _tabController = TabController(length: 10, vsync: this);
    _loadGatewayUrl();
  }

  Future<void> _loadGatewayUrl() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? storedUrl = prefs.getString('public_url');
      
      if (storedUrl != null && storedUrl.isNotEmpty) {
        // Remove protocol and trailing slash if present
        storedUrl = storedUrl.replaceAll('https://', '').replaceAll('http://', '');
        if (storedUrl.endsWith('/')) storedUrl = storedUrl.substring(0, storedUrl.length - 1);
        
        // Set to localhost for local access
        setState(() {
          _gatewayUrl = "localhost:55000";
        });
      }
    } catch (e) {
      debugPrint("Error loading gateway URL: $e");
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _showAddRoomDialog(String homeId) {
    showDialog(
      context: context,
      builder: (context) => AddRoomDialog(
        homeId: homeId,
        onRoomAdded: (room) async {
          try {
            await _supabaseService.createRoom(room);
            setState(() {
              _homesFuture = _supabaseService.getHomes();
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Room added successfully')),
            );
          } catch (e) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error: $e')),
            );
          }
        },
      ),
    );
  }

  void _showAddBoardDialog(String? homeId, String? roomId) {
    showDialog(
      context: context,
      builder: (context) => AddBoardDialog(
        homeId: homeId,
        roomId: roomId,
        onBoardAdded: (board) async {
          try {
            final ownerId = _supabaseService.currentUserId ?? '';
            final newBoard = Board(
              homeId: board.homeId ?? homeId,
              roomId: board.roomId ?? roomId,
              ownerId: ownerId,
              name: board.name,
              macAddress: board.macAddress,
              status: board.status,
            );

            await _supabaseService.createBoard(newBoard);
            setState(() {
              _homesFuture = _supabaseService.getHomes();
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Board added successfully')),
            );
          } catch (e) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error: $e')),
            );
          }
        },
      ),
    );
  }

  void _showAddHomeDialog() {
    showDialog(
      context: context,
      builder: (context) => AddHomeDialog(
        onHomeAdded: (home) async {
          try {
            final userId = _supabaseService.currentUserId;
            if (userId != null) {
              final newHome = Home(
                userId: userId,
                name: home.name,
                address: home.address,
                city: home.city,
                country: home.country,
              );
              await _supabaseService.createHome(newHome);
              setState(() {
                _homesFuture = _supabaseService.getHomes();
              });
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Home added successfully')),
              );
            }
          } catch (e) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error: $e')),
            );
          }
        },
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        title: Row(
          children: [
            Image.asset('lib/assets/logonobg.png', height: 30),
            const SizedBox(width: 10),
            const Text('Guptik Desktop', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(width: 10),
            const Text('v0.1.0', style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.minimize, color: Colors.white),
            onPressed: () => windowManager.minimize(),
          ),
          IconButton(
            icon: const Icon(Icons.check_box_outline_blank, color: Colors.white),
            onPressed: () async {
              bool isMaximized = await windowManager.isMaximized();
              if (isMaximized) {
                windowManager.unmaximize();
              } else {
                windowManager.maximize();
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => windowManager.close(),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(LucideIcons.grid), text: 'Dashboard'),
            Tab(icon: Icon(LucideIcons.home), text: 'Home Control'),
            Tab(icon: Icon(LucideIcons.settings), text: 'Settings'),
            Tab(icon: Icon(LucideIcons.bot), text: 'Guptik AI'),
            Tab(icon: Icon(LucideIcons.shield), text: 'Vault'),
            Tab(icon: Icon(LucideIcons.play), text: 'Media Player'),
            Tab(icon: Icon(LucideIcons.lock), text: 'Trust Me'),
            Tab(icon: Icon(LucideIcons.facebook), text: 'Meta Manager'),
            Tab(icon: Icon(LucideIcons.messageCircle), text: 'WhatsApp'),
            Tab(icon: Icon(LucideIcons.table, size: 24, color: Colors.cyanAccent), text: 'Data Tables'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          const DashboardHomeScreen(),
          _buildHomeContentWithSidebar(),
          const SettingsScreen(),
          const GuptikScreen(),
          const VaultScreen(),
          DesktopMediaHomeScreen(gatewayUrl: _gatewayUrl),
          const TrustMeScreen(),
          const MetaDashboard(),
          const WhatsAppScreen(),
          const DatatablesScreen(),
        ],
      ),
    );
  }

  Widget _buildHomeContentWithSidebar() {
    return FutureBuilder<List<Home>>(
      future: _homesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.cyanAccent),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Error loading homes',
              style: TextStyle(color: Colors.red.shade400),
            ),
          );
        }

        final homes = snapshot.data ?? [];

        if (homes.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  LucideIcons.home,
                  size: 64,
                  color: Colors.grey.shade700,
                ),
                const SizedBox(height: 16),
                const Text(
                  'No homes configured',
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Create a home on your mobile app to get started',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          );
        }

        _selectedHome ??= homes[0];

        return Row(
          children: [
            // SIDEBAR: Homes List
            Container(
              width: 300,
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                border: Border(right: BorderSide(color: Colors.white.withOpacity(0.1))),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'My Homes',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _showAddHomeDialog,
                          icon: const Icon(LucideIcons.plus),
                          label: const Text('Add Home'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.cyanAccent,
                            foregroundColor: Colors.black,
                            minimumSize: const Size(double.infinity, 48),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: homes.length,
                      itemBuilder: (context, index) {
                        final home = homes[index];
                        final isSelected = _selectedHome?.id == home.id;

                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                _selectedHome = home;
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? Colors.cyanAccent.withOpacity(0.1)
                                    : Colors.transparent,
                                border: Border(
                                  left: BorderSide(
                                    color: isSelected
                                        ? Colors.cyanAccent
                                        : Colors.transparent,
                                    width: 3,
                                  ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    LucideIcons.home,
                                    color: isSelected
                                        ? Colors.cyanAccent
                                        : Colors.grey,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          home.name,
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: isSelected
                                                ? Colors.cyanAccent
                                                : Colors.white,
                                          ),
                                        ),
                                        if (home.address != null)
                                          Text(
                                            home.address!,
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey.shade600,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            // MAIN CONTENT AREA
            Expanded(
              child: _buildHomeContent(_selectedHome!),
            ),
          ],
        );
      },
    );
  }

  Widget _buildHomeContent(Home home) {
    return FutureBuilder<List<Room>>(
      future: _supabaseService.getRoomsForHome(home.id),
      builder: (context, roomSnapshot) {
        if (roomSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.cyanAccent),
          );
        }

        final rooms = roomSnapshot.data ?? [];

        return Column(
          children: [
            // HOME HEADER
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                border: Border(
                  bottom: BorderSide(color: Colors.white.withOpacity(0.1)),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    home.name,
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  if (home.address != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        children: [
                          const Icon(
                            LucideIcons.mapPin,
                            size: 16,
                            color: Colors.grey,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            home.address!,
                            style: TextStyle(color: Colors.grey.shade400),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            // ROOMS AND DEVICES
            Expanded(
              child: rooms.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            LucideIcons.layoutGrid,
                            size: 64,
                            color: Colors.grey.shade700,
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'No rooms configured',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton.icon(
                            onPressed: () => _showAddRoomDialog(home.id),
                            icon: const Icon(LucideIcons.plus),
                            label: const Text('Add First Room'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.cyanAccent,
                              foregroundColor: Colors.black,
                            ),
                          ),
                        ],
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ...rooms.map((room) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 32),
                              child: _buildRoomSection(home.id, room),
                            );
                          }),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: () => _showAddRoomDialog(home.id),
                            icon: const Icon(LucideIcons.plus),
                            label: const Text('Add Another Room'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.cyanAccent.withOpacity(0.7),
                              foregroundColor: Colors.black,
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildRoomSection(String homeId, Room room) {
    return FutureBuilder<List<Board>>(
      future: _supabaseService.getBoardsForHome(homeId),
      builder: (context, boardSnapshot) {
        final boards = boardSnapshot.data ?? [];
        final roomBoards = boards.where((b) => b.roomId == room.id).toList();

        if (roomBoards.isEmpty) {
          return SizedBox.shrink();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                children: [
                  Icon(
                    LucideIcons.layoutGrid,
                    color: Colors.cyanAccent,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    room.name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: () => _showAddBoardDialog(homeId, room.id),
                    icon: const Icon(LucideIcons.plus, size: 16),
                    label: const Text('Add Board'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                ],
              ),
            ),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                childAspectRatio: 1,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
              ),
              itemCount: roomBoards.length,
              itemBuilder: (context, index) {
                final board = roomBoards[index];
                return _buildBoardCard(board);
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildBoardCard(Board board) {
    return FutureBuilder<List<smart_switch.Switch>>(
      future: _supabaseService.getSwitchesForBoard(board.id),
      builder: (context, switchSnapshot) {
        final switches = switchSnapshot.data ?? [];

        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: board.isOnline ? Colors.cyanAccent : Colors.grey,
              width: 1.5,
            ),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                board.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                board.status,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: board.isOnline
                                      ? Colors.greenAccent
                                      : Colors.red.shade400,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: board.isOnline
                                ? Colors.greenAccent
                                : Colors.grey.shade700,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: switches.isEmpty
                    ? Center(
                        child: Text(
                          'No devices',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        itemCount: switches.length,
                        itemBuilder: (context, index) {
                          final switchItem = switches[index];
                          return _buildSwitchControl(switchItem);
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSwitchControl(smart_switch.Switch switchItem) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: switchItem.isEnabled
              ? () async {
                  try {
                    await _supabaseService.updateSwitchState(
                      switchItem.id,
                      !switchItem.state,
                    );
                    setState(() {
                      _homesFuture = _supabaseService.getHomes();
                    });
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error: $e'),
                        backgroundColor: Colors.red.shade400,
                      ),
                    );
                  }
                }
              : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: switchItem.state
                    ? Colors.cyanAccent
                    : Colors.white.withOpacity(0.1),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        switchItem.name,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        switchItem.typeLabel,
                        style: TextStyle(
                          fontSize: 9,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: switchItem.state ? Colors.greenAccent : Colors.grey,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Center(
                    child: Icon(
                      switchItem.state
                          ? LucideIcons.power
                          : LucideIcons.powerOff,
                      size: 12,
                      color: Colors.black,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
