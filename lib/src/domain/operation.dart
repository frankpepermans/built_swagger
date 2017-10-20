import 'package:built_swagger/src/domain/parameter.dart';

class Operation {
  final String name;
  final String method;
  final String path;
  final String description;
  final String requestContentType, responseContentType;
  final List<String> parentResources;
  final Iterable<Parameter> parameters;

  Operation(
      this.name, this.path, this.description, final Map<String, dynamic> data)
      : this.parentResources = data['tags'],
        this.method = data['operationId'],
        this.requestContentType = (data['consumes'] as List<String>).first,
        this.responseContentType = (data['produces'] as List<String>).first,
        this.parameters = _toParameters(path, data['parameters']) {
    //print(this.parentResources);
  }

  static Iterable<Parameter> _toParameters(
      final String path, final List<Map<String, dynamic>> raw) {
    if (raw == null) return <Parameter>[];

    final List<Parameter> pathParameters = new RegExp(r'{([^}]+)}')
        .allMatches(path)
        .map((Match match) =>
            new Parameter(match.group(1), true, 'path', 'string', null, null))
        .toList(growable: false);

    raw.forEach((_) {
      if (_['type'] == 'array') {
        print(_);
      }
    });

    final List<Parameter> otherParameters = raw
        .map((Map<String, dynamic> raw) => new Parameter(
            raw['name'],
            raw['required'] == 'true',
            raw['in'],
            raw['type'],
            raw['items'],
            raw['collectionFormat']))
        .toList(growable: false);

    return new List<Parameter>.from(pathParameters)
      ..addAll(otherParameters.where((Parameter parameter) =>
          parameter.location != 'path' &&
          pathParameters.firstWhere(
                  (Parameter existing) => existing.name == parameter.name,
                  orElse: () => null) ==
              null));
  }
}
