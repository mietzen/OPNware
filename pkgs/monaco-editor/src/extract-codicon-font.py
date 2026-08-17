#!/usr/bin/env python3
"""Extract the base64-inlined codicon font from monaco's editor.main.css (ticket #272).

Monaco's min build inlines the codicon font as a data: URL inside the single
@font-face in vs/editor/editor.main.css. OPNsense CSP is
`default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval';
style-src 'self' 'unsafe-inline' 'unsafe-eval'` — there is no font-src, so
fonts fall back to default-src 'self', which blocks data: font URLs. The
Codicon FontFace ends in status `error` and folding chevrons render as literal
EAB4 glyphs.

The CSS is loaded via <link rel="stylesheet">, so a RELATIVE url() in the CSS
resolves against the CSS file location (/ui/js/vendor/monaco/vs/editor/),
which is same-origin and CSP-allowed. This codemod decodes the inlined base64
into a same-origin .ttf at monaco's canonical upstream location
(vs/base/browser/ui/codicons/codicon/codicon.ttf) and rewrites the @font-face
src: to reference it relatively.

Applied at build time (not checked in) so the payload is always patched — the
patch can never drift from the fetched tree. The codemod FAILS the build if the
expected pristine pattern is absent, which is the safety gate for version bumps
that change the minified shape.

Run: python3 extract-codicon-font.py <vendor_dir>
Vendor dir layout: <dir>/monaco/vs/... (same as the built payload).
"""

import base64
import binascii
import re
import sys
from pathlib import Path

CSS_PATH = "monaco/vs/editor/editor.main.css"
TTF_REL = "../base/browser/ui/codicons/codicon/codicon.ttf"
TTF_PATH = "monaco/vs/base/browser/ui/codicons/codicon/codicon.ttf"

# The min editor.main.css is a single line with exactly one @font-face:
#   @font-face{font-family:codicon;font-display:block;src:url(data:font/ttf;base64,AAAA...)}
# Tolerant of optional whitespace between tokens; the base64 is captured
# non-greedily up to the closing `)`.
FONT_FACE_RE = re.compile(
    r"@font-face\s*\{\s*font-family\s*:\s*codicon\s*;"
    r".*?src\s*:\s*url\(\s*data:font/ttf;base64,([A-Za-z0-9+/=]+)\s*\)",
    re.DOTALL,
)


def extract_font(css: str) -> bytes:
    """Return the decoded ttf bytes from the codicon @font-face.

    Raises SystemExit if the expected pristine pattern is missing.
    """
    m = FONT_FACE_RE.search(css)
    if not m:
        raise SystemExit(
            "extract-codicon-font: codicon @font-face with data:font/ttf not found "
            f"in {CSS_PATH} — the monaco build may have changed its minified shape"
        )
    try:
        ttf = base64.b64decode(m.group(1), validate=True)
    except (binascii.Error, ValueError) as exc:
        raise SystemExit(f"extract-codicon-font: invalid base64 in {CSS_PATH}: {exc}")
    if not ttf.startswith(b"\x00\x01"):
        raise SystemExit(
            f"extract-codicon-font: decoded data does not start with TTF magic "
            f"(0x0001) in {CSS_PATH}"
        )
    return ttf


def patch(vendor_dir: Path) -> None:
    css_path = vendor_dir / CSS_PATH
    if not css_path.is_file():
        raise SystemExit(f"extract-codicon-font: {CSS_PATH} not found in {vendor_dir}")

    css = css_path.read_text()
    if "data:font/ttf" not in css:
        print(f"extract-codicon-font: {CSS_PATH} already patched (no data:font/ttf), skipping")
        return

    ttf = extract_font(css)

    ttf_path = vendor_dir / TTF_PATH
    ttf_path.parent.mkdir(parents=True, exist_ok=True)
    ttf_path.write_bytes(ttf)
    ttf_path.chmod(0o644)

    # Replace the data: url with the relative same-origin url.
    new_css = re.sub(
        r"url\(\s*data:font/ttf;base64,[A-Za-z0-9+/=]+\s*\)",
        f"url({TTF_REL})",
        css,
        count=1,
    )

    if "data:font/ttf" in new_css:
        raise SystemExit(
            f"extract-codicon-font: data:font/ttf still present in {CSS_PATH} after rewrite"
        )

    css_path.write_text(new_css)
    print(f"extract-codicon-font: wrote {TTF_PATH} ({len(ttf)} bytes)")
    print(f"extract-codicon-font: rewrote @font-face src: -> url({TTF_REL}) in {CSS_PATH}")


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: extract-codicon-font.py <vendor_dir>")
    vendor_dir = Path(sys.argv[1])
    if not vendor_dir.is_dir():
        raise SystemExit(f"vendor dir not found: {vendor_dir}")

    patch(vendor_dir)
    print("extract-codicon-font: ok")


if __name__ == "__main__":
    main()
