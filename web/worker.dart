import 'package:drift/wasm.dart';

// Compiled to `worker.dart.js` by the Flutter web build tool (any `.dart`
// file directly under `web/` is compiled as a separate entrypoint). This is
// drift's shared worker, letting multiple tabs share one database connection
// via SharedWorker/dedicated Worker with graceful fallback.
void main() {
  return WasmDatabase.workerMainForOpen();
}
