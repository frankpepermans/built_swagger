import 'dart:async';

import 'package:analyzer/dart/element/element.dart';
import 'package:source_gen/source_gen.dart';

import 'package:built_swagger/src/infrastructure/swagger_service.dart';
import 'package:built_swagger/src/domain/blueprint.dart';
import 'package:built_swagger/src/domain/bundle.dart';
import 'package:built_swagger/src/domain/operation.dart';
import 'package:built_swagger/src/domain/path.dart';
import 'package:built_swagger/src/domain/parameter.dart';

class SwaggerGenerator extends Generator {
  @override
  Future<String> generate(Element element, _) async {
    if (element is ClassElement) {
      final ElementAnnotation remoteAnnotation = element.metadata.firstWhere(
          (ElementAnnotation annotation) =>
              annotation.toSource().contains('@Remote('),
          orElse: () => null);
      final ElementAnnotation useCredentialsAnnotation = element.metadata
          .firstWhere(
              (ElementAnnotation annotation) =>
                  annotation.toSource().contains('@UseCredentials('),
              orElse: () => null);
      final ElementAnnotation urlFactoryAnnotation = element.metadata
          .firstWhere(
              (ElementAnnotation annotation) =>
                  annotation.toSource().contains('@UrlFactory('),
              orElse: () => null);
      final ElementAnnotation headersFactoryAnnotation = element.metadata
          .firstWhere(
              (ElementAnnotation annotation) =>
                  annotation.toSource().contains('@HeadersFactory('),
              orElse: () => null);

      final Iterable<ElementAnnotation> middlewareAnnotations = element.metadata
          .where((ElementAnnotation annotation) =>
              annotation.toSource().contains('@Middleware('));

      if (remoteAnnotation != null) {
        final String swaggerUrl = new RegExp(r"@Remote\('([^']+)'\)")
            .firstMatch(remoteAnnotation.toSource())
            .group(1);
        final StringBuffer buffer = new StringBuffer();
        final SwaggerService service = new SwaggerService();
        final Blueprint data = await service.fetchDocumentation(swaggerUrl);
        final Set<_PathPart> buildList = new Set<_PathPart>(),
            flatList = new Set<_PathPart>();
        int classIndex = 0;

        buffer.writeln('''import 'dart:async';''');
        buffer.writeln('''import 'dart:convert' show JSON;''');
        buffer.writeln('''import 'dart:html' show FormData, HttpRequest;''');
        buffer.writeln(
            '''import 'package:angular2/angular2.dart' show Injectable, Inject;''');

        final String parentLib =
            new RegExp(r'[^|]+').firstMatch(element.source.fullName).group(0);
        final String parentPath =
            new RegExp(r'\/.+').firstMatch(element.source.fullName).group(0);

        buffer.writeln('''import 'package:$parentLib$parentPath';''');

        buffer.writeln(
            'const List<Type> remoteServices = const <Type>[${data.bundles.map(_bundleNameToClassName).join(',')}];');

        data.bundles.forEach((Bundle bundle) {
          final String bundleClassName = _bundleNameToClassName(bundle);
          final Set<_PathPart> bundleList = new Set<_PathPart>();

          buffer.writeln('@Injectable()');
          buffer.writeln('class $bundleClassName {');

          buffer.writeln();
          buffer.writeln('const $bundleClassName();');

          bundle.paths.forEach((Path path) {
            path.operations.forEach((Operation operation) {
              List<String> pathList = _pathToMethodName(path, operation);
              Set<_PathPart> currentBuildList = buildList;
              int loopIndex = 0;

              pathList.forEach((String segment) {
                segment = segment == 'new' ? 'create' : segment;

                _PathPart pathPart = currentBuildList.firstWhere(
                    (_PathPart pathPart) =>
                        pathPart.segment.compareTo(segment) == 0,
                    orElse: () =>
                        new _PathPart(segment, operation, ++classIndex));

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

          bundleList.forEach((_PathPart pathPart) {
            String className =
                '_${pathPart.segment[0].toUpperCase()}${pathPart.segment.substring(1)}${pathPart.classIndex}';

            buffer.writeln(
                '$className get ${pathPart.segment} => const $className();');
          });

          buffer.writeln('}');
        });

        flatList.forEach((_PathPart pathPart) {
          Map<String, List<String>> enumMap = <String, List<String>>{};
          String className =
              '_${pathPart.segment[0].toUpperCase()}${pathPart.segment.substring(1)}${pathPart.classIndex}';

          buffer.writeln('class $className {');

          buffer.writeln('const $className();');

          pathPart.next.forEach((_PathPart nextPathPart) {
            if (nextPathPart.next.isNotEmpty) {
              String className =
                  '_${nextPathPart.segment[0].toUpperCase()}${nextPathPart.segment.substring(1)}${nextPathPart.classIndex}';

              buffer.writeln(
                  '$className get ${nextPathPart.segment} => const $className();');
            }

            if (nextPathPart.hasOperation) {
              if (nextPathPart.operation.description != null) {
                buffer.writeln('/// ${nextPathPart.operation.description}');
              }

              nextPathPart.operation.parameters
                  .where((Parameter parameter) => parameter.values != null)
                  .forEach((Parameter parameter) => enumMap.putIfAbsent(
                      '${className}_${parameter.name}',
                      () => parameter.values['enum']));

              buffer.writeln('Future<dynamic> ${nextPathPart.segment}(');

              List<Parameter> pathParameters = nextPathPart.operation.parameters
                  .where((Parameter parameter) => parameter.location == 'path')
                  .toList(growable: false);
              List<Parameter> otherParameters = nextPathPart
                  .operation.parameters
                  .where((Parameter parameter) => parameter.location != 'path')
                  .toList(growable: false);

              buffer.writeln(pathParameters
                  .map((Parameter parameter) =>
                      'final ${_toReturnType(className, parameter)} ${parameter.name}')
                  .join(','));

              if (pathParameters.isNotEmpty && otherParameters.isNotEmpty)
                buffer.writeln(',');

              if (otherParameters.isNotEmpty) buffer.writeln('{');

              buffer.writeln(otherParameters.map((Parameter parameter) {
                if (parameter.isRequired) {
                  return 'final ${_toReturnType(className, parameter)} ${parameter.name}';
                }

                return 'final ${_toReturnType(className, parameter)} ${parameter.name}:null';
              }).join(','));

              if (otherParameters.isNotEmpty) buffer.writeln('}');

              buffer.writeln(') async {');

              final List<Parameter> extraPathParameters =
                  new List<Parameter>.from(pathParameters);

              new RegExp(r'{([^}]+)}')
                  .allMatches(nextPathPart.operation.path)
                  .map((Match match) => match.group(1))
                  .forEach((String pathParam) =>
                      extraPathParameters.removeWhere((Parameter parameter) =>
                          parameter.name == pathParam));

              String url =
                  "'\$url${nextPathPart.operation.path.replaceAllMapped(
                  new RegExp(r'{([^}]+)}'), (Match match) => '\$${match.group(1)}')}";

              if (extraPathParameters.isNotEmpty) {
                url +=
                    '/${extraPathParameters.map((Parameter parameter) => '\$${parameter.name}').join('/')}';
              }

              final List<Parameter> queryParameters = nextPathPart
                  .operation.parameters
                  .where((Parameter parameter) => parameter.location == 'query')
                  .toList(growable: false);
              final List<Parameter> bodyParameters = nextPathPart
                  .operation.parameters
                  .where((Parameter parameter) =>
                      parameter.location == 'body' ||
                      parameter.location == 'formData')
                  .toList(growable: false);

              if (queryParameters.isNotEmpty)
                url += '?${queryParameters.map((Parameter parameter) {
                if (parameter.collectionFormat == 'multi') {
                  return '''\${${parameter.name}.map((${className}_${parameter.name} entry) => '${parameter.name}=\${entry.toJson()}').join('&')}''';
                }

                return '${parameter.name}=\$${parameter.name}';
                    }).join('&')}';

              url += "'";

              final withCredentials = (useCredentialsAnnotation != null);

              middlewareAnnotations.forEach((ElementAnnotation annotation) {
                final String method =
                    new RegExp(r"@Middleware\((\w+), RunOn.(\w+)\)")
                        .firstMatch(annotation.toSource())
                        .group(1);

                final String event =
                    new RegExp(r"@Middleware\((\w+), RunOn.(\w+)\)")
                        .firstMatch(annotation.toSource())
                        .group(2);

                if (event == 'LOGGING') {
                  buffer.writeln(
                      '''$method(<String, dynamic>{'path': '${nextPathPart.operation.path}', 'operation': '${nextPathPart.operation.name}', 'remoteMethodName': '${nextPathPart.operation.method}', 'parameters': <String, dynamic>{${nextPathPart.operation.parameters.map((Parameter parameter) => "'${parameter.name}':'\$${parameter.name}'").join(',')}}});''');
                }
              });

              final String createUrlMethod =
                  new RegExp(r"@UrlFactory\(([^\)]+)\)")
                      .firstMatch(urlFactoryAnnotation.toSource())
                      .group(1);

              if (headersFactoryAnnotation != null) {
                final String createHeadersMethod =
                    new RegExp(r"@HeadersFactory\(([^\)]+)\)")
                        .firstMatch(headersFactoryAnnotation.toSource())
                        .group(1);

                buffer.writeln(
                    'final Map<String, String> headers = await $createHeadersMethod();');
                buffer.writeln(
                    "headers['Content-Type'] = '${nextPathPart.operation.requestContentType}';");
              } else {
                buffer.writeln(
                    "final Map<String, String> headers = const <String, String>{'Content-Type':'${nextPathPart.operation.requestContentType}'};");
              }

              buffer.writeln('return $createUrlMethod()');

              buffer.writeln('.then<dynamic>((String url) => ');

              if (nextPathPart.operation.requestContentType.toLowerCase() ==
                      'multipart/form-data' &&
                  bodyParameters.isNotEmpty) {
                final String bodyData = bodyParameters
                    .map((Parameter parameter) => parameter.name)
                    .first;

                buffer.writeln('$bodyData != null ? ');

                buffer.writeln(
                    '''HttpRequest.request($url, method: '${nextPathPart.operation.name.toUpperCase()}', withCredentials: $withCredentials, sendData: ${bodyParameters.map((Parameter parameter) => parameter.name).first})''');

                buffer.writeln(
                    '.then((HttpRequest response) => response.responseText)');
                if (nextPathPart.operation.responseContentType ==
                    'application/json') {
                  buffer.writeln('.then<dynamic>((String data) => data != null ? JSON.decode(data) : null)');
                }

                buffer.writeln(' : ');
                buffer.writeln(''' HttpRequest.request($url, method: '${nextPathPart.operation.name.toUpperCase()}', withCredentials: $withCredentials ''');
              } else {
                buffer.writeln(''' HttpRequest.request($url, method: '${nextPathPart.operation.name.toUpperCase()}', withCredentials: $withCredentials ''');
              }

              if (nextPathPart.operation.requestContentType.toLowerCase() ==
                      'multipart/form-data' &&
                  bodyParameters.isNotEmpty) {} else {
                buffer.writeln(", requestHeaders: headers");
              }

              if (bodyParameters.isNotEmpty &&
                  nextPathPart.operation.name != 'get') {
                if (nextPathPart.operation.requestContentType ==
                    'application/json') {
                  buffer.writeln(
                      ', sendData: JSON.encode(${bodyParameters.map((Parameter parameter) => parameter.name).first})');
                } else {
                  buffer.writeln(
                      ', sendData: ${bodyParameters.map((Parameter parameter) => parameter.name).first}');
                }
              }

              buffer.writeln(')');

              middlewareAnnotations.forEach((ElementAnnotation annotation) {
                final String method =
                    new RegExp(r"@Middleware\((\w+), RunOn.(\w+)\)")
                        .firstMatch(annotation.toSource())
                        .group(1);

                final String event =
                    new RegExp(r"@Middleware\((\w+), RunOn.(\w+)\)")
                        .firstMatch(annotation.toSource())
                        .group(2);

                if (event == 'ERROR') buffer.writeln('.then($method, onError: (_) {})');
                else if (event != 'LOGGING') buffer.writeln('.then($method)');
              });

              buffer.writeln(
                  '.then<String>((HttpRequest request) => request?.responseText)');

              if (nextPathPart.operation.responseContentType ==
                  'application/json') {
                buffer.writeln('.then<dynamic>((String data) => data != null ? JSON.decode(data) : null));');
              } else {
                buffer.writeln(');');
              }

              buffer.writeln('}');
            }
          });

          enumMap.forEach((String K, List<String> V) {
            buffer.writeln(
                '$K get ${K.split('_').last}Enums => const $K._(null);');
          });

          buffer.writeln('}');

          enumMap.forEach((String K, List<String> V) {
            buffer.writeln('class $K {');
            buffer.writeln('final String _value;');
            buffer.writeln('const $K._(this._value);');

            V?.forEach((String enumValue) {
              buffer.writeln("$K get $enumValue => const $K._('$enumValue');");
            });

            buffer.writeln('@override String toString() => _value;');
            buffer.writeln('String toJson() => _value;');

            buffer.writeln('}');
          });
        });

        return buffer.toString();
      }
    }

    return null;
  }

  String _toReturnType(String className, Parameter parameter) {
    if (parameter.values == null) return parameter.returnType;

    return '${parameter.returnType}<${className}_${parameter.name}>';
  }

  String _bundleNameToClassName(Bundle bundle) {
    final String camelCased = bundle.name.replaceAllMapped(
        new RegExp(r'-([\w]{1})'),
        (Match match) => match.group(1).toUpperCase());

    return 'Taurus${camelCased[0].toUpperCase()}${camelCased.substring(1)}Service';
  }

  List<String> _pathToMethodName(Path path, Operation operation) {
    final List<String> parts = path.name.split('/');

    List<String> transformed = parts
        .where((String segment) => segment.isNotEmpty)
        .map((String segment) {
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

  const SwaggerGenerator();
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
