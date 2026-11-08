#!/usr/bin/env python3
"""配布archiveと内部chartを展開し、秘密情報を値を表示せず検査する。"""
import argparse
import json
import re
from pathlib import Path
import subprocess
import tarfile
import tempfile

PLATFORM = Path(__file__).resolve().parent


def extract(archive_path, destination):
    with tarfile.open(archive_path) as archive:
        for member in archive.getmembers():
            if not (member.isfile() or member.isdir()):
                raise ValueError("archive must not contain links or special files")
            if Path(member.name).is_absolute() or ".." in Path(member.name).parts:
                raise ValueError("archive path escapes destination")
        archive.extractall(destination, filter="data")


def audit(package, archive_path):
    charts = json.loads((PLATFORM / "charts.json").read_text())
    expected = set()
    if package == "home-k8s":
        for component, chart in charts.items():
            expected.update((f"{component}/Chart.yaml", f"{component}/values.yaml",
                             f"{component}/charts/{chart['chart']}-{chart['version']}.tgz"))
    else:
        expected.update(("linkding/manifest.yaml", "longhorn/longhorn.yaml"))
    with tarfile.open(archive_path) as archive:
        names = archive.getnames()
        if len(names) != len(expected) or set(names) != expected:
            raise ValueError("archive members differ from public allowlist")
    with tempfile.TemporaryDirectory(prefix="oci-audit-") as temporary:
        root = Path(temporary)
        payload = root / "payload"
        extract(archive_path, payload)
        seen = set()
        for _ in range(10):
            pending = [path for path in payload.rglob("*.tgz") if path not in seen]
            if not pending:
                break
            for path in pending:
                extract(path, path.parent / (path.name + "-unpacked"))
                seen.add(path)
        else:
            raise ValueError("nested chart depth exceeded")
        # 上流chartの省略記号だけのコメント例を、検査用コピー上でのみ無害化する。
        # 3行すべてが完全一致した場合のみ置換し、他の値・行番号は維持する。
        # gitleaks側のファイル除外は使わず、実キー形式は同じファイルでも検出する。
        placeholder = re.compile(
            r"(?m)^ *# +-----BEGIN OPENSSH PRIVATE KEY-----\r?\n"
            r" *# +\.\.\.\r?\n *# +-----END OPENSSH PRIVATE KEY----- *$"
        )
        for values in payload.glob("argocd/charts/*-unpacked/argo-cd/values.yaml"):
            text = values.read_text()
            normalized, count = placeholder.subn("#\n#\n#", text)
            if count:
                values.write_text(normalized)
                print(f"Normalized {count} exact commented placeholders in scan copy")
        report = root / "report.json"
        scan = subprocess.run([
            "gitleaks", "dir", str(payload), "--redact=100", "--no-banner",
            "--config", str(PLATFORM / "gitleaks.toml"),
            "--report-format", "json", "--report-path", str(report),
        ], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if scan.returncode:
            if report.exists():
                for finding in json.loads(report.read_text()):
                    # Secret / Match は表示しない。
                    print({key: finding.get(key) for key in ("RuleID", "File", "StartLine")})
            raise RuntimeError(f"secret scan failed (exit {scan.returncode}); values suppressed")
        print(f"{package}: allowlist OK; {len(seen)} nested charts extracted; no credentials detected")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("package", choices=("home-k8s", "home-k8s-app"))
    parser.add_argument("archive", type=Path)
    arguments = parser.parse_args()
    audit(arguments.package, arguments.archive)
