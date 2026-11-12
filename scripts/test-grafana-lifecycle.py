#!/usr/bin/env python3
"""Render Grafana ownership modes and exercise the rendered failure behavior.

Requires helm and PyYAML. Run: python3 scripts/test-grafana-lifecycle.py
"""

from pathlib import Path
import os
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


def render(**grafana):
    values = {**BASE, "grafana": {**BASE["grafana"], **grafana}}
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
        self.assertIn("/deploy.sh --plugins-only || exit $?", sidecar["args"][0])
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

    def test_plugin_sidecar_restarts_on_failure(self):
        sidecar, _ = containers(self.docs(db=DB, provisioning={"contentOwner": "release"}))
        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp)
            for name, body in {"curl": "exit 0", "tail": "echo idle", "deploy.sh": "exit 37"}.items():
                path = work / name
                path.write_text("#!/bin/sh\n" + body + "\n")
                path.chmod(0o755)
            command = sidecar["args"][0].replace("/deploy.sh", str(work / "deploy.sh"))
            command = command.replace("/tmp/reconverge-alive", str(work / "alive"))
            env = {**os.environ, "PATH": f"{work}:{os.environ['PATH']}"}
            result = subprocess.run(["sh", "-c", command], env=env, capture_output=True, text=True, timeout=5)
            self.assertEqual(result.returncode, 37)
            self.assertNotIn("idle", result.stdout)

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


if __name__ == "__main__":
    unittest.main()
