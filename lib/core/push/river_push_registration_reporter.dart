import 'dart:convert';

import 'package:http/http.dart' as http;

class RiverPushRegistrationReporter {
  RiverPushRegistrationReporter({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  Future<void> report({
    required String endpointUrl,
    required Map<String, dynamic> payload,
  }) async {
    final uri = Uri.parse(endpointUrl);
    final response = await _client
        .post(
          uri,
          headers: const <String, String>{
            'Content-Type': 'application/json; charset=utf-8',
            'Accept': 'application/json',
          },
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 12));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('push register HTTP ${response.statusCode}');
    }
  }
}
