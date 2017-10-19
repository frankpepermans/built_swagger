import 'package:built_swagger/src/domain/bundle.dart';
import 'package:built_swagger/src/domain/path.dart';
import 'package:built_swagger/src/domain/operation.dart';

class Blueprint {
  final List<Bundle> bundles;

  Blueprint(List<Map<String, String>> tags,
      Map<String, Map<String, Map<String, dynamic>>> paths)
      : this.bundles = tags
            .map((Map<String, String> tag) => tag['name'])
            .map((String name) => new Bundle(name))
            .toList(growable: false) {
    _extractPaths(paths);
  }

  void _extractPaths(Map<String, Map<String, Map<String, dynamic>>> pathsRaw) {
    pathsRaw.forEach((String pathName, Map<String, Map<String, dynamic>> body) {
      List<Operation> operations = <Operation>[];

      body.forEach((String operation, Map<String, dynamic> data) {
        operations
            .add(new Operation(operation, pathName, data['description'], data));
      });

      Path path = new Path(pathName, operations);
      Set<String> relatedResources = new Set.from(path.operations
          .map((Operation operation) => operation.parentResources)
          .expand((List<String> resources) => resources));
      Iterable<Bundle> relatedBundles = bundles
          .where((Bundle bundle) => relatedResources.contains(bundle.name));

      relatedBundles.forEach((Bundle bundle) {
        bundle.paths.add(new Path(
            pathName,
            path.operations.where((Operation operation) =>
                operation.parentResources.contains(bundle.name))));
      });
      //bundles.where((Bundle bundle) => );
    });
  }
}
