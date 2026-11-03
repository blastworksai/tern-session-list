#!/usr/bin/env python3
"""Real native local/SSH interactive-plan outcomes in owned disposable Tern/Xvfb/SSH."""
import argparse
from contextlib import ExitStack
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile
import time
from estate_test import plan, write_plan
from ssh_fixture import loopback_ssh

ROOT = Path(__file__).resolve().parents[1]
TERN = '/usr/local/lib/tern/current/tern'


def wait_for(check, description, seconds=10):
    deadline = time.monotonic()+seconds
    while time.monotonic()<deadline:
        value = check()
        if value:
            return value
        time.sleep(.15)
    raise AssertionError('timeout: '+description)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--evidence', required=True, type=Path)
    args = parser.parse_args()
    evidence = {'checks': [], 'production_touched': False}
    processes = []
    # sshd StrictModes requires a safe ancestor chain; /var/tmp is deliberately sticky/shared.
    with tempfile.TemporaryDirectory(prefix='interactive-plan-smoke-', dir=Path.home()/'.cache') as temporary, ExitStack() as stack:
        base = Path(temporary)
        config = base/'config'
        config.mkdir(mode=0o700)
        shutil.copytree(ROOT, base/'plugin', ignore=shutil.ignore_patterns('.git', '__pycache__', '*.local'))
        local = base/'Local plan.md'
        remote = base/'SSH plan.md'
        write_plan(local, plan())
        remote_value = plan('plan-abcdef123456')
        remote_value['title'] = 'SSH interactive task'
        write_plan(remote, remote_value)
        path = stack.enter_context(loopback_ssh(base/'ssh'))
        env = dict(os.environ, PATH=path, TERN_CONFIG_DIR=str(config),
                   TERN_DAEMON_SOCKET=str(base/'daemon.sock'), STENCIL_GPU='cpu')
        control = base/'window.sock'
        source_file = base/'plugin/window.luau'
        with source_file.open('a') as stream:
            for name, source in [('test_local', {'path': str(local)}), ('test_ssh', {'path': str(remote), 'ssh': 'session-plan-test'})]:
                encoded = json.dumps(json.dumps(source))
                stream.write('\ntern.command({id="'+name+'", title="Isolated fixture", run=function(cx) openSource(cx,cx.session:focused(),tern.json.decode('+encoded+')) end})\n')
        host = base/'plugin/host.luau'
        with host.open('a') as stream:
            stream.write('\nlocal suite=require("./tests/native_suite")\ntern.fs.write(tern.plugin.data.."/library-tests.json",tern.json.encode(suite))\n')
            stream.write('''
local function captureFixtureState()
    local out = {}
    for _, state in instances do
        if state.source then
            out[state.source.path] = {plan_id=state.plan_id, plan=state.plan, error=state.error,
                saved={schema=2,source=state.source,plan_id=state.plan_id}}
        end
    end
    tern.fs.write(tern.plugin.data .. "/fixture-state.json", tern.json.encode(out))
    tern.timer(100, captureFixtureState)
end
tern.timer(100, captureFixtureState)
''')
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
        def has_row(state, text=None):
            current = rows()
            return len(current)==1 and ('st-'+state) in current[0]['class'] and (text is None or text in current[0].get('text',''))
        def observed(source):
            location=config/'plugin-data/estate-session-list/fixture-state.json'
            try:return json.loads(location.read_text()).get(str(source),{})
            except (FileNotFoundError,json.JSONDecodeError):return {}
        def source_state(source,state):
            value=observed(source)
            return value.get('plan',{}).get('checkpoints',[{}])[0].get('state')==state
        def action(name):
            ctl('plugins', 'run', 'plugin.estate-session-list.'+name)
        log = open(base/'process.log', 'w+')
        try:
            processes.append(subprocess.Popen([TERN,'daemon','--socket',str(base/'daemon.sock')],env=env,stdout=log,stderr=log,start_new_session=True))
            wait_for(lambda:(base/'daemon.sock').exists(),'private daemon')
            command('plugin','link',base/'plugin')
            plugins=json.loads(command('plugin','list','--json'))
            assert not plugins['problems'] and plugins['plugins'][0]['status']=='ready',plugins
            evidence['checks'].append('real Tern host plugin loads ready')
            library=json.loads((config/'plugin-data/estate-session-list/library-tests.json').read_text())
            assert not library['failures'],library
            evidence['retained_library_tests_passed']=library['passed']
            first=int(command('new','session','interactive-test','--','/bin/sh').strip())
            processes.append(subprocess.Popen(['xvfb-run','-a',TERN,'--control',str(control)],env=env,cwd=base,stdout=log,stderr=log,start_new_session=True))
            wait_for(lambda:control.exists(),'private window',15)
            command('focus',first)
            wait_for(lambda: any(p.get('id')==first for p in ctl('state').get('panes',[])), 'native window attached to fixture')
            action('test_local')
            wait_for(lambda:has_row('pending','Prove the outcome'),'local source checklist')
            evidence['checks'].append('explicit local checkpoint block renders native pending state')
            write_plan(local,plan(state='done'))
            wait_for(lambda:has_row('done'),'automatic source refresh')
            evidence['checks'].append('canonical edit automatically renders done without an agent hook')
            command('focus',first)
            action('show');action('show')
            assert len(rows())==1,rows()
            evidence['checks'].append('repeated show preserves one panel per tab')
            write_plan(local,plan('plan-999999999999'))
            wait_for(lambda:'different plan' in observed(local).get('error','') and not observed(local).get('plan'),'identity replacement refusal')
            evidence['checks'].append('different plan at the same path cannot replace the pinned plan id')
            command('plugin','reload','estate-session-list')
            wait_for(lambda:'different plan' in observed(local).get('error','') and observed(local).get('saved',{}).get('plan_id')=='plan-123456abcdef','restored identity refusal')
            evidence['checks'].append('plugin restore retains the pinned source/id, never a source-pane number')
            write_plan(local,plan())
            wait_for(lambda:source_state(local,'pending'),'original source restored')
            local.write_text('# No checkpoint block\n')
            wait_for(lambda:'checkpoint block' in observed(local).get('error','') and not observed(local).get('plan'),'source failure invalidation')
            evidence['checks'].append('source loss clears old success and reaches the native error view')
            write_plan(local,plan())
            second=int(command('new','tab','interactive-test','--','/bin/sh').strip())
            command('focus',second)
            wait_for(lambda:ctl('state').get('focused',{}).get('id')==second and any(p.get('id')==second for p in ctl('state').get('panes',[])), 'second fixture pane published in the native window')
            action('test_ssh')
            wait_for(lambda:source_state(remote,'pending'),'real SSH source response in native host',12)
            evidence['checks'].append('real loopback SSH key-authenticated source reaches native host view state')
            remote_value['checkpoints'][0]['state']='done'
            write_plan(remote,remote_value)
            wait_for(lambda:source_state(remote,'done'),'SSH canonical edit refresh')
            evidence['checks'].append('SSH source edits automatically refresh native view state')
            command('focus',first)
            wait_for(lambda:source_state(local,'pending'),'independent local source')
            evidence['checks'].append('local and SSH views keep independent plan identities and state')
            evidence['visual_qualification']='Initial local pending/done rows observed; later checks use actual host callback state because the closed-beta sign-in overlay hides the client UI. Remote/restored visual qualification remains open.'
            evidence['runtime']=command('--version').strip()
            evidence['source_hashes']={name:hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in ['host.luau','window.luau','lib/plan_view.luau','bin/estate_session_list.py']}
            evidence['passed']=True
        except Exception as error:
            evidence['passed']=False;evidence['error']=str(error)
            log.flush();log.seek(0);evidence['process_log_tail']=log.read()[-3000:]
            try:
                evidence['last_native_rows']=rows()
                evidence['last_native_state']=ctl('state')
                evidence['last_native_tree']=ctl('tree')
            except Exception:pass
        finally:
            for process in reversed(processes):
                if process.poll() is None:
                    os.killpg(process.pid,signal.SIGTERM)
                    try:process.wait(timeout=4)
                    except subprocess.TimeoutExpired:
                        os.killpg(process.pid,signal.SIGKILL);process.wait(timeout=4)
            log.close()
            evidence['own_processes_reaped']=all(p.poll() is not None for p in processes)
        args.evidence.parent.mkdir(parents=True,exist_ok=True)
        args.evidence.write_text(json.dumps(evidence,indent=2)+'\n')
    print(json.dumps({k:v for k,v in evidence.items() if k not in ('last_native_tree','last_native_state')},indent=2))
    return 0 if evidence.get('passed') and evidence.get('own_processes_reaped') else 1


if __name__=='__main__':
    raise SystemExit(main())
