import importlib.util
import shlex
import stat
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location(
    "research_env", Path(__file__).with_name("init-deep-research-env.py")
)
assert spec and spec.loader
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ResearchEnvironmentTests(unittest.TestCase):
    def test_upgrade_preserves_existing_key_and_is_idempotent(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "runtime.env"
            path.write_text("DEEP_RESEARCH_RUNTIME_API_KEY=existing-test-key\n")
            environment = {
                "SAKURA_AI_ACCOUNT_TOKENS": "first-test-token,second-test-token"
            }
            module.initialize(path, environment)
            first = path.read_bytes()
            values = dict(
                shlex.split(line)[0].split("=", 1)
                for line in first.decode().splitlines()
            )
            self.assertEqual(
                values["DEEP_RESEARCH_RUNTIME_API_KEY"], "existing-test-key"
            )
            self.assertEqual(values["SAKURA_AI_ACCOUNT_IDS"], "account-1,account-2")
            self.assertEqual(len({values[name] for name in module.KEYS}), 3)
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
            module.initialize(path, environment)
            self.assertEqual(path.read_bytes(), first)
            with self.assertRaises(ValueError):
                module.initialize(
                    path, {"SAKURA_AI_ACCOUNT_TOKENS": "first-test-token"}
                )
            self.assertEqual(path.read_bytes(), first)

    def test_invalid_configuration_does_not_write_credentials(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "runtime.env"
            environment = {name: "duplicate-test-key" for name in module.KEYS}
            environment["SAKURA_AI_ACCOUNT_TOKENS"] = "test-token"
            with self.assertRaises(ValueError):
                module.initialize(path, environment)
            self.assertFalse(path.exists())


if __name__ == "__main__":
    unittest.main()
