import 'package:built_swagger/src/domain/parameter.dart';

class Operation {
  final String name;
  final String method;
  final String path;
  final String description;
  final String requestContentType, responseContentType;
  final List<dynamic> parentResources;
  final Iterable<Parameter> parameters;

  Operation(
      this.name, this.path, this.description, final Map<String, dynamic> data)
      : this.parentResources = data['tags'],
        this.method = data['operationId'],
        this.requestContentType = data.containsKey('consumes')
            ? (data['consumes'] as List<dynamic>).first
            : 'application/json',
        this.responseContentType = data.containsKey('produces')
            ? (data['produces'] as List<dynamic>).first
            : 'application/json',
        this.parameters = _toParameters(path, data['parameters']) {
    //print(this.parentResources);
    if (this.method == 'deleteClausById') {
      print(data['parameters']);
      print('parameters: $path');
    }
  }

  static Iterable<Parameter> _toParameters(
      final String path, final List<dynamic> raw) {
    if (raw == null) return <Parameter>[];

    final List<Parameter> pathParameters = new RegExp(r'{([^}]+)}')
        .allMatches(path)
        .map((Match match) =>
            new Parameter(match.group(1), true, 'path', 'string', null, null))
        .toList(growable: false);

    final List<Parameter> otherParameters = raw
        .map((dynamic raw) => new Parameter(
            raw['name'],
            raw['required'] == 'true',
            raw['in'],
            raw['type'],
            raw['items'],
            raw['collectionFormat']))
        .toList(growable: false);

    return new List<Parameter>.from(pathParameters)
      ..addAll(otherParameters.where((Parameter parameter) =>
          parameter.location != 'path' ||
          !pathParameters
                  .map((Parameter parameter) => parameter.name)
                  .contains(parameter.name) &&
              pathParameters.firstWhere(
                      (Parameter existing) => existing.name == parameter.name,
                      orElse: () => null) ==
                  null));
  }
}
