#!/usr/bin/env python3
"""Patch the vendored monaco-editor tree for OPNsense CSP (ticket #256).

Monaco's AMD build instantiates its language workers with blob: workers
during editor.main module evaluation. OPNsense CSP refuses blob: workers
(script-src 'self'), and the main-thread fallback freezes the editor on
model changes. The patch makes every worker same-origin through the
shipped editor.worker.bootstrap.js classic worker.

Applied at build time (not checked in) so the payload is always patched —
the patch can never drift from the fetched tree. The vendored file names
that carry the edits are stable (vs/editor/editor.main.js) or matched by
glob (vs/editor-*.js, the hash changes every monaco build).

Run: python3 patch-csp-worker.py <vendor_dir>
Vendor dir layout: <dir>/monaco/vs/... (same as the built payload).
"""

import re
import sys
from pathlib import Path

BOOTSTRAP_URL = "'/ui/js/vendor/monaco/vs/editor/editor.worker.bootstrap.js'"
MARKER = "editor.worker.bootstrap.js"


def patch_editor_main(path: Path) -> None:
    """Strip the four language-worker deps and replace getWorker.

    The pristine AMD define carries the json/css/html/ts worker modules as
    dependencies; each instantiates a blob worker during module evaluation,
    before any MonacoEnvironment override can take effect. Drop the deps and
    point getWorker at the same-origin bootstrap worker unconditionally.
    """
    src = path.read_text()
    if MARKER in src:
        return  # already patched

    # 1. Remove the four worker deps from the define() dependency list.
    deps_pattern = re.compile(
        r'(\["exports",)"(?:\.\./)?(?:json|css|html|ts)\.worker-[^"]*",'
        r'(?:"(?:\.\./)?(?:json|css|html|ts)\.worker-[^"]*",){3}',
    )
    new_src, n_deps = deps_pattern.subn(r'\1', src, count=1)
    if n_deps != 1:
        raise SystemExit(f"patch-csp-worker: editor.main.js worker deps not found ({path})")

    # 2. Drop the four orphaned worker params from the module factory
    #    signature (single-letter minified names after the exports param).
    params_pattern = re.compile(r"\(function\(e,[a-z],[a-z],[a-z],[a-z],")
    new_src, n_params = params_pattern.subn(r"(function(e,", new_src, count=1)
    if n_params != 1:
        raise SystemExit(f"patch-csp-worker: editor.main.js worker params not found ({path})")

    # 3. Replace the MonacoEnvironment.getWorker blob factory.
    env_pattern = re.compile(
        r"self\.MonacoEnvironment=\{getWorker:function\([^)]*\)\{[^}]*\}\};"
        r"(?=function o\()",
    )
    replacement = (
        f"self.MonacoEnvironment={{getWorker:function(){{return new Worker({BOOTSTRAP_URL})}}}};"
    )
    new_src, n_env = env_pattern.subn(replacement, new_src, count=1)
    if n_env != 1:
        raise SystemExit(f"patch-csp-worker: MonacoEnvironment not found ({path})")

    path.write_text(new_src)
    print(f"patched {path} (worker deps stripped, getWorker -> bootstrap)")


def patch_editor_chunk(vendor_dir: Path) -> None:
    """Replace the ESM-path _createWorker in the hashed editor chunk.

    The editor chunk's default worker factory creates blob workers with
    type:"module" (the ESM path ignores MonacoEnvironment.getWorker). Point
    it at the same-origin bootstrap worker; the hash in the filename changes
    every monaco build, so the file is located by glob.
    """
    chunks = sorted(vendor_dir.glob("monaco/vs/editor-*.js"))
    if len(chunks) != 1:
        raise SystemExit(f"patch-csp-worker: expected one vs/editor-*.js chunk, got {len(chunks)}")
    path = chunks[0]
    src = path.read_text()
    if MARKER in src:
        return  # already patched

    pattern = re.compile(
        r"_createWorker\(e\)\{"
        r"(?:[^{}]|\{[^{}]*\})*"  # body may contain one brace level ({name:...})
        r"\}"
    )
    replacement = (
        f"_createWorker(e){{return new Worker({BOOTSTRAP_URL},{{name:e.label}})}}"
    )
    new_src, n = pattern.subn(replacement, src, count=1)
    if n != 1:
        raise SystemExit(f"patch-csp-worker: _createWorker not found ({path})")

    path.write_text(new_src)
    print(f"patched {path.name} (_createWorker -> bootstrap)")


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: patch-csp-worker.py <vendor_dir>")
    vendor_dir = Path(sys.argv[1])
    if not vendor_dir.is_dir():
        raise SystemExit(f"vendor dir not found: {vendor_dir}")

    patch_editor_main(vendor_dir / "monaco/vs/editor/editor.main.js")
    patch_editor_chunk(vendor_dir)
    print("patch-csp-worker: ok")


if __name__ == "__main__":
    main()
