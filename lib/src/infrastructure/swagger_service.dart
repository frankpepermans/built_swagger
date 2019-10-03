import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:built_swagger/src/domain/blueprint.dart';

class SwaggerService {
  const SwaggerService();

  Future<Blueprint> fetchDocumentation(final String url) async => http
      .get(url, headers: {'Cache-Control': 'no-cache'})
      .then((http.Response response) => response.body)
      .then((String body) => new Map<String, dynamic>.from(json.decode(body)))
      .then((Map<String, dynamic> raw) =>
          new Blueprint(raw['tags'], raw['paths']));
}
