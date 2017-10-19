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
      final ElementAnnotation annotation = element.metadata.firstWhere(
          (ElementAnnotation annotation) =>
              annotation.toSource().contains('@Remote('),
          orElse: () => null);

      if (annotation != null) {
        final String swaggerUrl = new RegExp(r"@Remote\('([^']+)'\)")
            .firstMatch(annotation.toSource())
            .group(1);
        final StringBuffer buffer = new StringBuffer();
        final SwaggerService service = new SwaggerService();
        final Blueprint data = await service.fetchDocumentation(swaggerUrl);
        final Set<_PathPart> buildList = new Set<_PathPart>(),
            flatList = new Set<_PathPart>();
        int classIndex = 0;

        buffer.writeln('''import 'dart:async';''');
        buffer.writeln('''import 'dart:convert' show JSON, JsonEncoder;''');
        buffer.writeln(
            '''import 'package:angular2/angular2.dart' show Injectable, Inject;''');
        buffer.writeln(
            '''import 'package:http/browser_client.dart' show BrowserClient;''');
        buffer.writeln(
            '''import 'package:http/http.dart' as http show Response;''');
        buffer
            .writeln('''import 'package:logging/logging.dart' show Logger;''');
        buffer.writeln(
            '''import 'package:taurus_security/taurus_security.dart' show ConfigExternalizable;''');
        buffer.writeln(
            '''import 'package:xpert_libraries/src/infrastructure/config_service.dart' show ConfigService, Config;''');

        buffer.writeln(
            'const List<Type> remoteServices = const <Type>[${data.bundles.map(_bundleNameToClassName).join(',')}];');

        data.bundles.forEach((Bundle bundle) {
          final String bundleClassName = _bundleNameToClassName(bundle);
          final Set<_PathPart> bundleList = new Set<_PathPart>();

          buffer.writeln('@Injectable()');
          buffer.writeln('class $bundleClassName {');

          buffer.writeln('final ConfigService _configService;');
          buffer.writeln(
              '''final Logger _log = new Logger('$bundleClassName');''');
          buffer.writeln();
          buffer.writeln(
              '$bundleClassName(@Inject(ConfigExternalizable) this._configService);');

          bundle.paths.forEach((Path path) {
            path.operations.forEach((Operation operation) {
              List<String> pathList = _pathToMethodName(path, operation);
              Set<_PathPart> currentBuildList = buildList;
              int loopIndex = 0;

              pathList.forEach((String segment) {
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
                '$className get ${pathPart.segment} => new $className(_configService, _log);');
          });

          buffer.writeln('}');
        });

        flatList.forEach((_PathPart pathPart) {
          String className =
              '_${pathPart.segment[0].toUpperCase()}${pathPart.segment.substring(1)}${pathPart.classIndex}';

          buffer.writeln('class $className {');

          buffer.writeln('final ConfigService _configService;');
          buffer.writeln('final Logger _log;');
          buffer.writeln('$className(this._configService, this._log);');

          pathPart.next.forEach((_PathPart nextPathPart) {
            if (nextPathPart.next.isNotEmpty) {
              String className =
                  '_${nextPathPart.segment[0].toUpperCase()}${nextPathPart.segment.substring(1)}${nextPathPart.classIndex}';

              buffer.writeln(
                  '$className get ${nextPathPart.segment} => new $className(_configService, _log);');
            }

            if (nextPathPart.hasOperation) {
              if (nextPathPart.operation.description != null) {
                buffer.writeln('/// ${nextPathPart.operation.description}');
              }

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
                      'final ${parameter.returnType} ${parameter.name}')
                  .join(','));

              if (pathParameters.isNotEmpty && otherParameters.isNotEmpty)
                buffer.writeln(',');

              if (otherParameters.isNotEmpty) buffer.writeln('{');

              buffer.writeln(otherParameters.map((Parameter parameter) {
                if (parameter.isRequired) {
                  return 'final ${parameter.returnType} ${parameter.name}';
                }

                return 'final ${parameter.returnType} ${parameter.name}:null';
              }).join(','));

              if (otherParameters.isNotEmpty) buffer.writeln('}');

              buffer.writeln(') {');

              String url =
                  "'\${config.api.url}${nextPathPart.operation.path.replaceAllMapped(
                  new RegExp(r'{([^}]+)}'), (Match match) => '\$${match.group(1)}')}";

              final List<Parameter> queryParameters = nextPathPart
                  .operation.parameters
                  .where((Parameter parameter) => parameter.location == 'query')
                  .toList(growable: false);
              final List<Parameter> bodyParameters = nextPathPart
                  .operation.parameters
                  .where((Parameter parameter) => parameter.location == 'body')
                  .toList(growable: false);

              if (queryParameters.isNotEmpty)
                url +=
                    '?${queryParameters.map((Parameter parameter) => '${parameter.name}=\$${parameter.name}').join('&')}';

              url += "'";

              buffer.writeln(
                  'final BrowserClient client = new BrowserClient()..withCredentials = true;');
              buffer.writeln(
                  '''_log.info(new JsonEncoder.withIndent('  ').convert(<String, dynamic>{'path': '${nextPathPart.operation.path}', 'operation': '${nextPathPart.operation.name}', 'remoteMethodName': '${nextPathPart.operation.method}', 'parameters': <String, dynamic>{${nextPathPart.operation.parameters.map((Parameter parameter) => "'${parameter.name}':'\${${parameter.name}}'").join(',')}}}));''');
              buffer.writeln('return _configService.getConfig()');
              buffer.writeln(
                  '.then((Config config) => client.${nextPathPart.operation.name}($url');

              buffer.writeln(
                  ",headers:const <String, String>{'Content-Type':'${nextPathPart.operation.requestContentType}'}");

              if (bodyParameters.isNotEmpty &&
                  nextPathPart.operation.name != 'get') {
                if (nextPathPart.operation.requestContentType ==
                    'application/json') {
                  buffer.writeln(
                      ',body:JSON.encode(${bodyParameters.map((Parameter parameter) => parameter.name).first})');
                } else {
                  buffer.writeln(
                      ',body:${bodyParameters.map((Parameter parameter) => parameter.name).first}');
                }
              }

              buffer.writeln(')');

              buffer
                  .writeln('.then((http.Response response) => response.body)');

              if (nextPathPart.operation.responseContentType ==
                  'application/json') {
                buffer.writeln('.then(JSON.decode));');
              } else {
                buffer.writeln(');');
              }

              buffer.writeln('}');
            }
          });

          buffer.writeln('}');
        });

        return buffer.toString();
      }
    }

    return null;
  }

  String _bundleNameToClassName(Bundle bundle) {
    final String camelCased = bundle.name.replaceAllMapped(
        new RegExp(r'-([\w]{1})'),
        (Match match) => match.group(1).toUpperCase());

    return '${camelCased[0].toUpperCase()}${camelCased.substring(1)}Service';
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
