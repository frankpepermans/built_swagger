import 'package:built_swagger/src/domain/operation.dart';

class Path {
  final String name;
  final Iterable<Operation> operations;

  Path(this.name, this.operations) {
    //print(name);
  }
}