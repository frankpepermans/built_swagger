import 'dart:async';

enum RunOn { RETRY_ON_STATUS, RETRY_ON_ERROR, ERROR, LOGGING, RESOLVE_URL, REQUEST_HANDLER }

typedef Future<Map<String, String>> CreateHeaders();
typedef Future<String> CreateUrl();

class Remote {
  final String url;

  const Remote(this.url);
}

class UseCredentials {
  const UseCredentials();
}

class Middleware {
  final Function method;
  final RunOn runOn;

  const Middleware(this.method, this.runOn);
}

class HeadersFactory {
  final CreateHeaders generator;

  const HeadersFactory(this.generator);
}

class UrlFactory {
  final CreateUrl generator;

  const UrlFactory(this.generator);
}
