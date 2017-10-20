class Parameter {
  final String name;
  final bool isRequired;
  final String returnType;
  final Map<String, dynamic> values;
  final String collectionFormat;
  final String location;

  Parameter(this.name, this.isRequired, this.location, final String returnType,
      this.values, this.collectionFormat)
      : this.returnType = _convertType(returnType) {}

  static String _convertType(final String incomingType) {
    switch (incomingType) {
      case 'string':
        return 'String';
      case 'number':
        return 'num';
      case 'boolean':
        return 'bool';
      case 'array':
        return 'Iterable';
      default:
        return 'dynamic/*$incomingType*/';
    }
  }
}
