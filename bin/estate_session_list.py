#!/usr/bin/env python3
"""Read explicit interactive-plan checkpoints locally or over SSH. CodexBWAI; MIT."""
import argparse
import json
import os
from pathlib import Path
import re
import shlex
import stat
import subprocess
import sys
import uuid

START = '<!-- TERN-SESSION:START -->'
END = '<!-- TERN-SESSION:END -->'
LIMIT = 1024 * 1024
STATES = {'pending', 'active', 'blocked', 'done'}


class Parser(argparse.ArgumentParser):
    def error(self, message):
        raise ValueError(message)


def validate(plan):
    if not isinstance(plan, dict) or set(plan) != {'schema', 'plan_id', 'title', 'current', 'checkpoints'}:
        raise ValueError('checkpoint block needs schema, plan_id, title, current and checkpoints only')
    if type(plan['schema']) is not int or plan['schema'] != 1:
        raise ValueError('unsupported checkpoint schema')
    if not isinstance(plan['plan_id'], str) or not re.fullmatch(r'plan-[0-9a-f]{12}', plan['plan_id']):
        raise ValueError('invalid stable plan_id')
    if not isinstance(plan['title'], str) or not 1 <= len(plan['title'].strip()) <= 160:
        raise ValueError('plan title must contain 1–160 characters')
    if not isinstance(plan['checkpoints'], list) or not 1 <= len(plan['checkpoints']) <= 30:
        raise ValueError('use 1–30 agreed checkpoints')
    ids, active = {}, []
    for item in plan['checkpoints']:
        if not isinstance(item, dict) or not {'id', 'text', 'state'} <= set(item) or set(item) - {'id', 'text', 'state', 'reason'}:
            raise ValueError('checkpoint needs id, text, state and optional reason only')
        if not isinstance(item['id'], str) or not re.fullmatch(r'[a-z][a-z0-9_-]{0,39}', item['id']) or item['id'] in ids:
            raise ValueError('checkpoint ids must be stable and unique')
        if not isinstance(item['text'], str) or not 1 <= len(item['text'].strip()) <= 240:
            raise ValueError('checkpoint text must contain 1–240 characters')
        if not isinstance(item['state'], str) or item['state'] not in STATES:
            raise ValueError('unsupported checkpoint state')
        reason = item.get('reason')
        if reason is not None and (not isinstance(reason, str) or not 1 <= len(reason.strip()) <= 400):
            raise ValueError('blocked reason must contain 1–400 characters')
        if (item['state'] == 'blocked') != (reason is not None):
            raise ValueError('only blocked checkpoints carry a required reason')
        ids[item['id']] = item['state']
        if item['state'] == 'active':
            active.append(item['id'])
    current = plan['current']
    if current is not None and (not isinstance(current, str) or current not in ids or ids[current] not in {'active', 'blocked'}):
        raise ValueError('current must name an active/blocked checkpoint, or be null')
    if len(active) > 1 or (active and current != active[0]):
        raise ValueError('at most one active checkpoint, named by current')
    return plan


def read_plan(path):
    if not path.is_absolute():
        raise ValueError('PLAN path must be absolute on the agent machine')
    if path.is_symlink():
        raise ValueError('PLAN must be a regular non-symlink file')
    flags = os.O_RDONLY | getattr(os, 'O_NOFOLLOW', 0) | getattr(os, 'O_NONBLOCK', 0)
    fd = os.open(path, flags)
    with os.fdopen(fd, 'rb') as stream:
        if not stat.S_ISREG(os.fstat(stream.fileno()).st_mode):
            raise ValueError('PLAN must be a regular file')
        raw = stream.read(LIMIT + 1)
    if len(raw) > LIMIT:
        raise ValueError('PLAN exceeds 1 MiB')
    text = raw.decode('utf-8')
    if text.count(START) != 1 or text.count(END) != 1:
        raise ValueError('PLAN needs one explicit TERN-SESSION checkpoint block; deliberately adopt it through the planning workflow')
    before, block = text.split(START, 1)
    block, after = block.split(END, 1)
    block = block.strip()
    if not block.startswith('```json\n') or not block.endswith('\n```'):
        raise ValueError('checkpoint block must contain one fenced JSON object')
    return validate(json.loads(block[len('```json\n'):-len('\n```')]))


def read_ssh(destination, path):
    if not re.fullmatch(r'(?:[A-Za-z0-9._-]+@)?[A-Za-z0-9][A-Za-z0-9._-]{0,252}', destination):
        raise ValueError('use a reviewed SSH config alias or user@host, with no shell options')
    if destination.split('@')[-1].lower().startswith('seat-'):
        raise ValueError('seat-* forced agent launchers are not SSH file-reading destinations')
    # Only this reviewed reader travels to the configured POSIX host; no install or writes.
    remote = shlex.join(['python3', '-I', '-', 'source', '--plan', str(path)])
    result = subprocess.run(['ssh', '-T', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=3',
                             '-o', 'ClearAllForwardings=yes', destination, remote],
                            input=Path(__file__).read_text(encoding='utf-8'),
                            capture_output=True, text=True, timeout=4)
    if result.returncode or len(result.stdout) > 65536:
        raise ValueError('SSH source unavailable; verify the reviewed destination, existing trust/authentication and Python 3')
    envelope = json.loads(result.stdout)
    if not isinstance(envelope, dict) or envelope.get('ok') is not True:
        raise ValueError('SSH source did not return a valid checkpoint report')
    return validate(envelope.get('plan'))


def main(argv=None):
    try:
        parser = Parser(description=__doc__)
        commands = parser.add_subparsers(dest='command', required=True, parser_class=Parser)
        source = commands.add_parser('source', help='read the agent’s canonical checkpoint block')
        source.add_argument('--plan', required=True)
        source.add_argument('--ssh', help='explicitly reviewed ordinary SSH destination; remote host needs Python 3 and a POSIX shell')
        template = commands.add_parser('template', help='print a block for the agent to place in its approved plan; never writes it')
        template.add_argument('--title', required=True)
        template.add_argument('--step', action='append', required=True)
        args = parser.parse_args(argv)
        if args.command == 'template':
            plan = validate({'schema': 1, 'plan_id': 'plan-' + uuid.uuid4().hex[:12], 'title': args.title,
                             'current': None, 'checkpoints': [{'id': f'cp{i}', 'text': text, 'state': 'pending'} for i, text in enumerate(args.step, 1)]})
            print(START+'\n```json\n'+json.dumps(plan, indent=2, ensure_ascii=False)+'\n```\n'+END)
        else:
            plan = read_ssh(args.ssh, args.plan) if args.ssh else read_plan(Path(args.plan))
            print(json.dumps({'ok': True, 'plan': plan}, ensure_ascii=True, separators=(',', ':')))
        return 0
    except (ValueError, OSError, subprocess.TimeoutExpired) as error:
        print(json.dumps({'ok': False, 'error': str(error)}, ensure_ascii=True))
        return 1


if __name__ == '__main__':
    sys.exit(main())
