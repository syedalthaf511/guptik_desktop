import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/mediaplayer/player_video_model.dart';
import '../../services/mediaplayer/player_ai_service.dart';

/// PlayerAIPanel — AI "Surprise" features using local Ollama models.
/// Lets users generate summaries, tags, captions, vibe checks, discussion
/// questions, and recommendations using their own locally pulled AI models.
class PlayerAIPanel extends StatefulWidget {
  final PlayerVideo video;

  const PlayerAIPanel({super.key, required this.video});

  @override
  State<PlayerAIPanel> createState() => _PlayerAIPanelState();
}

class _PlayerAIPanelState extends State<PlayerAIPanel> {
  final PlayerAIService _aiService = PlayerAIService();
  bool _isCheckingAI = true;
  bool _aiReady = false;
  List<String> _models = [];
  String? _selectedModel;
  String _aiOutput = '';
  bool _isGenerating = false;
  StreamSubscription<String>? _streamSub;

  final List<_SurpriseFeature> _features = [
    _SurpriseFeature('summary', 'Summary', Icons.summarize),
    _SurpriseFeature('tags', 'Tags', Icons.tag),
    _SurpriseFeature('caption', 'Caption', Icons.edit_note),
    _SurpriseFeature('vibe', 'Vibe Check', Icons.emoji_emotions),
    _SurpriseFeature('questions', 'Discussion', Icons.forum),
    _SurpriseFeature('recommend', 'Next Up', Icons.recommend),
  ];

  @override
  void initState() {
    super.initState();
    _checkAI();
  }

  @override
  void dispose() {
    _streamSub?.cancel();
    super.dispose();
  }

  Future<void> _checkAI() async {
    final ready = await _aiService.isAIReady();
    final models = await _aiService.getAvailableModels();
    if (mounted) {
      setState(() {
        _aiReady = ready;
        _models = models;
        _selectedModel = models.isNotEmpty ? models.first : null;
        _isCheckingAI = false;
      });
    }
  }

  Future<void> _generate(String surpriseType) async {
    if (_selectedModel == null) return;
    _streamSub?.cancel();
    setState(() {
      _isGenerating = true;
      _aiOutput = '';
    });

    final stream = _aiService.generateSurprise(
      model: _selectedModel!,
      surpriseType: surpriseType,
      videoTitle: widget.video.title,
      videoDescription: widget.video.description,
      channelName: widget.video.channelName,
      category: widget.video.category,
    );

    _streamSub = stream.listen(
      (chunk) {
        if (mounted) setState(() => _aiOutput += chunk);
      },
      onDone: () {
        if (mounted) setState(() => _isGenerating = false);
      },
      onError: (e) {
        if (mounted) {
          setState(() {
            _isGenerating = false;
            _aiOutput = 'Error: $e';
          });
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withAlpha(150),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _aiReady
              ? const Color(0xFF00E5FF).withAlpha(50)
              : Colors.orange.withAlpha(50),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome,
                  color: _aiReady ? const Color(0xFF00E5FF) : Colors.orange,
                  size: 22),
              const SizedBox(width: 8),
              const Text('AI Surprise',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
              const Spacer(),
              if (_models.isNotEmpty) ...[
                const Text('Model:',
                    style: TextStyle(color: Colors.grey, fontSize: 12)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedModel,
                      isDense: true,
                      dropdownColor: const Color(0xFF1E293B),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      icon: const Icon(Icons.expand_more,
                          color: Color(0xFF00E5FF), size: 18),
                      items: _models
                          .map((m) => DropdownMenuItem<String>(
                                value: m,
                                child: Text(m,
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 12)),
                              ))
                          .toList(),
                      onChanged: (val) => setState(() => _selectedModel = val),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          if (_isCheckingAI)
            const Center(
                child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Color(0xFF00E5FF))))
          else if (!_aiReady || _models.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Column(
                children: [
                  Icon(Icons.cloud_off, color: Colors.orange, size: 32),
                  SizedBox(height: 8),
                  Text('No local AI models found',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold)),
                  SizedBox(height: 4),
                  Text(
                      'Pull an AI model to enable surprise features.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            )
          else ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _features.map((feature) {
                return GestureDetector(
                  onTap: _isGenerating ? null : () => _generate(feature.type),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: _isGenerating
                          ? Colors.grey.withAlpha(20)
                          : const Color(0xFF00E5FF).withAlpha(20),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _isGenerating
                            ? Colors.white12
                            : const Color(0xFF00E5FF).withAlpha(50),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(feature.icon,
                            color: const Color(0xFF00E5FF), size: 16),
                        const SizedBox(width: 6),
                        Text(feature.label,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            if (_aiOutput.isNotEmpty || _isGenerating) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 200),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_isGenerating && _aiOutput.isEmpty)
                        const Row(children: [
                          SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Color(0xFF00E5FF))),
                          SizedBox(width: 8),
                          Text('Generating...',
                              style: TextStyle(
                                  color: Color(0xFF00E5FF), fontSize: 12)),
                        ]),
                      Text(_aiOutput,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13, height: 1.5)),
                    ],
                  ),
                ),
              ),
              if (_aiOutput.isNotEmpty && !_isGenerating)
                const SizedBox(height: 8),
              if (_aiOutput.isNotEmpty && !_isGenerating)
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: () => setState(() => _aiOutput = ''),
                      icon: const Icon(Icons.clear, color: Colors.grey, size: 16),
                      label: const Text('Clear',
                          style: TextStyle(color: Colors.grey, fontSize: 12)),
                    ),
                  ],
                ),
            ],
          ],
        ],
      ),
    );
  }
}

class _SurpriseFeature {
  final String type;
  final String label;
  final IconData icon;
  const _SurpriseFeature(this.type, this.label, this.icon);
}