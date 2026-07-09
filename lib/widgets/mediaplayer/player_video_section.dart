import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

class PlayerVideoSection extends StatelessWidget {
  final VideoController controller;
  final List<String> stickers;

  const PlayerVideoSection({super.key, required this.controller, this.stickers = const []});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(color: const Color(0xFF00E5FF).withAlpha(20), blurRadius: 20, spreadRadius: 2)
          ]
        ),
        clipBehavior: Clip.antiAlias,
        child: Video(controller: controller),
      ),
    );
  }
}