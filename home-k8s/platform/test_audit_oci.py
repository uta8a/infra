"""秘密情報の例示除外が実キー形式や追加ファイルを通さない回帰テスト。"""
import base64
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import tarfile
import tempfile
import unittest

PLATFORM = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("audit_oci", PLATFORM / "audit-oci.py")
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)


def entry(archive, name, content):
    info = tarfile.TarInfo(name)
    info.size = len(content)
    archive.addfile(info, io.BytesIO(content))


class AuditTest(unittest.TestCase):
    def test_key_in_nested_upstream_values_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            nested = root / "chart.tgz"
            encoded = base64.b64encode(bytes(range(256)) * 4)
            content = (b"key: |\n  -----BEGIN OPENSSH PRIVATE KEY-----\n  " + encoded
                       + b"\n  -----END OPENSSH PRIVATE KEY-----\n")
            with tarfile.open(nested, "w:gz") as archive:
                entry(archive, "argo-cd/values.yaml", content)
            artifact = root / "artifact.tar.gz"
            charts = json.loads((PLATFORM / "charts.json").read_text())
            with tarfile.open(artifact, "w:gz") as archive:
                for name, chart in charts.items():
                    entry(archive, f"{name}/Chart.yaml", b"{}")
                    entry(archive, f"{name}/values.yaml", b"{}")
                    entry(archive, f"{name}/charts/{chart['chart']}-{chart['version']}.tgz", nested.read_bytes())
            with contextlib.redirect_stdout(io.StringIO()):
                with self.assertRaisesRegex(RuntimeError, r"secret scan failed \(exit 1\)"):
                    audit.audit("home-k8s", artifact)

    def test_extra_file_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            artifact = Path(temporary) / "artifact.tar.gz"
            with tarfile.open(artifact, "w:gz") as archive:
                entry(archive, "linkding/manifest.yaml", b"{}")
                entry(archive, "longhorn/longhorn.yaml", b"{}")
                entry(archive, "secrets.yaml", b"{}")
            with self.assertRaisesRegex(ValueError, "public allowlist"):
                audit.audit("home-k8s-app", artifact)


if __name__ == "__main__":
    unittest.main()
