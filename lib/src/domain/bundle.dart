import 'package:built_swagger/src/domain/path.dart';

class Bundle {
  final String name;
  final List<Path> paths = <Path>[];

  Bundle(this.name) {
    //print(name);
  }
}