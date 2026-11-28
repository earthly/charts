#!/usr/bin/env python3
"""Render Grafana ownership modes and sign-in settings, and exercise the rendered failure behavior.

Requires helm and PyYAML. Run: python3 scripts/test-grafana-lifecycle.py
"""

from pathlib import Path
import os
import select
import signal
import subprocess
import tempfile
import unittest

import yaml

CHART = Path(__file__).resolve().parents[1] / "charts/lunar"
BASE = {
    "grafana": {"url": "http://grafana.example.com"},
    "hub": {"github": {"app": {"owner": "test", "id": 1, "installId": 1}}},
}
DB = {
    "host": "postgres.example.com", "port": 5432, "name": "grafana", "sslMode": "verify-full",
    "user": {"secretName": "backend", "secretKey": "username"},
    "pass": {"secretName": "backend", "secretKey": "password"},
}


def render(hub=None, **grafana):
    values = {**BASE, "grafana": {**BASE["grafana"], **grafana}}
    if hub:
        values["hub"] = {**BASE["hub"], **hub}
    with tempfile.NamedTemporaryFile(mode="w", suffix=".yaml") as file:
        yaml.safe_dump(values, file)
        file.flush()
        return subprocess.run(["helm", "template", "lunar", str(CHART), "-f", file.name],
                              capture_output=True, text=True, timeout=30)


def resource(docs, kind, name):
    return next(doc for doc in docs if doc and doc["kind"] == kind and doc["metadata"]["name"] == name)


def containers(docs):
    pod = resource(docs, "Deployment", "lunar-grafana")["spec"]["template"]["spec"]
    sidecar = next(c for c in pod["containers"] if c["name"] == "provision-reconverge")
    job = resource(docs, "Job", "lunar-grafana-provision")
    return sidecar, job


