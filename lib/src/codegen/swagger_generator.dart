import 'dart:async';

import 'package:analyzer/dart/element/element.dart';
import 'package:source_gen/source_gen.dart';
import 'package:build/build.dart';

import 'package:built_swagger/src/infrastructure/swagger_service.dart';
import 'package:built_swagger/src/domain/bundle.dart';
import 'package:built_swagger/src/domain/operation.dart';
import 'package:built_swagger/src/domain/path.dart';
import 'package:built_swagger/src/domain/parameter.dart';

class SwaggerGenerator extends Generator {
  final BuilderOptions options;

  @override
  FutureOr<String> generate(LibraryReader library, BuildStep buildStep) async {
    final path = buildStep.inputId.path.split('/').sublist(1).join('/');
    final element = library.allElements.firstWhere(
        (Element element) =>
            element.location.components.first.contains(path),
        orElse: () => null);

    if (element == null) return null;

    final String endPoint = options.config['endPoint'];
    print('swagger url: $endPoint');
    final buffer = new StringBuffer();
    final service = const SwaggerService();
    final data = await service.fetchDocumentation(endPoint);
    final buildList = new Set<_PathPart>(), flatList = new Set<_PathPart>();
    var classIndex = 0;

    buffer.writeln('''import 'dart:async';''');
    buffer.writeln('''import 'dart:convert' show json;''');
    buffer.writeln('''import 'dart:html' show FormData, HttpRequest;''');
    buffer.writeln(
        '''import 'package:angular/angular.dart' show Injectable, Inject;''');

    //  /xpert_libraries/lib/src/infrastructure/remote_service.dart
    buffer.writeln('''import '${element.source.fullName.split('/').last}';''');

    buffer.writeln(
        'const List<Type> remoteServices = [${data.bundles.map(_bundleNameToClassName).join(',')}];');

    data.bundles.forEach((bundle) {
      final bundleClassName = _bundleNameToClassName(bundle);
      final bundleList = new Set<_PathPart>();

      buffer.writeln('@Injectable()');
      buffer.writeln('class $bundleClassName {');

      buffer.writeln();
      buffer.writeln('const $bundleClassName();');

      bundle.paths.forEach((path) {
        path.operations.forEach((operation) {
          var pathList = _pathToMethodName(path, operation);
          var currentBuildList = buildList;
          var loopIndex = 0;

          pathList.forEach((segment) {
            segment = segment == 'new' ? 'create' : segment;

            _PathPart pathPart = currentBuildList.firstWhere(
                (pathPart) => pathPart.segment.compareTo(segment) == 0,
                orElse: () => new _PathPart(segment, operation, ++classIndex));

            currentBuildList.add(pathPart);
            if (loopIndex < pathList.length - 1) flatList.add(pathPart);

            if (loopIndex == 0 && loopIndex < pathList.length - 1)
              bundleList.add(pathPart);

            currentBuildList = pathPart.next;

            if (!pathPart.hasOperation)
              pathPart.hasOperation = loopIndex == pathList.length - 1;

            loopIndex++;
          });
        });
      });

      bundleList.forEach((pathPart) {
        String className =
            '_${pathPart.segment[0].toUpperCase()}${pathPart.segment.substring(1)}${pathPart.classIndex}';

        buffer.writeln(
            '$className get ${pathPart.segment} => const $className();');
      });

      buffer.writeln('}');
    });

    flatList.forEach((pathPart) {
      var enumMap = <String, List<String>>{};
      var className =
          '_${pathPart.segment[0].toUpperCase()}${pathPart.segment.substring(1)}${pathPart.classIndex}';

      buffer.writeln('class $className {');

      buffer.writeln('const $className();');

      pathPart.next.forEach((nextPathPart) {
        if (nextPathPart.next.isNotEmpty) {
          var className =
              '_${nextPathPart.segment[0].toUpperCase()}${nextPathPart.segment.substring(1)}${nextPathPart.classIndex}';

          buffer.writeln(
              '$className get ${nextPathPart.segment} => const $className();');
        }

        if (nextPathPart.hasOperation) {
          if (nextPathPart.operation.description != null) {
            buffer.writeln('/// ${nextPathPart.operation.description}');
          }

          nextPathPart.operation.parameters
              .where((parameter) =>
                  parameter.values != null &&
                  parameter.values.containsKey('enum'))
              .forEach((parameter) => enumMap.putIfAbsent(
                  '${className}_${parameter.name}',
                  () => parameter.values['enum']?.cast<String>()));

          if (nextPathPart.operation.responseContentType ==
              'application/json') {
            buffer.writeln('Future<T> ${nextPathPart.segment}<T, S>(');
          } else {
            buffer.writeln('Future<String> ${nextPathPart.segment}(');
          }

          var pathParameters = nextPathPart.operation.parameters
              .where((parameter) => parameter.location == 'path')
              .toList(growable: false);
          var otherParameters = nextPathPart.operation.parameters
              .where((parameter) => parameter.location != 'path')
              .toList(growable: true);

          if (nextPathPart.operation.responseContentType ==
              'application/json') {
            otherParameters.add(null);
          }

          buffer.writeln(pathParameters
              .map((parameter) =>
                  'final ${_toReturnType(className, parameter)} ${parameter.name}')
              .join(','));

          if (pathParameters.isNotEmpty && otherParameters.isNotEmpty)
            buffer.writeln(',');

          if (otherParameters.isNotEmpty) buffer.writeln('{');

          buffer.writeln(otherParameters.map((parameter) {
            if (parameter == null) {
              return 'T convert(S data)';
            } else if (parameter.isRequired) {
              return '${_toReturnType(className, parameter)} ${parameter.name}';
            }

            return '${_toReturnType(className, parameter)} ${parameter.name}';
          }).join(','));

          if (otherParameters.isNotEmpty) buffer.writeln('}');

          buffer.writeln(') async {');

          if (nextPathPart.operation.responseContentType ==
              'application/json') {
            buffer.writeln('convert ??= (dynamic data) => data as T;');
          }

          final extraPathParameters = new List<Parameter>.from(pathParameters);

          new RegExp(r'{([^}]+)}')
              .allMatches(nextPathPart.operation.path)
              .map((match) => match.group(1))
              .forEach((pathParam) => extraPathParameters
                  .removeWhere((parameter) => parameter.name == pathParam));

          var url =
              "'\$url${nextPathPart.operation.path.replaceAllMapped(new RegExp(r'{([^}]+)}'), (Match match) => '\$${match.group(1)}')}";

          if (extraPathParameters.isNotEmpty) {
            url +=
                '/${extraPathParameters.map((parameter) => '\$${parameter.name}').join('/')}';
          }

          final queryParameters = nextPathPart.operation.parameters
              .where((parameter) => parameter.location == 'query')
              .toList(growable: false);
          final bodyParameters = nextPathPart.operation.parameters
              .where((parameter) =>
                  parameter.location == 'body' ||
                  parameter.location == 'formData')
              .toList(growable: false);

          if (queryParameters.isNotEmpty)
            url += '?${queryParameters.map((Parameter parameter) {
              if (parameter.collectionFormat == 'multi') {
                if (parameter.values.containsKey('enum')) {
                  return '''\${${parameter.name}.map((entry) => '${parameter.name}=\${entry.toJson()}').join('&')}''';
                }

                return '''\${${parameter.name}.map((entry) => '${parameter.name}=\${entry.toString()}').join('&')}''';
              }

              return '${parameter.name}=\$${parameter.name}';
            }).join('&')}';

          url += "'";

          final withCredentials = (options.config['useCredentials'] == true);
          final String logging = options.config['middleware']['logging'];

          if (logging != null) {
            buffer.writeln(
                '''$logging({'path': '${nextPathPart.operation.path}', 'operation': '${nextPathPart.operation.name}', 'remoteMethodName': '${nextPathPart.operation.method}', 'parameters': {${nextPathPart.operation.parameters.map((Parameter parameter) => "'${parameter.name}':'\$${parameter.name}'").join(',')}}});''');
          }

          buffer.writeln('// ignore: omit_local_variable_types');
          buffer.writeln(
              'final Future<HttpRequest> Function(Map<String, String>) request = (Map<String, String> extraHeaders) async { ');

          if (options.config.containsKey('headersFactory')) {
            buffer.writeln(
                'final headers = await ${options.config['headersFactory']}();');
            buffer.writeln(
                "headers['Content-Type'] = '${nextPathPart.operation.requestContentType}';");
          } else {
            buffer.writeln(
                "final headers = {'Content-Type':'${nextPathPart.operation.requestContentType}'};");
          }

          buffer.writeln('headers.addAll(extraHeaders);');

          buffer.writeln('return ${options.config['urlFactory']}()');

          buffer.writeln('.then((url) => ');

          if (nextPathPart.operation.requestContentType.toLowerCase() ==
                  'multipart/form-data' &&
              bodyParameters.isNotEmpty) {
            final bodyData =
                bodyParameters.map((parameter) => parameter.name).first;

            buffer.writeln('$bodyData != null ? ');

            buffer.writeln(
                '''HttpRequest.request($url, method: '${nextPathPart.operation.name.toUpperCase()}', withCredentials: $withCredentials, sendData: ${bodyParameters.map((Parameter parameter) => parameter.name).first})''');

            buffer.writeln(' : ');
            buffer.writeln(
                ''' HttpRequest.request($url, method: '${nextPathPart.operation.name.toUpperCase()}', withCredentials: $withCredentials ''');
          } else {
            buffer.writeln(
                ''' HttpRequest.request($url, method: '${nextPathPart.operation.name.toUpperCase()}', withCredentials: $withCredentials ''');
          }

          if (nextPathPart.operation.requestContentType.toLowerCase() ==
                  'multipart/form-data' &&
              bodyParameters.isNotEmpty) {
          } else {
            buffer.writeln(", requestHeaders: headers");
          }

          if (bodyParameters.isNotEmpty &&
              nextPathPart.operation.name != 'get') {
            if (nextPathPart.operation.requestContentType ==
                'application/json') {
              buffer.writeln(
                  ', sendData: json.encode(${bodyParameters.map((Parameter parameter) => parameter.name).first})');
            } else {
              buffer.writeln(
                  ', sendData: ${bodyParameters.map((Parameter parameter) => parameter.name).first}');
            }
          }

          buffer.writeln('));};');
          buffer.writeln('return request(const <String, String>{})');

          final String runOnStatus =
              options.config['middleware']['retryOnStatus'];
          final String runOnError =
              options.config['middleware']['retryOnError'];
          final String requestHandler =
              options.config['middleware']['requestHandler'];
          final String onError = options.config['middleware']['error'];

          if (requestHandler != null) {
            buffer.writeln('.then($requestHandler)');
          }

          if (runOnStatus != null && runOnError != null) {
            buffer.writeln(
                '.then($runOnStatus(request), onError: $runOnError(request))');
          } else if (runOnStatus != null) {
            buffer.writeln('.then($runOnStatus(request))');
          } else if (runOnError != null) {
            buffer.writeln(
                '.then((request) => request, onError: $runOnError(request))');
          }

          if (onError != null)
            buffer.writeln('.then($onError, onError: (dynamic _) {})');
          /*else if (!(const <String>[
            'LOGGING',
            'RETRY_ON_STATUS',
            'RETRY_ON_ERROR',
            'REQUEST_HANDLER'
          ].contains(event))) buffer.writeln('.then($method)');*/

          buffer.writeln('.then((request) => request?.responseText)');

          if (nextPathPart.operation.responseContentType ==
              'application/json') {
            buffer.writeln(
                '.then((data) => data != null ? convert(json.decode(data) as S) : null);');
          } else {
            buffer.writeln(';');
          }

          buffer.writeln('}');
        }
      });

