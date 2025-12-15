## 0.1.0

- Initial release of `okws_client`.
- Robust reconnection logic with configurable backoff strategies (`LinearBackoff`, `ExponentialBackoff`).
- Support for custom HTTP headers.
- Support for `pingInterval` to keep connections alive.
- Support for `customHttpClient` for advanced configuration (e.g., self-signed certificates).
- Built on top of `dart:io` for native performance and flexibility.
- Simple API with `connect`, `disconnect`, `send`, and state streams.