class GrafanaLifecycleTest(unittest.TestCase):
    def docs(self, **grafana):
        result = render(**grafana)
        self.assertEqual(result.returncode, 0, result.stderr)
        return list(yaml.safe_load_all(result.stdout))

    def test_default_keeps_full_sqlite_provisioning(self):
        sidecar, job = containers(self.docs())
        self.assertIn('/deploy.sh || echo "dashboards reconverge failed"', sidecar["args"][0])
        command = job["spec"]["template"]["spec"]["containers"][0]["args"][0]
        self.assertIn("if /deploy.sh; then exit 0; fi", command)
        self.assertNotIn("--content-only", command)
        self.assertNotIn("--plugins-only", sidecar["args"][0])

    def test_release_splits_local_plugins_from_content(self):
        docs = self.docs(db=DB, replicaCount=2, provisioning={"contentOwner": "release"})
        sidecar, job = containers(docs)
        env = {e["name"]: e for e in sidecar["env"]}
        self.assertEqual(env["GRAFANA_URL"]["value"], "http://localhost:3000")
        self.assertIn("secretKeyRef", env["GRAFANA_USER"]["valueFrom"])
        self.assertIn("secretKeyRef", env["GRAFANA_PASSWORD"]["valueFrom"])
        self.assertFalse(any(k.startswith("LUNAR_HUB_") for k in env))
        self.assertIn("until /deploy.sh --plugins-only; do", sidecar["args"][0])
        self.assertNotIn("grpcurl", sidecar["args"][0])
        self.assertEqual(sidecar["readinessProbe"]["exec"]["command"], ["test", "-f", "/tmp/reconverge-alive"])
        spec = job["spec"]["template"]["spec"]
        command = spec["containers"][0]["args"][0]
        self.assertEqual(command.strip(), "exec /deploy.sh --content-only")
        self.assertEqual(job["metadata"]["annotations"]["helm.sh/hook"], "post-install,post-upgrade")
        self.assertIn("wait-for-deps", [c["name"] for c in spec["initContainers"]])
        self.assertNotIn("volumes", spec)
        self.assertFalse(any("PROVISION_LOCK" in e["name"] for e in spec["containers"][0]["env"]))
        # Actually execute the rendered hook with a failing provisioner, so an
        # accidental error-swallowing wrapper cannot pass a string-only check.
        with tempfile.TemporaryDirectory() as tmp:
            deploy = Path(tmp) / "deploy.sh"
            deploy.write_text('#!/bin/sh\n[ "$1" = --content-only ] || exit 98\nexit 37\n')
            deploy.chmod(0o755)
            result = subprocess.run(["sh", "-c", command.replace("/deploy.sh", str(deploy))])
            self.assertEqual(result.returncode, 37)

    def test_skip_plugins_is_honored_on_each_pod(self):
        docs = self.docs(db=DB, provisioning={"contentOwner": "release", "skipPlugins": True})
        sidecar, _ = containers(docs)
        env = {e["name"]: e for e in sidecar["env"]}
        self.assertEqual(env["SKIP_PLUGINS"]["value"], "true")

    def test_plugin_sidecar_retries_until_success_then_idles(self):
        sidecar, _ = containers(self.docs(db=DB, provisioning={"contentOwner": "release"}))
        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp)
            for name, body in {
                "curl": "exit 0",
                "tail": "echo idle",
                "deploy.sh": '''[ "$1" = --plugins-only ] || exit 98
echo "$PPID" >>"$TEST_WORK/attempts"
[ "$(wc -l <"$TEST_WORK/attempts")" -ge 3 ]''',
                # Check the readiness marker while installation is failing, and
                # record the requested delay without slowing down the test.
                "sleep": '''test -f "$TEST_WORK/alive" || exit 97
echo "$1" >>"$TEST_WORK/delays"''',
            }.items():
                path = work / name
                path.write_text("#!/bin/sh\n" + body + "\n")
                path.chmod(0o755)
            command = sidecar["args"][0].replace("/deploy.sh", str(work / "deploy.sh"))
            command = command.replace("/tmp/reconverge-alive", str(work / "alive"))
            env = {**os.environ, "PATH": f"{work}:{os.environ['PATH']}", "TEST_WORK": str(work)}
            result = subprocess.run(["sh", "-c", command], env=env, capture_output=True, text=True, timeout=5)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.count("idle"), 1)
            self.assertEqual(result.stderr.count("plugin install failed; retrying in 30s"), 2)
            attempts = (work / "attempts").read_text().splitlines()
            self.assertEqual(len(attempts), 3)
            self.assertEqual(len(set(attempts)), 1, "retries must run under the same shell")
            self.assertEqual((work / "delays").read_text().splitlines(), ["30", "30"])

    def test_persistent_plugin_failure_keeps_sidecar_alive_and_ready(self):
        sidecar, _ = containers(self.docs(db=DB, provisioning={"contentOwner": "release"}))
        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp)
            for name, body in {"curl": "exit 0", "deploy.sh": "exit 37"}.items():
                path = work / name
                path.write_text("#!/bin/sh\n" + body + "\n")
                path.chmod(0o755)
            command = sidecar["args"][0].replace("/deploy.sh", str(work / "deploy.sh"))
            command = command.replace("/tmp/reconverge-alive", str(work / "alive"))
            env = {**os.environ, "PATH": f"{work}:{os.environ['PATH']}"}
            process = subprocess.Popen(["sh", "-c", command], env=env, stdout=subprocess.PIPE,
                                       stderr=subprocess.PIPE, text=True, start_new_session=True)
            try:
                readable, _, _ = select.select([process.stderr], [], [], 5)
                self.assertTrue(readable, "sidecar did not report its failed attempt")
                self.assertIn("plugin install failed; retrying in 30s", process.stderr.readline())
                # A permanently failing provisioner must leave its container
                # running, rather than exit and make Kubernetes withdraw the pod.
                with self.assertRaises(subprocess.TimeoutExpired):
                    process.communicate(timeout=0.1)
                self.assertIsNone(process.poll())
                probe = [arg.replace("/tmp/reconverge-alive", str(work / "alive"))
                         for arg in sidecar["readinessProbe"]["exec"]["command"]]
                self.assertEqual(subprocess.run(probe).returncode, 0)
            finally:
                try:
                    os.killpg(process.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
                stdout, _ = process.communicate(timeout=5)
            self.assertNotIn("idle", stdout)

    def test_invalid_ownership_and_nondurable_modes_are_rejected(self):
        for grafana in (
            {"provisioning": {"contentOwner": "invalid"}},
            {"provisioning": {"contentOwner": "release"}},
            *({"mode": mode, "db": DB, "provisioning": {"contentOwner": "release"}}
              for mode in ("external", "external-manual", "off")),
        ):
            with self.subTest(grafana=grafana):
                result = render(**grafana)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("grafana.provisioning.contentOwner", result.stderr)

    def test_external_and_manual_defaults_remain_unchanged(self):
        for mode in ("external", "external-manual", "off"):
            with self.subTest(mode=mode):
                docs = self.docs(mode=mode, auth={"secretName": "external-auth"})
                self.assertFalse(any(d and d["kind"] == "Deployment" and d["metadata"]["name"] == "lunar-grafana"
                                     for d in docs))
                jobs = [d for d in docs if d and d["kind"] == "Job" and d["metadata"]["name"] == "lunar-grafana-provision"]
                self.assertEqual(len(jobs), 1 if mode == "external" else 0)
                if jobs:
                    command = jobs[0]["spec"]["template"]["spec"]["containers"][0]["args"][0]
                    self.assertIn("if /deploy.sh; then exit 0; fi", command)


# grafana.sso needs these from the Hub's configuration before it renders.
SSO_HUB = {"extraEnv": [
    {"name": "HUB_AUTH_SESSION_KEY_PATH", "value": "/secrets/session/key"},
    {"name": "HUB_AUTH_OAUTH_APPS", "value": '[{"forge":"github","client_id":"x"}]'},
]}


def hub_env(docs, name):
    pod = resource(docs, "Deployment", "lunar-hub")["spec"]["template"]["spec"]
    hub = next(c for c in pod["containers"] if c["name"] == "lunar")
    return next(e["value"] for e in hub["env"] if e["name"] == name)


class GrafanaSSORedirectTest(unittest.TestCase):
    def render(self, **sso):
        return render(hub=SSO_HUB, sso={"enabled": True, **sso})

    def redirects(self, **sso):
        result = self.render(**sso)
        self.assertEqual(result.returncode, 0, result.stderr)
        return hub_env(list(yaml.safe_load_all(result.stdout)), "HUB_UI_OAUTH_REDIRECT_URIS")

    def test_grafana_callback_alone_by_default(self):
        self.assertEqual(self.redirects(), "http://grafana.example.com/login/generic_oauth")

    def test_extra_uris_follow_grafana_callback(self):
        self.assertEqual(
            self.redirects(extraRedirectURIs=["https://grafana.example.com/auth/callback", "http://localhost:8091/auth/callback"]),
            "http://grafana.example.com/login/generic_oauth,"
            "https://grafana.example.com/auth/callback,http://localhost:8091/auth/callback")

    def test_unusable_extra_uris_are_rejected(self):
        for uri in ("grafana.example.com/auth/callback", "https://a.example.com/x,https://b", "https://a b"):
            with self.subTest(uri=uri):
                result = self.render(extraRedirectURIs=[uri])
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("grafana.sso.extraRedirectURIs", result.stderr)


if __name__ == "__main__":
    unittest.main()
