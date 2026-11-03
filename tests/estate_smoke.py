#!/usr/bin/env python3
"""Isolated Tern 0.9.10 native-window outcome test. CodexBWAI, COMMANDER-993.

Requires existing Tern + xvfb-run. No install, external download or provider call.
Only an optional --forge REF performs a read through the deployed FORGE CLI.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shlex
import shutil
import signal
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
TERN = '/usr/local/lib/tern/current/tern'


def wait_for(check, description, seconds=10):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        result = check()
        if result:
            return result
        time.sleep(.15)
    raise AssertionError('timeout: ' + description)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--forge')
    parser.add_argument('--evidence', required=True, type=Path)
    args = parser.parse_args()
    evidence = {'checks': [], 'production_touched': False}
    processes = []
    with tempfile.TemporaryDirectory(prefix='codexbwai-tern-smoke-', dir='/var/tmp') as temporary:
        base = Path(temporary)
        config = base/'config'
        data = config/'plugin-data/estate-session-list'
        data.mkdir(parents=True, mode=0o700)
        config.chmod(0o700)
        data.parent.chmod(0o700)
        shutil.copytree(ROOT, base/'plugin', ignore=shutil.ignore_patterns('.git', '__pycache__', '*.local'))
        host = base/'plugin/host.luau'
        with host.open('a') as stream:
            stream.write('\nlocal suite = require("./tests/native_suite")\ntern.fs.write(tern.plugin.data .. "/library-tests.json", tern.json.encode(suite))\n')
        plan = base/'PLAN.md'
        original = '# Smoke\n## Progress\n- [ ] CP1: native outcome\n## START HERE\nContinue smoke only.\n'
        plan.write_text(original)
        env = dict(os.environ, TERN_CONFIG_DIR=str(config), TERN_DAEMON_SOCKET=str(base/'daemon.sock'), STENCIL_GPU='cpu')
        control = base/'window.sock'
        def command(*parts, check=True):
            result = subprocess.run([TERN, *map(str, parts)], env=env, capture_output=True, text=True, timeout=15)
            if check and result.returncode:
                raise AssertionError(result.stderr)
            return result.stdout
        def ctl(*parts):
            result = json.loads(command('ctl', '--control', control, *parts))
            if result.get('ok') is False:
                raise AssertionError(result)
            return result
        def rows():
            return ctl('tree', '.sf-ck-item').get('nodes', [])
        def snapshot(pane):
            path = data/'views'/f'{pane}.json'
            return json.loads(path.read_text()) if path.exists() else None
        def run(pane, *parts):
            command('run', str(pane), shlex.join(map(str, parts)))
        try:
            log = open(base/'process.log', 'w+')
            processes.append(subprocess.Popen([TERN, 'daemon', '--socket', str(base/'daemon.sock')], env=env, stdout=log, stderr=log, start_new_session=True))
            wait_for(lambda: (base/'daemon.sock').exists(), 'private daemon')
            command('plugin', 'link', str(base/'plugin'))
            plugins = json.loads(command('plugin', 'list', '--json'))
            assert not plugins['problems'] and plugins['plugins'][0]['status'] == 'ready', plugins
            evidence['checks'].append('real host plugin loads ready')
            library = json.loads((data/'library-tests.json').read_text())
            assert not library['failures'], library
            evidence['library_tests_passed'] = library['passed']
            pane = int(command('new', 'session', 'estate-smoke', '--', '/bin/sh').strip())
            processes.append(subprocess.Popen(['xvfb-run', '-a', TERN, '--control', str(control)], env=env, cwd=base, stdout=log, stderr=log, start_new_session=True))
            wait_for(lambda: control.exists(), 'private window', 15)
            command('focus', str(pane))
            run(pane, base/'plugin/bin/session-list', 'bind', '--work-id', 'SMOKE-1', '--plan', plan)
            wait_for(lambda: snapshot(pane), 'bound snapshot')
            wait_for(lambda: len(rows()) == 1 and 'st-pending' in rows()[0]['class'], 'native pending checklist')
            evidence['checks'].append('PLAN binding renders native pending row')
            plan.write_text(original.replace('[ ]', '[x]'))
            run(pane, base/'plugin/bin/session-list', 'refresh')
            wait_for(lambda: len(rows()) == 1 and 'st-done' in rows()[0]['class'], 'native done checklist')
            evidence['checks'].append('canonical edit + refresh renders native done row')
            command('focus', str(pane))
            ctl('plugins', 'run', 'plugin.estate-session-list.show')
            ctl('plugins', 'run', 'plugin.estate-session-list.show')
            assert len(rows()) == 1, rows()
            evidence['checks'].append('repeated palette show does not duplicate panel')
            plan.write_text('# Invalid source\n')
            run(pane, base/'plugin/bin/session-list', 'refresh')
            wait_for(lambda: len(rows()) == 1 and rows()[0].get('text', '').startswith('Source unavailable') and 'st-blocked' in rows()[0]['class'], 'native source failure')
            evidence['checks'].append('source failure clears old success and renders blocked error')
            # A second native pane is a new epoch and cannot inherit the first view.
            second = int(command('new', 'tab', 'estate-smoke', '--', '/bin/sh').strip())
            second_source = ['--forge', args.forge] if args.forge else ['--plan', str(plan)]
            plan.write_text(original)
            run(second, base/'plugin/bin/session-list', 'bind', '--work-id', 'SECOND-1', *second_source)
            wait_for(lambda: snapshot(second), 'second source snapshot')
            assert snapshot(pane)['error'] and snapshot(second)['work_id'] == 'SECOND-1'
            assert snapshot(pane)['epoch'] != snapshot(second)['epoch']
            evidence['checks'].append('two native panes retain independent bindings/epochs')
            if args.forge:
                assert snapshot(second)['forge'] == [args.forge]
                evidence['checks'].append('live FORGE product read binds matching custom reference')
            evidence['source_hashes'] = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in [ROOT/'host.luau',ROOT/'window.luau',ROOT/'lib/vista.luau',ROOT/'bin/estate_session_list.py']}
            evidence['passed'] = True
        except Exception as error:
            evidence['passed'] = False
            evidence['error'] = str(error)
            log.flush()
            log.seek(0)
            evidence['process_log_tail'] = log.read()[-4000:]
        finally:
            # Only groups started by this invocation. No process-name/global cleanup.
            for process in reversed(processes):
                if process.poll() is None:
                    os.killpg(process.pid, signal.SIGTERM)
                    try:
                        process.wait(timeout=4)
                    except subprocess.TimeoutExpired:
                        os.killpg(process.pid, signal.SIGKILL)
                        process.wait(timeout=4)
            log.close()
            evidence['own_processes_reaped'] = all(p.poll() is not None for p in processes)
        args.evidence.parent.mkdir(parents=True, exist_ok=True)
        args.evidence.write_text(json.dumps(evidence, indent=2)+'\n')
    print(json.dumps(evidence, indent=2))
    return 0 if evidence.get('passed') and evidence.get('own_processes_reaped') else 1


if __name__ == '__main__':
    raise SystemExit(main())
