#!/usr/bin/env python3
"""Deploy one image; restore a recorded healthy template and digest on failure."""
import json
import os
import re
import subprocess
import sys
from check_release import verify

NAMESPACE = os.getenv('NAMESPACE', 'default')
DEPLOYMENT = os.getenv('DEPLOYMENT', 'healthcare-api')
CONTAINER = os.getenv('CONTAINER', 'healthcare-api')
BASE_URL = os.getenv('BASE_URL', 'https://34-149-84-32.sslip.io')
RESOURCE = 'deployment/' + DEPLOYMENT


def run(*args, capture=False):
    print('+ ' + ' '.join(args), flush=True)
    completed = subprocess.run(args, text=True, check=True, timeout=700, capture_output=capture)
    return completed.stdout.strip() if capture else None


def kube(*args, capture=False):
    return run('kubectl', '--namespace=' + NAMESPACE, *args, capture=capture)


def document():
    return json.loads(kube('get', RESOURCE, '-o', 'json', capture=True))


def running_digest():
    pods = json.loads(kube('get', 'pods', '-l', 'app=' + DEPLOYMENT, '-o', 'json', capture=True))
    digests = set()
    for pod in pods['items']:
        if pod['metadata'].get('deletionTimestamp'):
            continue
        for container in pod.get('status', {}).get('containerStatuses', []):
            if container['name'] != CONTAINER:
                continue
            if not container.get('ready'):
                raise ValueError('A selected API container is not ready')
            identity = container.get('imageID', '')
            if '://' in identity:
                identity = identity.split('://', 1)[1]
            if not re.fullmatch(r'[^\s]+@sha256:[0-9a-f]{64}', identity):
                raise ValueError('Runtime did not provide a pullable image digest')
            digests.add(identity)
    if len(digests) != 1:
        raise ValueError('Expected one consistent running API image digest')
    return next(iter(digests))


def wait_rollout():
    kube('rollout', 'status', RESOURCE, '--timeout=600s')


def summary(message):
    print(message, flush=True)
    path = os.getenv('GITHUB_STEP_SUMMARY')
    if path:
        with open(path, 'a') as output:
            output.write(message + '\n\n')


def diagnostics():
    # Diagnostic failures must never prevent the restoration attempt.
    for args in (
        ('get', 'pods', '-l', 'app=' + DEPLOYMENT, '-o', 'wide'),
        ('get', 'events', '--field-selector=type=Warning', '--sort-by=.metadata.creationTimestamp'),
    ):
        try:
            kube(*args)
        except Exception as error:
            print(f'Diagnostic unavailable: {error}', flush=True)


def main():
    candidate = os.environ['CANDIDATE_IMAGE']
    commit = os.environ['RELEASE_COMMIT']
    if not re.fullmatch(r'[0-9a-f]{40}', commit):
        raise ValueError('RELEASE_COMMIT must be a full Git commit SHA')
    demo = os.getenv('ROLLBACK_DEMO', 'false') == 'true'
    if not demo and not re.fullmatch(r'[^\s]+@sha256:[0-9a-f]{64}', candidate):
        raise ValueError('Production release must use an immutable image digest')

    # Abort before changing anything when there is no working recovery target.
    wait_rollout()
    before = document()
    desired = before['spec'].get('replicas', 1)
    if desired < 2 or before.get('status', {}).get('availableReplicas', 0) < desired:
        raise ValueError('Baseline must have at least two available replicas')
    baseline = verify(BASE_URL, allow_legacy=os.getenv('ALLOW_LEGACY_BASELINE', 'false') == 'true')
    revision = before['metadata']['annotations']['deployment.kubernetes.io/revision']
    digest = running_digest()
    if demo and baseline['legacy']:
        raise ValueError('Deploy a versioned production release before the rollback demo')
    snapshot = {'revision': revision, 'image_digest': digest, **baseline}
    print('RECOVERY_TARGET=' + json.dumps(snapshot), flush=True)
    summary(f'Recorded recovery target: revision {revision}, image {digest}, commit {baseline["commit"]}')

    # Maintain replicas during a failed candidate rollout. This does not change the pod template.
    kube('patch', RESOURCE, '--type=merge', '-p', json.dumps({'spec': {
        'revisionHistoryLimit': 10,
        'progressDeadlineSeconds': 600,
        'strategy': {'type': 'RollingUpdate', 'rollingUpdate': {'maxUnavailable': 0, 'maxSurge': 1}},
    }}))

    try:
        kube('set', 'image', RESOURCE, CONTAINER + '=' + candidate)
        wait_rollout()
        if demo:
            raise ValueError('Missing-image demo unexpectedly rolled out; restoring baseline')
        if running_digest() != candidate:
            raise ValueError('Running pods do not match the built candidate digest')
        verify(BASE_URL, expected_commit=commit)
        summary(f'DEPLOYMENT_VERIFIED: HTTPS ready; serving commit {commit}; image {candidate}')
        return 0
    except Exception as deployment_error:
        print(f'CANDIDATE_FAILED: {deployment_error}', flush=True)
        diagnostics()
        try:
            kube('rollout', 'undo', RESOURCE, '--to-revision=' + revision)
            # Pin the recorded runtime digest even if an old image tag has moved.
            kube('set', 'image', RESOURCE, CONTAINER + '=' + digest)
            wait_rollout()
            if running_digest() != digest:
                raise ValueError('Recovered pods do not match the recorded working digest')
            verify(BASE_URL, expected_commit=baseline['commit'], allow_legacy=baseline['legacy'])
            summary(f'ROLLBACK_VERIFIED: serving previous commit {baseline["commit"]}; image {digest}')
        except Exception as rollback_error:
            summary(f'ROLLBACK_FAILED: recovery could not be verified: {rollback_error}')
            diagnostics()
        # Candidate failure remains visible even after successful recovery.
        return 1


if __name__ == '__main__':
    try:
        sys.exit(main())
    except Exception as error:
        summary(f'PREFLIGHT_FAILED: no candidate deployment attempted: {error}')
        sys.exit(1)
