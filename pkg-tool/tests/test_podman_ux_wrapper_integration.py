"""Tests for os-podman wrapper, inspect modal, and CLI configuration."""

import subprocess
import tempfile
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parents[2]
PODMAN_SRC = ROOT_DIR / "pkgs" / "os-podman" / "src"
WRAPPER_SCRIPT = PODMAN_SRC / "usr" / "local" / "bin" / "podman-wrapper"


def test_podman_wrapper_script_logic():
    assert WRAPPER_SCRIPT.exists()
    assert WRAPPER_SCRIPT.stat().st_mode & 0o111, "podman-wrapper must be executable"

    with tempfile.TemporaryDirectory() as tmpdir:
        tmp_path = Path(tmpdir)

        # Create mock sudo and mock podman
        log_file = tmp_path / "calls.log"

        mock_sudo = tmp_path / "sudo"
        mock_sudo.write_text(f"""#!/bin/sh
echo "SUDO: $@" >> "{log_file}"
exec "$@"
""")
        mock_sudo.chmod(0o755)

        mock_podman = tmp_path / "podman"
        mock_podman.write_text(f"""#!/bin/sh
echo "PODMAN: $@" >> "{log_file}"
""")
        mock_podman.chmod(0o755)

        # Create test wrapper pointing to mock binaries
        wrapper_copy = tmp_path / "podman-wrapper"
        wrapper_content = WRAPPER_SCRIPT.read_text()
        wrapper_content = wrapper_content.replace(
            "PODMAN=/usr/local/bin/podman", f"PODMAN={mock_podman}"
        ).replace(
            "SUDO=/usr/bin/sudo", f"SUDO={mock_sudo}"
        )
        wrapper_copy.write_text(wrapper_content)
        wrapper_copy.chmod(0o755)

        # 1. Test run without --platform -> adds --platform linux/amd64
        subprocess.run([str(wrapper_copy), "run", "-d", "alpine"], check=True)
        lines = log_file.read_text().strip().splitlines()
        assert any("PODMAN: run --platform linux/amd64 -d alpine" in line for line in lines)

        # 2. Test pull with explicit --platform -> preserves it, no duplicate
        log_file.unlink()
        subprocess.run([str(wrapper_copy), "pull", "--platform", "linux/arm64", "alpine"], check=True)
        lines = log_file.read_text().strip().splitlines()
        assert any("PODMAN: pull --platform linux/arm64 alpine" in line for line in lines)
        assert not any("linux/amd64" in line for line in lines)

        # 3. Test build with --platform=linux/riscv64 -> preserves it
        log_file.unlink()
        subprocess.run([str(wrapper_copy), "build", "--platform=linux/riscv64", "."], check=True)
        lines = log_file.read_text().strip().splitlines()
        assert any("PODMAN: build --platform=linux/riscv64 ." in line for line in lines)

        # 4. Test ps -a (non-wrapping command) -> passes through unmodified
        log_file.unlink()
        subprocess.run([str(wrapper_copy), "ps", "-a"], check=True)
        lines = log_file.read_text().strip().splitlines()
        assert any("PODMAN: ps -a" in line for line in lines)
        assert not any("--platform" in line for line in lines)


def test_dashboard_inspect_modal_and_theme_elements():
    dash_file = PODMAN_SRC / "opnsense" / "mvc" / "app" / "views" / "OPNsense" / "Podman" / "dashboard.volt"
    assert dash_file.exists()
    content = dash_file.read_text()

    # XTerm Theme blend-in
    assert "background: '#1e1e1e'" in content
    assert "cursor: '#5af78e'" in content

    # Inspect modal structured elements
    assert "renderInspectModal" in content
    assert "jsonToYaml" in content
    assert "modal-inspect-raw" in content
    assert "btn_inspect_raw_yaml" in content
    assert "btn_copy_inspect_raw" in content
    assert "Container Name" in content
    assert "Network & Ports" in content
    assert "Storage & Mounts" in content
    assert "Security & Runtime" in content
    assert "Environment & Execution" in content
    assert 'class="panel-collapse collapse"' in content
    assert "Digest/ID" in content


def test_alias_and_cshrc_block_manipulation():
    begin_marker = "# BEGIN OPNWARE PODMAN ALIASES"
    end_marker = "# END OPNWARE PODMAN ALIASES"

    # 1. Existing cshrc with other content
    initial_cshrc = "# System cshrc\nset prompt = '%n@%m:%~%# '\n"
    aliases = [
        "alias podman /usr/local/bin/podman-wrapper",
        "alias docker /usr/local/bin/podman-wrapper",
    ]
    block = f"{begin_marker}\n" + "\n".join(aliases) + f"\n{end_marker}\n"
    updated_cshrc = initial_cshrc.strip() + "\n\n" + block

    assert begin_marker in updated_cshrc
    assert "alias podman /usr/local/bin/podman-wrapper" in updated_cshrc
    assert "alias docker /usr/local/bin/podman-wrapper" in updated_cshrc

    # 2. Test removal/update of block
    import re
    pattern = r"\n?" + re.escape(begin_marker) + r".*?" + re.escape(end_marker) + r"\n?"
    cleaned_cshrc = re.sub(pattern, "", updated_cshrc, flags=re.DOTALL).strip()
    assert cleaned_cshrc == initial_cshrc.strip()
    assert begin_marker not in cleaned_cshrc

