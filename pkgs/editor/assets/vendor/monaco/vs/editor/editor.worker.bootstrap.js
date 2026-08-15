// Same-origin bootstrap worker for the vendored Monaco editor.
//
// Monaco's default worker factory creates blob: workers, which the OPNsense
// CSP refuses (script-src 'self' 'unsafe-inline' 'unsafe-eval' — no
// worker-src blob:). The main-thread fallback then freezes the UI whenever
// the model changes. This classic worker (no { type: 'module' }) loads the
// vendored AMD loader and boots the real editor worker from the same
// origin, which the CSP allows. The volt patches
// MonacoEnvironment.getWorker to return `new Worker(this file)`.
//
// The loader resolves module ids against its own location, so "vs/..."
// ids must be re-based to the vendored root explicitly — otherwise
// "vs/editor/editor.worker" resolves relative to this file's directory.
importScripts('/ui/js/vendor/monaco/vs/loader.js');
require.config({ baseUrl: '/ui/js/vendor/monaco/vs' });
require(['vs/editor/editor.worker'], function() {});
