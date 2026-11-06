#!/usr/bin/env python3
"""Verify HTTPS JSON health and release identity; never disable TLS verification."""
import argparse
import json
import time
import urllib.error
import urllib.request
import uuid


def fetch_json(base_url, path):
    url = base_url.rstrip('/') + path + '?release_check=' + uuid.uuid4().hex
    request = urllib.request.Request(url, headers={'Cache-Control': 'no-cache', 'Accept': 'application/json'})
    with urllib.request.urlopen(request, timeout=10) as response:
        if response.status != 200:
            raise ValueError(f'{path}: expected HTTP 200, got {response.status}')
        payload = json.loads(response.read(65536))
        if not isinstance(payload, dict):
            raise ValueError(f'{path}: expected JSON object')
        return payload


def check_once(base_url, expected_commit=None, allow_legacy=False):
    if fetch_json(base_url, '/api/health').get('status') != 'ok':
        raise ValueError('Backend health response did not contain status=ok')
    try:
        version = fetch_json(base_url, '/api/version')
    except urllib.error.HTTPError as error:
        if error.code == 404 and allow_legacy and expected_commit is None:
            return {'legacy': True, 'commit': None}
        raise
    commit = version.get('commit')
    if version.get('service') != 'healthcare-api' or not isinstance(commit, str) or not commit or commit == 'development':
        raise ValueError('Version endpoint did not identify a built healthcare-api release')
    if expected_commit is not None and commit != expected_commit:
        raise ValueError(f'Expected commit {expected_commit}, got {commit}')
    ready = fetch_json(base_url, '/api/health/ready')
    if ready.get('status') != 'ready' or ready.get('database') != 'connected':
        raise ValueError('Database readiness check failed')
    return {'legacy': False, 'commit': commit}


def verify(base_url, expected_commit=None, allow_legacy=False, attempts=8, delay=5):
    if not base_url.startswith('https://'):
        raise ValueError('Health checks require an HTTPS base URL')
    for attempt in range(1, attempts + 1):
        try:
            result = check_once(base_url, expected_commit, allow_legacy)
            print(f'HTTPS health/version check passed: {result}', flush=True)
            return result
        except (OSError, ValueError, urllib.error.URLError) as error:
            print(f'Health attempt {attempt}/{attempts}: {type(error).__name__}: {error}', flush=True)
            if attempt == attempts:
                raise
            time.sleep(delay)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--base-url', required=True)
    parser.add_argument('--expected-commit')
    parser.add_argument('--allow-legacy', action='store_true')
    options = parser.parse_args()
    verify(options.base_url, options.expected_commit, options.allow_legacy)