      enumMap.forEach((K, V) {
        buffer.writeln('$K get ${K.split('_').last}Enums => const $K._(null);');
      });

      buffer.writeln('}');

      enumMap.forEach((K, V) {
        buffer.writeln('class $K {');
        buffer.writeln('final _value;');
        buffer.writeln('const $K._(this._value);');

        V?.forEach((enumValue) {
          buffer.writeln("$K get $enumValue => const $K._('$enumValue');");
        });

        buffer.writeln('@override String toString() => _value;');
        buffer.writeln('String toJson() => _value;');

        buffer.writeln('}');
      });
    });

    return buffer.toString();

    return null;
  }

  String _toReturnType(String className, Parameter parameter) {
    if (parameter.returnType == 'Map') return 'Map<String, dynamic>';
    if (parameter.values == null) return parameter.returnType;

    if (!parameter.values.containsKey('enum'))
      return '${parameter.returnType}<${Parameter('', false, '', parameter.values['type'], {}, '').returnType}>';

    return '${parameter.returnType}<${className}_${parameter.name}>';
  }

  String _bundleNameToClassName(Bundle bundle) {
    final camelCased = bundle.name.replaceAllMapped(
        new RegExp(r'-([\w]{1})'), (match) => match.group(1).toUpperCase());

    return 'Taurus${camelCased[0].toUpperCase()}${camelCased.substring(1)}Service';
  }

  List<String> _pathToMethodName(Path path, Operation operation) {
    final parts = path.name.split('/');

    var transformed =
        parts.where((segment) => segment.isNotEmpty).map((segment) {
      if (segment[0] == '{') {
        String unwrapped = segment.substring(1, segment.length - 1);

        return 'with${unwrapped[0].toUpperCase()}${unwrapped.substring(1)}';
      }

      return segment;
    }).toList();

    transformed.add(
        'do${operation.name[0].toUpperCase()}${operation.name.substring(1)}');

    return transformed;
  }

  const SwaggerGenerator(this.options);
}

class _PathPart {
  final String segment;
  final Operation operation;
  final int classIndex;
  final Set<_PathPart> next = new Set<_PathPart>();

  bool hasOperation = false;

  _PathPart(String segment, this.operation, this.classIndex)
      : this.segment = segment == 'new' ? 'create' : segment;

  String toString() => '$segment.$next';
}
