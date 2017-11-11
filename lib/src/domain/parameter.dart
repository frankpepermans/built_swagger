class Parameter {
  final String name;
  final bool isRequired;
  final String returnType;
  final Map<String, dynamic> values;
  final String collectionFormat;
  final String location;

  Parameter(String name, this.isRequired, String location,
      final String returnType, this.values, this.collectionFormat)
      : this.location = location,
        this.name = location == 'body' ? 'body' : name,
        this.returnType = _convertType(returnType) {}

  static String _convertType(final String incomingType) {
    switch (incomingType?.toLowerCase()) {
      case 'string':
        return 'String';
      case 'number':
        return 'num';
      case 'boolean':
        return 'bool';
      case 'array':
        return 'Iterable';
      case 'file':
        return 'FormData';
      case 'blob':
        return 'Blob';
      default:
        return 'dynamic/*$incomingType*/';
    }
  }
}
