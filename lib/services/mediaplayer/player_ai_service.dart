import 'dart:async';
import '../external/ollama_service.dart';

/// PlayerAIService — AI-powered video enhancement using local Ollama models.
/// Provides "Surprise" features like AI-generated video summaries, tags,
/// caption suggestions, content analysis, and real-time Q&A about the video.
class PlayerAIService {
  final OllamaService _ollama = OllamaService();

  /// Checks if the local Ollama server is running and available.
  Future<bool> isAIReady() async {
    return _ollama.isReady();
  }

  /// Fetches the list of locally pulled AI models.
  Future<List<String>> getAvailableModels() async {
    return _ollama.getLocalModels();
  }

  /// Generates an AI "Surprise" — a creative enhancement for the video.
  /// The type can be: 'summary', 'tags', 'caption', 'description', 'questions', 'vibe'
  /// Returns a streamed response for real-time display.
  Stream<String> generateSurprise({
    required String model,
    required String surpriseType,
    required String videoTitle,
    String videoDescription = '',
    String channelName = '',
    String category = '',
  }) async* {
    final prompts = _buildPrompt(surpriseType, videoTitle, videoDescription, channelName, category);
    
    yield* _ollama.generateChatStream(
      model: model,
      history: prompts,
    );
  }

  /// Generates a non-streamed response for quick features.
  Future<String> generateQuick({
    required String model,
    required String surpriseType,
    required String videoTitle,
    String videoDescription = '',
    String channelName = '',
    String category = '',
  }) async {
    final buffer = StringBuffer();
    await for (final chunk in generateSurprise(
      model: model,
      surpriseType: surpriseType,
      videoTitle: videoTitle,
      videoDescription: videoDescription,
      channelName: channelName,
      category: category,
    )) {
      buffer.write(chunk);
    }
    return buffer.toString();
  }

  /// Builds the appropriate prompt for each surprise type.
  List<Map<String, String>> _buildPrompt(
    String type,
    String title,
    String desc,
    String channel,
    String category,
  ) {
    final context = 'Video Title: "$title"'
        '${desc.isNotEmpty ? '\nDescription: $desc' : ''}'
        '${channel.isNotEmpty ? '\nChannel: $channel' : ''}'
        '${category.isNotEmpty ? '\nCategory: $category' : ''}';

    switch (type) {
      case 'summary':
        return [
          {'role': 'system', 'content': 'You are an engaging video content analyst. Provide concise, exciting summaries that make viewers want to watch. Keep it under 3 sentences.'},
          {'role': 'user', 'content': 'Give me a punchy, exciting summary of this video that makes me want to watch it right now:\n\n$context'},
        ];
      
      case 'tags':
        return [
          {'role': 'system', 'content': 'You are a video SEO expert. Generate relevant, searchable tags for videos. Return only the tags as a comma-separated list, no extra text.'},
          {'role': 'user', 'content': 'Generate 10 relevant tags for this video to maximize discoverability:\n\n$context'},
        ];
      
      case 'caption':
        return [
          {'role': 'system', 'content': 'You are a creative social media copywriter. Write catchy captions with emojis. Keep it under 2 sentences and make it shareable.'},
          {'role': 'user', 'content': 'Write a catchy social media caption for this video:\n\n$context'},
        ];
      
      case 'description':
        return [
          {'role': 'system', 'content': 'You are a professional video description writer. Write engaging, SEO-friendly descriptions with relevant formatting.'},
          {'role': 'user', 'content': 'Write an engaging and detailed description for this video:\n\n$context'},
        ];
      
      case 'questions':
        return [
          {'role': 'system', 'content': 'You are a curious viewer. Generate interesting discussion questions about videos to spark engagement. Return exactly 5 questions as a numbered list.'},
          {'role': 'user', 'content': 'Generate 5 interesting discussion questions about this video:\n\n$context'},
        ];
      
      case 'vibe':
        return [
          {'role': 'system', 'content': 'You are a vibe curator. Describe the mood, energy, and atmosphere of videos in a fun, creative way. Keep it under 3 sentences.'},
          {'role': 'user', 'content': 'What\'s the vibe of this video? Describe the mood and energy:\n\n$context'},
        ];
      
      case 'recommend':
        return [
          {'role': 'system', 'content': 'You are a video recommendation expert. Based on the video info, suggest what type of content the viewer might enjoy next. Keep it brief and exciting.'},
          {'role': 'user', 'content': 'Based on this video, what should I watch next? Give me recommendations:\n\n$context'},
        ];
      
      case 'chat':
        return [
          {'role': 'system', 'content': 'You are a helpful AI video companion. Answer questions about the video in a friendly, conversational way.'},
          {'role': 'user', 'content': 'Context about the current video:\n$context\n\nAsk me anything about this video!'},
        ];

      default:
        return [
          {'role': 'system', 'content': 'You are a helpful AI assistant for video content.'},
          {'role': 'user', 'content': 'Tell me about this video:\n\n$context'},
        ];
    }
  }

  /// Streams a free-form chat about the video using the selected model.
  Stream<String> chatAboutVideo({
    required String model,
    required String userMessage,
    required String videoTitle,
    String videoDescription = '',
    List<Map<String, String>> conversationHistory = const [],
  }) async* {
    final context = 'You are an AI companion for a video player. The user is currently watching "$videoTitle"'
        '${videoDescription.isNotEmpty ? '. Description: $videoDescription' : ''}. '
        'Be helpful, concise, and engaging. Answer questions about the video or suggest enhancements.';

    final history = <Map<String, String>>[
      {'role': 'system', 'content': context},
      ...conversationHistory,
      {'role': 'user', 'content': userMessage},
    ];

    yield* _ollama.generateChatStream(
      model: model,
      history: history,
    );
  }

  /// Checks if any AI models are available locally.
  Future<bool> hasModelsAvailable() async {
    final models = await getAvailableModels();
    return models.isNotEmpty;
  }
}