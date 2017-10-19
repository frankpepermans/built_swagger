// Copyright (c) 2017, Frank. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.
import 'dart:async';

import 'package:built_swagger/built_swagger.dart';
import 'package:test/test.dart';

Future<Null> main() async {
  SwaggerService service = new SwaggerService();

  final Blueprint data = await service.fetchDocumentation();

  print(data.bundles.map((_) => _.paths.map((_) => _.operations.length)));
}
