class Parameter {
  final String name;
  final bool isRequired;
  final String returnType;
  final String location;

  Parameter(this.name, this.isRequired, this.location, final String returnType)
      : this.returnType = _convertType(returnType) {}

  static String _convertType(final String incomingType) {
    switch (incomingType) {
      case 'string':
        return 'String';
      case 'number':
        return 'num';
      case 'boolean':
        return 'bool';
      default:
        return 'dynamic/*$incomingType*/';
    }
  }
}
