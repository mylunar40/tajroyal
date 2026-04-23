import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/secrets.dart';

class AITranslateService {
  static const String apiKey = AppSecrets.openAiApiKey;

  static final Map<String, String> _cache = {};

  static Future<String> toArabic(String text) async {
    final raw = text.trim();

    if (raw.isEmpty) return "";
    if (RegExp(r'^[0-9]+$').hasMatch(raw)) return raw;
    if (raw.length < 2) return raw;

    if (_cache.containsKey(raw)) {
      return _cache[raw]!;
    }

    try {
      final response = await http.post(
        Uri.parse("https://api.openai.com/v1/responses"),
        headers: {
          "Authorization": "Bearer $apiKey",
          "Content-Type": "application/json",
        },
        body: jsonEncode({
          "model": "gpt-4o-mini",
          "input": """
Translate the text into Arabic for a Kuwait contract form.

STRICT RULES:
1. Person names must be transliterated only, not translated.
2. Company names / product codes / model names stay in English.
3. Addresses should translate naturally into Arabic.
4. Numbers stay unchanged.
5. Return ONLY the final Arabic result.
6. No explanation. No notes.

Text: $raw
"""
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        final result =
            data['output'][0]['content'][0]['text']?.toString().trim() ?? raw;

        _cache[raw] = result;
        return result;
      } else {
        debugPrint("API ERROR: ${response.body}");
        return raw;
      }
    } catch (e) {
      debugPrint("TRANSLATION ERROR: $e");
      return raw;
    }
  }
}
