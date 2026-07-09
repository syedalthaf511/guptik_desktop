import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// PlayerControlsOverlay — Advanced video controls with:
/// - Double-tap left/right to seek backward/forward 10 seconds
/// - Single tap to show/hide controls overlay
/// - Play/pause, seek bar, volume, fullscreen
/// - Settings panel: streaming quality, sound, brightness
/// - Auto-hide controls after inactivity
class PlayerControlsOverlay extends StatefulWidget {
  final Player player;
  final VideoController controller;

  const PlayerControlsOverlay({
    super.key,
    required this.player,
    required this.controller,
  });

  @override
  State<PlayerControlsOverlay> createState() => _PlayerControlsOverlayState();
}

class _PlayerControlsOverlayState extends State<PlayerControlsOverlay>
    with SingleTickerProviderStateMixin {
  bool _controlsVisible = false;
  bool _showSettingsPanel = false;
  bool _isPlaying = true;
  bool _isMuted = false;
  double _volume = 100.0;
  double _brightness = 1.0;
  double _playbackSpeed = 1.0;
  String _quality = 'Auto';
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Timer? _hideTimer;
  String? _seekIndicator; // Shows ">> 10s" or "<< 10s" briefly

  // Quality options
  final List<String> _qualityOptions = ['Auto', '1080p', '720p', '480p', '360p'];
  final List<double> _speedOptions = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  late AnimationController _animController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeInOut,
    );

    // Listen to player state
    widget.player.stream.playing.listen((playing) {
      if (mounted) setState(() => _isPlaying = playing);
    });

    widget.player.stream.position.listen((pos) {
      if (mounted && _controlsVisible) setState(() => _position = pos);
    });

    widget.player.stream.duration.listen((dur) {
      if (mounted) setState(() => _duration = dur);
    });

    widget.player.stream.volume.listen((vol) {
      if (mounted) setState(() => _volume = vol);
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _animController.dispose();
    super.dispose();
  }

  void _showControls() {
    setState(() => _controlsVisible = true);
    _animController.forward();
    _startHideTimer();
  }

  void _hideControls() {
    setState(() {
      _controlsVisible = false;
      _showSettingsPanel = false;
    });
    _animController.reverse();
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _isPlaying) _hideControls();
    });
  }

  void _togglePlayPause() {
    if (_isPlaying) {
      widget.player.pause();
    } else {
      widget.player.play();
    }
  }

  void _seekRelative(int seconds) {
    final newPos = widget.player.state.position + Duration(seconds: seconds);
    widget.player.seek(newPos);
    // Show seek indicator
    setState(() {
      _seekIndicator = seconds > 0 ? '>> ${seconds}s' : '<< ${seconds.abs()}s';
    });
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _seekIndicator = null);
    });
  }

  void _seekTo(double fraction) {
    final newPos = Duration(
      milliseconds: (_duration.inMilliseconds * fraction).round(),
    );
    widget.player.seek(newPos);
  }

  void _setVolume(double vol) {
    widget.player.setVolume(vol);
    setState(() => _volume = vol);
    if (vol == 0) {
      setState(() => _isMuted = true);
    } else if (_isMuted) {
      setState(() => _isMuted = false);
    }
  }

  void _toggleMute() {
    if (_isMuted) {
      _setVolume(100.0);
    } else {
      _setVolume(0.0);
    }
  }

  void _setSpeed(double speed) {
    widget.player.setRate(speed);
    setState(() => _playbackSpeed = speed);
  }

  void _setBrightness(double value) {
    setState(() => _brightness = value.clamp(0.1, 1.0));
    // Apply visual brightness filter via overlay
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Brightness overlay (darkens video)
        if (_brightness < 1.0)
          IgnorePointer(
            child: Container(
              color: Colors.black.withValues(alpha: (1.0 - _brightness) * 0.7),
            ),
          ),

        // Gesture layer — double tap to seek, single tap to toggle controls
        GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () {
            if (_controlsVisible) {
              _hideControls();
            } else {
              _showControls();
            }
          },
          onDoubleTapDown: (details) {
            final screenWidth = MediaQuery.of(context).size.width;
            final tapX = details.globalPosition.dx;
            if (tapX < screenWidth * 0.4) {
              // Left side — seek backward
              _seekRelative(-10);
            } else if (tapX > screenWidth * 0.6) {
              // Right side — seek forward
              _seekRelative(10);
            } else {
              // Center — toggle play/pause
              _togglePlayPause();
            }
          },
          child: Container(color: Colors.transparent),
        ),

        // Seek indicator (>> 10s / << 10s)
        if (_seekIndicator != null)
          Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _seekIndicator!,
                style: const TextStyle(
                  color: Color(0xFF00E5FF),
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),

        // Controls overlay
        FadeTransition(
          opacity: _fadeAnimation,
          child: IgnorePointer(
            ignoring: !_controlsVisible,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Top gradient bar
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 80,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.7),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),

                // Bottom controls bar
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.85),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    padding: const EdgeInsets.fromLTRB(16, 40, 16, 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Seek bar
                        Row(
                          children: [
                            Text(
                              _formatDuration(_position),
                              style: const TextStyle(color: Colors.white, fontSize: 12),
                            ),
                            Expanded(
                              child: SliderTheme(
                                data: SliderThemeData(
                                  trackHeight: 4,
                                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                                  activeTrackColor: const Color(0xFF00E5FF),
                                  inactiveTrackColor: Colors.white24,
                                  thumbColor: const Color(0xFF00E5FF),
                                ),
                                child: Slider(
                                  value: _duration.inMilliseconds > 0
                                      ? _position.inMilliseconds / _duration.inMilliseconds
                                      : 0.0,
                                  onChanged: (val) {
                                    setState(() {
                                      _position = Duration(
                                        milliseconds: (_duration.inMilliseconds * val).round(),
                                      );
                                    });
                                  },
                                  onChangeEnd: (val) => _seekTo(val),
                                ),
                              ),
                            ),
                            Text(
                              _formatDuration(_duration),
                              style: const TextStyle(color: Colors.white, fontSize: 12),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        // Control buttons row
                        Row(
                          children: [
                            // Play/Pause
                            IconButton(
                              icon: Icon(
                                _isPlaying ? Icons.pause : Icons.play_arrow,
                                color: Colors.white,
                                size: 28,
                              ),
                              onPressed: _togglePlayPause,
                            ),
                            // Seek backward
                            IconButton(
                              icon: const Icon(Icons.replay_10, color: Colors.white, size: 22),
                              onPressed: () => _seekRelative(-10),
                            ),
                            // Seek forward
                            IconButton(
                              icon: const Icon(Icons.forward_10, color: Colors.white, size: 22),
                              onPressed: () => _seekRelative(10),
                            ),
                            // Volume
                            IconButton(
                              icon: Icon(
                                _isMuted ? Icons.volume_off : Icons.volume_up,
                                color: Colors.white,
                                size: 22,
                              ),
                              onPressed: _toggleMute,
                            ),
                            // Volume slider
                            SizedBox(
                              width: 80,
                              child: SliderTheme(
                                data: SliderThemeData(
                                  trackHeight: 3,
                                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                                  activeTrackColor: const Color(0xFF00E5FF),
                                  inactiveTrackColor: Colors.white24,
                                  thumbColor: const Color(0xFF00E5FF),
                                ),
                                child: Slider(
                                  value: _volume,
                                  min: 0, max: 100,
                                  onChanged: _setVolume,
                                ),
                              ),
                            ),
                            const Spacer(),
                            // Playback speed
                            PopupMenuButton<double>(
                              icon: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '${_playbackSpeed}x',
                                  style: const TextStyle(color: Colors.white, fontSize: 12),
                                ),
                              ),
                              color: const Color(0xFF1E293B),
                              onSelected: _setSpeed,
                              itemBuilder: (context) => _speedOptions.map((speed) {
                                return PopupMenuItem<double>(
                                  value: speed,
                                  child: Text(
                                    '${speed}x',
                                    style: TextStyle(
                                      color: speed == _playbackSpeed
                                          ? const Color(0xFF00E5FF)
                                          : Colors.white,
                                      fontWeight: speed == _playbackSpeed
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                            // Settings
                            IconButton(
                              icon: const Icon(Icons.settings, color: Colors.white, size: 22),
                              onPressed: () {
                                setState(() => _showSettingsPanel = !_showSettingsPanel);
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // Settings panel (slides up from bottom)
                if (_showSettingsPanel)
                  Positioned(
                    bottom: 90,
                    right: 16,
                    child: Container(
                      width: 280,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B).withValues(alpha: 0.95),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.5),
                            blurRadius: 20,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Quality
                          const Text('Streaming Quality',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: _qualityOptions.map((q) {
                              final isActive = q == _quality;
                              return ChoiceChip(
                                label: Text(q, style: TextStyle(
                                  color: isActive ? Colors.black : Colors.white,
                                  fontSize: 12,
                                )),
                                selected: isActive,
                                selectedColor: const Color(0xFF00E5FF),
                                onSelected: (val) {
                                  if (val) setState(() => _quality = q);
                                },
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 16),
                          const Divider(color: Colors.white12),
                          const SizedBox(height: 16),
                          // Brightness
                          const Text('Brightness',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(Icons.brightness_low, color: Colors.grey, size: 18),
                              Expanded(
                                child: SliderTheme(
                                  data: SliderThemeData(
                                    trackHeight: 3,
                                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                    activeTrackColor: const Color(0xFF00E5FF),
                                    inactiveTrackColor: Colors.white24,
                                    thumbColor: const Color(0xFF00E5FF),
                                  ),
                                  child: Slider(
                                    value: _brightness,
                                    min: 0.1, max: 1.0,
                                    onChanged: _setBrightness,
                                  ),
                                ),
                              ),
                              const Icon(Icons.brightness_high, color: Colors.grey, size: 18),
                            ],
                          ),
                          const SizedBox(height: 16),
                          const Divider(color: Colors.white12),
                          const SizedBox(height: 16),
                          // Volume
                          const Text('Sound',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(Icons.volume_down, color: Colors.grey, size: 18),
                              Expanded(
                                child: SliderTheme(
                                  data: SliderThemeData(
                                    trackHeight: 3,
                                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                    activeTrackColor: const Color(0xFF00E5FF),
                                    inactiveTrackColor: Colors.white24,
                                    thumbColor: const Color(0xFF00E5FF),
                                  ),
                                  child: Slider(
                                    value: _volume,
                                    min: 0, max: 100,
                                    onChanged: _setVolume,
                                  ),
                                ),
                              ),
                              const Icon(Icons.volume_up, color: Colors.grey, size: 18),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
