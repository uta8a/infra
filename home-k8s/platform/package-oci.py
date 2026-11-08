#!/usr/bin/env python3
"""公開allowlistのみを単一layer用archiveへ梱包する。publishは行わない。"""
import argparse
import gzip
import json
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile


PLATFORM = Path(__file__).resolve().parent
REPOSITORY = PLATFORM.parents[1]


def public_file(path):
    if path.is_symlink() or not path.is_file():
        raise ValueError(f"regular public file required: {path}")
    return path


def build(package, output):
    output = output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="home-k8s-oci-") as temporary:
        staging = Path(temporary) / "payload"
        staging.mkdir()
        if package == "home-k8s":
            charts = json.loads(public_file(PLATFORM / "charts.json").read_text())
            for component, chart in charts.items():
                directory = staging / component
                (directory / "charts").mkdir(parents=True)
                # JSONはYAMLのサブセット。依存chart名をvaluesのキーにする。
                (directory / "Chart.yaml").write_text(json.dumps({
                    "apiVersion": "v2", "name": f"home-k8s-{component}",
                    "version": "0.1.0", "dependencies": [{
                        "name": chart["chart"], "version": chart["version"],
                        "repository": chart["repository"],
                    }],
                }, indent=2) + "\n")
                values = public_file(PLATFORM / component / "values.yaml").read_text()
                (directory / "values.yaml").write_text(
                    chart["chart"] + ":\n" + "".join("  " + line + "\n" for line in values.splitlines())
                )
                subprocess.run([
                    "helm", "pull", chart["chart"], "--repo", chart["repository"],
                    "--version", chart["version"], "--destination", str(directory / "charts"),
                ], check=True)
                # 描画結果には生成Secretがあるため、配布・ログ出力せず破棄する。
                with (Path(temporary) / "rendered.yaml").open("w") as rendered:
                    subprocess.run([
                        "helm", "template", component, str(directory), "--include-crds",
                        "--namespace", chart["namespace"], "--kube-version", "1.37.1",
                    ], check=True, stdout=rendered)
        else:
            for relative in ("linkding/manifest.yaml", "longhorn/longhorn.yaml"):
                source = public_file(REPOSITORY / "home-k8s-app" / relative)
                target = staging / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(source, target)
        # mtime・所有者などを固定し、同じ入力のarchiveを再現可能にする。
        with output.open("xb") as raw, gzip.GzipFile(fileobj=raw, mode="wb", filename="", mtime=0) as compressed:
            with tarfile.open(fileobj=compressed, mode="w") as archive:
                for path in sorted(staging.rglob("*")):
                    if path.is_file():
                        info = archive.gettarinfo(str(path), arcname=path.relative_to(staging).as_posix())
                        info.uid = info.gid = info.mtime = 0
                        info.uname = info.gname = ""
                        info.mode = 0o644
                        with path.open("rb") as content:
                            archive.addfile(info, content)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("package", choices=("home-k8s", "home-k8s-app"))
    parser.add_argument("output", type=Path)
    arguments = parser.parse_args()
    build(arguments.package, arguments.output)
