"""Owned loopback SSH fixture; generated keys are private and deleted with the fixture."""
import contextlib
import os
from pathlib import Path
import pwd
import shlex
import signal
import socket
import subprocess
import time


@contextlib.contextmanager
def loopback_ssh(base):
    base = Path(base)
    base.mkdir(mode=0o700)
    for name in ('host', 'client'):
        subprocess.run(['ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-f', str(base/name)], check=True, timeout=5)
    with socket.socket() as probe:
        probe.bind(('127.0.0.1', 0))
        port = probe.getsockname()[1]
    user = pwd.getpwuid(os.getuid()).pw_name
    (base/'sshd.conf').write_text(f'''Port {port}
ListenAddress 127.0.0.1
HostKey {base}/host
PidFile {base}/pid
AuthorizedKeysFile {base}/client.pub
AllowUsers {user}
AuthenticationMethods publickey
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
UsePAM no
PermitRootLogin no
StrictModes yes
AllowTcpForwarding no
X11Forwarding no
PermitTTY no
LogLevel ERROR
''')
    public = (base/'host.pub').read_text().split()
    (base/'known_hosts').write_text(f'[127.0.0.1]:{port} {public[0]} {public[1]}\n')
    (base/'ssh.conf').write_text(f'''Host session-plan-test
 HostName 127.0.0.1
 Port {port}
 User {user}
 IdentityFile {base}/client
 UserKnownHostsFile {base}/known_hosts
 StrictHostKeyChecking yes
 IdentitiesOnly yes
 BatchMode yes
''')
    binary = base/'bin'
    binary.mkdir()
    wrapper = binary/'ssh'
    wrapper.write_text('#!/bin/sh\nexec /usr/bin/ssh -F '+shlex.quote(str(base/'ssh.conf'))+' "$@"\n')
    wrapper.chmod(0o700)
    with (base/'server.log').open('w+') as log:
        server = subprocess.Popen(['/usr/sbin/sshd', '-D', '-e', '-f', str(base/'sshd.conf')], stdout=log, stderr=log, start_new_session=True)
        try:
            deadline = time.monotonic()+3
            while time.monotonic()<deadline:
                if server.poll() is not None:
                    log.seek(0)
                    raise RuntimeError('owned SSH fixture failed: '+log.read())
                try:
                    with socket.create_connection(('127.0.0.1', port), timeout=.1):
                        break
                except OSError:
                    time.sleep(.05)
            else:
                raise RuntimeError('owned SSH fixture did not listen')
            yield str(binary)+os.pathsep+os.environ['PATH']
        finally:
            if server.poll() is None:
                os.killpg(server.pid, signal.SIGTERM)
                server.wait(timeout=4)
