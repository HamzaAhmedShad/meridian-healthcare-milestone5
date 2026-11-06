import importlib
import os
from pathlib import Path
import sys
import unittest
from unittest.mock import patch
from urllib.error import HTTPError

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
check = importlib.import_module('check_release')
deploy = importlib.import_module('deploy_release')
BASE = 'https://example.invalid'
SHA = 'a' * 40
OLD = 'registry.example/api@sha256:' + 'b' * 64
NEW = 'registry.example/api@sha256:' + 'c' * 64


class HealthChecks(unittest.TestCase):
    def test_correct_release_and_readiness(self):
        with patch.object(check, 'fetch_json', side_effect=[{'status': 'ok'}, {'service': 'healthcare-api', 'commit': SHA}, {'status': 'ready', 'database': 'connected'}]):
            self.assertEqual(check.check_once(BASE, SHA), {'legacy': False, 'commit': SHA})

    def test_wrong_version_rejected(self):
        with patch.object(check, 'fetch_json', side_effect=[{'status': 'ok'}, {'service': 'healthcare-api', 'commit': 'wrong'}]):
            with self.assertRaises(ValueError): check.check_once(BASE, SHA)

    def test_legacy_allowed_only_for_explicit_bootstrap(self):
        error = HTTPError(BASE, 404, 'not found', {}, None)
        with patch.object(check, 'fetch_json', side_effect=[{'status': 'ok'}, error]):
            self.assertTrue(check.check_once(BASE, allow_legacy=True)['legacy'])
        with patch.object(check, 'fetch_json', side_effect=[{'status': 'ok'}, error]):
            with self.assertRaises(HTTPError): check.check_once(BASE)

    def test_legacy_cannot_satisfy_expected_commit(self):
        with patch.object(check, 'fetch_json', side_effect=[{'status': 'ok'}, HTTPError(BASE, 404, 'not found', {}, None)]):
            with self.assertRaises(HTTPError): check.check_once(BASE, SHA, allow_legacy=True)

    def test_bad_readiness_rejected(self):
        with patch.object(check, 'fetch_json', side_effect=[{'status': 'ok'}, {'service': 'healthcare-api', 'commit': SHA}, {'status': 'not-ready'}]):
            with self.assertRaises(ValueError): check.check_once(BASE, SHA)

    def test_non_https_rejected(self):
        with self.assertRaises(ValueError): check.verify('http://example.invalid', attempts=1)


class DeploymentChecks(unittest.TestCase):
    def exercise(self, wait_fail=False, health_fail=False, recovery_fail=False, baseline_fail=False):
        calls = []
        def kube(*args, **kwargs):
            calls.append(args)
            return None
        wait_effect = [None, RuntimeError('rollout failed') if wait_fail else None, None]
        if baseline_fail:
            health_effect = [ValueError('baseline unhealthy')]
        elif wait_fail:
            health_effect = [{'legacy': False, 'commit': 'old'}, ValueError('recovery unhealthy') if recovery_fail else {'legacy': False, 'commit': 'old'}]
        elif health_fail:
            health_effect = [{'legacy': False, 'commit': 'old'}, ValueError('candidate unhealthy'), ValueError('recovery unhealthy') if recovery_fail else {'legacy': False, 'commit': 'old'}]
        else:
            health_effect = [{'legacy': False, 'commit': 'old'}, {'legacy': False, 'commit': SHA}]
        messages = []
        with patch.dict(os.environ, {'CANDIDATE_IMAGE': NEW, 'RELEASE_COMMIT': SHA, 'ROLLBACK_DEMO': 'false', 'ALLOW_LEGACY_BASELINE': 'false'}), \
             patch.object(deploy, 'kube', side_effect=kube), \
             patch.object(deploy, 'wait_rollout', side_effect=wait_effect), \
             patch.object(deploy, 'document', return_value={'metadata': {'annotations': {'deployment.kubernetes.io/revision': '7'}}, 'spec': {'replicas': 2}, 'status': {'availableReplicas': 2}}), \
             patch.object(deploy, 'running_digest', side_effect=[OLD, NEW, OLD] if health_fail else [OLD, OLD] if wait_fail else [OLD, NEW]), \
             patch.object(deploy, 'verify', side_effect=health_effect), \
             patch.object(deploy, 'summary', side_effect=messages.append), \
             patch.object(deploy, 'diagnostics'):
            if baseline_fail:
                with self.assertRaises(ValueError): deploy.main()
                return None, calls, messages
            return deploy.main(), calls, messages

    def test_success_does_not_rollback(self):
        result, calls, messages = self.exercise()
        self.assertEqual(result, 0)
        self.assertFalse(any('undo' in args for args in calls))
        self.assertTrue(any('DEPLOYMENT_VERIFIED' in message for message in messages))

    def test_rollout_failure_restores_explicit_revision_and_digest(self):
        result, calls, messages = self.exercise(wait_fail=True)
        self.assertEqual(result, 1)
        self.assertTrue(any('undo' in args and '--to-revision=7' in args for args in calls))
        self.assertTrue(any('set' in args and deploy.CONTAINER + '=' + OLD in args for args in calls))
        self.assertTrue(any('ROLLBACK_VERIFIED' in message for message in messages))

    def test_post_rollout_health_failure_also_restores(self):
        result, calls, messages = self.exercise(health_fail=True)
        self.assertEqual(result, 1)
        self.assertTrue(any('undo' in args for args in calls))
        self.assertTrue(any('ROLLBACK_VERIFIED' in message for message in messages))

    def test_failed_recovery_never_claims_success(self):
        result, _, messages = self.exercise(wait_fail=True, recovery_fail=True)
        self.assertEqual(result, 1)
        self.assertTrue(any('ROLLBACK_FAILED' in message for message in messages))
        self.assertFalse(any('ROLLBACK_VERIFIED' in message for message in messages))

    def test_unhealthy_baseline_prevents_mutation(self):
        _, calls, _ = self.exercise(baseline_fail=True)
        self.assertEqual(calls, [])


if __name__ == '__main__': unittest.main()
