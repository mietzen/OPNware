// Same-origin bootstrap worker for the vendored Monaco editor.
//
// Monaco's default worker factory creates blob: workers containing
// `importScripts(<worker>); postMessage({type:'vscode-worker-ready'})`.
// OPNsense's CSP refuses blob: workers (script-src 'self' — no
// worker-src blob:), and the main-thread fallback freezes the editor on
// model changes. This classic worker replicates the blob contract with
// same-origin files: load the AMD loader, boot the editor worker module,
// then announce readiness the way Monaco expects.
//
// Module ids like "vs/editor/editor.worker" already carry the "vs" prefix,
// so the baseUrl is the vendor root WITHOUT it.
importScripts('/ui/js/vendor/monaco/vs/loader.js');
require.config({ baseUrl: '/ui/js/vendor/monaco' });
require(['vs/editor/editor.worker'], function() {
    globalThis.postMessage({ type: 'vscode-worker-ready' });
});
