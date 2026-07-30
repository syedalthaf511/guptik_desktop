import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// PlayerAIService — Cloud-powered video enhancement supporting OpenRouter, OpenAI, Gemini, Anthropic, etc.
class PlayerAIService {
  
  // Reads saved settings from SharedPreferences
  Future<Map<String, String>> _getAiConfig() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'provider': prefs.getString('ai_provider') ?? 'OpenRouter',
      'url': prefs.getString('ai_endpoint_url') ?? 'https://openrouter.ai/api/v1/chat/completions',
      'key': prefs.getString('ai_api_key') ?? '',
      'model': prefs.getString('ai_model_name') ?? 'meta-llama/llama-3-8b-instruct',
    };
  }

  /// Always ready since it uses cloud endpoints
  Future<bool> isAIReady() async {
    final config = await _getAiConfig();
    return config['model'] != null && config['model']!.isNotEmpty;
  }

  /// Returns the currently configured model
  Future<List<String>> getAvailableModels() async {
    final config = await _getAiConfig();
    return [config['model'] ?? 'meta-llama/llama-3-8b-instruct'];
  }

  /// Generates an AI "Surprise" using the saved cloud configuration.
  Stream<String> generateSurprise({
    required String model,
    required String surpriseType,
    required String videoTitle,
    String videoDescription = '',
    String channelName = '',
    String category = '',
  }) async* {
    final prompts = _buildPrompt(surpriseType, videoTitle, videoDescription, channelName, category);
    final config = await _getAiConfig();
    
    final safeUrl = config['url']!.trim();
    final safeKey = config['key']!.replaceAll('\n', '').replaceAll('\r', '').replaceAll(' ', '').trim();
    
    final Map<String, String> headers = {
      "Content-Type": "application/json",
    };

    if (config['provider'] == 'OpenRouter') {
      headers["HTTP-Referer"] = "https://guptik.com";
      headers["X-Title"] = "Guptik Desktop";
    }

    if (safeKey.isNotEmpty) {
      if (config['provider'] == 'Anthropic') {
        headers["x-api-key"] = safeKey;
        headers["anthropic-version"] = "2023-06-01";
      } else {
        headers["Authorization"] = "Bearer $safeKey";
      }
    }

    final requestBody = jsonEncode({
      "model": model.isNotEmpty ? model : config['model'],
      "messages": prompts,
      "stream": false,
    });

    try {
      final response = await http.post(
        Uri.parse(safeUrl),
        headers: headers,
        body: requestBody,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        String output = "";
        if (data['choices'] != null && data['choices'].isNotEmpty) {
          output = data['choices'][0]['message']['content'] ?? "";
        } else if (data['content'] != null && data['content'] is List) {
          output = data['content'][0]['text'] ?? "";
        } else if (data['message'] != null && data['message']['content'] != null) {
          output = data['message']['content'] ?? "";
        }
        yield output;
      } else {
        yield "API Error [${response.statusCode}]: ${response.body}";
      }
    } catch (e) {
      yield "Network Error: $e";
    }
  }

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
      default:
        return [
          {'role': 'system', 'content': 'You are a helpful AI assistant for video content.'},
          {'role': 'user', 'content': 'Tell me about this video:\n\n$context'},
        ];
    }
  }

  Future<bool> hasModelsAvailable() async => true;
}