enum RunOn { ERROR, LOGGING }

class Remote {
  final String url;

  const Remote(this.url);
}

class Middleware {
  final Function method;
  final RunOn runOn;

  const Middleware(this.method, this.runOn);
}
