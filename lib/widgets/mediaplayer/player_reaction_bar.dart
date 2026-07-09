import 'package:flutter/material.dart';

class PlayerReactionBar extends StatelessWidget {
  final Function(String) onReactionSelected;

  const PlayerReactionBar({super.key, required this.onReactionSelected});

  // 🚀 UPGRADE: Added 'tooltip' so desktop users see the name when hovering
  Widget _buildReaction(IconData icon, String type, Color color, String tooltipName) {
    return IconButton(
      icon: Icon(icon, color: color),
      onPressed: () => onReactionSelected(type),
      splashRadius: 24,
      tooltip: tooltipName, 
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white12),
      ),
      // Use SingleChildScrollView in case the window gets too narrow,
      // it prevents the 7 icons from causing a screen overflow error!
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 1. Heart
            _buildReaction(Icons.favorite, 'heart', Colors.pinkAccent, 'Love'),
            const SizedBox(width: 4),
            
            // 2. Fire
            _buildReaction(Icons.local_fire_department, 'fire', Colors.orange, 'Fire'),
            const SizedBox(width: 4),
            
            // 3. Thumbs Up (Using your Guptik Cyan theme color)
            _buildReaction(Icons.thumb_up, 'thumbs_up', const Color(0xFF00E5FF), 'Like'),
            const SizedBox(width: 4),
            
            // 4. Clap (Celebration icon is standard for applause)
            _buildReaction(Icons.celebration, 'clap', Colors.yellow, 'Clap'),
            const SizedBox(width: 4),
            
            // 5. Laugh
            _buildReaction(Icons.sentiment_very_satisfied, 'laugh', Colors.amber, 'Haha'),
            const SizedBox(width: 4),
            
            // 6. Surprised (Auto Awesome acts as a great 'Wow' indicator)
            _buildReaction(Icons.auto_awesome, 'surprised', Colors.purpleAccent, 'Wow'),
            const SizedBox(width: 4),
            
            // 7. Sad
            _buildReaction(Icons.sentiment_very_dissatisfied, 'sad', Colors.blueGrey, 'Sad'),
          ],
        ),
      ),
    );
  }
}