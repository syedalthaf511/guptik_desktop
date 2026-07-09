import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:window_manager/window_manager.dart';

class WindowHeader extends StatefulWidget {
  final String title;

  const WindowHeader({
    required this.title,
    super.key,
  });

  @override
  State<WindowHeader> createState() => _WindowHeaderState();
}

class _WindowHeaderState extends State<WindowHeader> with WindowListener {
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() {
    setState(() => _isMaximized = true);
  }

  @override
  void onWindowUnmaximize() {
    setState(() => _isMaximized = false);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05))),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onPanStart: (details) {
                windowManager.startDragging();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Image.asset(
                      'lib/assets/logonobg.png',
                      width: 22,
                      height: 22,
                      errorBuilder: (_, _, _) => Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: Colors.cyanAccent,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Window Controls
          Row(
            children: [
              _WindowButton(
                icon: LucideIcons.minus,
                onPressed: () => windowManager.minimize(),
                tooltip: 'Minimize',
              ),
              _WindowButton(
                icon: _isMaximized ? LucideIcons.copy : LucideIcons.maximize2,
                onPressed: () => _isMaximized
                    ? windowManager.unmaximize()
                    : windowManager.maximize(),
                tooltip: _isMaximized ? 'Restore' : 'Maximize',
              ),
              _WindowButton(
                icon: LucideIcons.x,
                onPressed: () => windowManager.close(),
                tooltip: 'Close',
                isClose: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WindowButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final String tooltip;
  final bool isClose;

  const _WindowButton({
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.isClose = false,
  });

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Tooltip(
        message: widget.tooltip,
        child: GestureDetector(
          onTap: widget.onPressed,
          child: Container(
            width: 48,
            height: 48,
            color: _isHovered
                ? (widget.isClose
                    ? Colors.red.shade700
                    : Colors.white.withOpacity(0.1))
                : Colors.transparent,
            child: Center(
              child: Icon(
                widget.icon,
                size: 16,
                color: _isHovered
                    ? (widget.isClose ? Colors.white : Colors.cyanAccent)
                    : Colors.grey,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
