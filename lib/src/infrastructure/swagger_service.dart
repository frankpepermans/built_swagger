import 'dart:async';
import 'dart:convert';

import 'package:http/browser_client.dart' show BrowserClient;
import 'package:http/http.dart' as http show Response;

import 'package:built_swagger/src/domain/blueprint.dart';

class SwaggerService {

  Future<Blueprint> fetchDocumentation() async {
    const String url = 'http://188.166.66.71:81/v2/api-docs';
    final BrowserClient client = new BrowserClient();

    return client.get(url)
        .then((http.Response response) => response.body)
        .then((String body) => JSON.decode(body))
        .then((Map<String, dynamic> raw) => new Blueprint(raw['tags'], raw['paths']));
  }

}