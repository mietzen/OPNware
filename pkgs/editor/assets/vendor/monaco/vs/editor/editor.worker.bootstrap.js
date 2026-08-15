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
// Module ids like "vs/editor/editor.worker" already carry the "vs" prefix,
// so the baseUrl must be the vendor root WITHOUT it — otherwise the id
// resolves to .../vs/vs/editor/editor.worker.js and the load fails.
importScripts('/ui/js/vendor/monaco/vs/loader.js');
require.config({ baseUrl: '/ui/js/vendor/monaco' });
require(['vs/editor/editor.worker'], function() {});
