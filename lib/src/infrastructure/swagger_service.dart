import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:built_swagger/src/domain/blueprint.dart';

class SwaggerService {
  Future<Blueprint> fetchDocumentation(final String url) async => http
      .get(url)
      .then((http.Response response) => response.body)
      .then((String body) => JSON.decode(body))
      .then((Map<String, dynamic> raw) =>
          new Blueprint(raw['tags'], raw['paths']));
}
