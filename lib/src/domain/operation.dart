import 'package:built_swagger/src/domain/parameter.dart';

class Operation {
  final String name;
  final String method;
  final String requestContentType, responseContentType;
  final List<String> parentResources;
  final Iterable<Parameter> parameters;

  Operation(this.name, Map<String, dynamic> data)
      : this.parentResources = data['tags'],
        this.method = data['operationId'],
        this.requestContentType = (data['consumes'] as List<String>).first,
        this.responseContentType = (data['produces'] as List<String>).first,
        this.parameters = _toParameters(data['parameters']) {
    //print(this.parentResources);
  }

  static Iterable<Parameter> _toParameters(List<Map<String, dynamic>> raw) {
    if (raw == null) return <Parameter>[];

    return raw.map((Map<String, dynamic> raw) => new Parameter(
        raw['name'], raw['required'] == 'true', raw['type']));
  }
}
