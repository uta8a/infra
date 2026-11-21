"""curatedz同期が長期AWS認証情報へ戻らないための構成テスト。"""
from pathlib import Path
import unittest


REPOSITORY = Path(__file__).resolve().parents[2]
MANIFEST = REPOSITORY / "home-k8s-app/curatedz/manifest.yaml"
APPLICATION = REPOSITORY / "home-k8s-app/curatedz/application.example.yaml"


class CuratedzManifestTest(unittest.TestCase):
    def test_sync_uses_roles_anywhere_without_access_keys(self):
        manifest = MANIFEST.read_text()

        self.assertNotIn("AWS_ACCESS_KEY_ID", manifest)
        self.assertNotIn("AWS_SECRET_ACCESS_KEY", manifest)
        self.assertNotIn("access-key-id", manifest)
        self.assertNotIn("secret-access-key", manifest)
        self.assertIn("credential_process = /usr/local/bin/aws_signing_helper", manifest)
        self.assertIn('name: AWS_CONFIG_FILE, value: "/etc/curatedz/aws/config"', manifest)
        self.assertIn('name: AWS_SDK_LOAD_CONFIG, value: "1"', manifest)
        self.assertIn("secretName: curatedz-aws", manifest)
        self.assertIn("{key: tls.crt, path: tls.crt}", manifest)
        self.assertIn("{key: tls.key, path: tls.key}", manifest)

    def test_argocd_project_allows_public_config_map(self):
        application = APPLICATION.read_text()

        self.assertIn('{group: "", kind: ConfigMap}', application)


if __name__ == "__main__":
    unittest.main()
