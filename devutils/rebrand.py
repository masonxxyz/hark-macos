#!/usr/bin/env python3
# Copyright 2026 The Hark Authors
# You can use, redistribute, and/or modify this source code under
# the terms of the GPL-3.0 license that can be found in the LICENSE file.
"""One-shot rebrand of a Helium tree (helium-macos + helium core + onboarding)
into Hark. Kept in-tree so the same transform can be re-run after merging
upstream Helium changes:

    python3 devutils/rebrand.py <repo> [<repo> ...]

It rewrites file contents and renames paths. Things that must keep pointing
at upstream (shared infrastructure, attribution, copyright notices, upstream
third-party content that patches match against) are protected.
"""

import os
import re
import subprocess
import sys

UPSTREAM_SERVICES = 'services.helium.imput.net'

# Literal strings that must survive untouched (checked before any rewrite).
PROTECT = [
    # Shared infrastructure we still rely on (see README "Infrastructure").
    UPSTREAM_SERVICES,
    'push.helium.computer',
    'imputnet/helium-services',
    'filters/helium-annoyances.txt',
    'filters/helium-unbreak.txt',
    'assets/helium/',
    'Helium filters',  # uBO list titles shipped by the upstream uBO fork
    'imputnet/helium-nonfree-assets',
    '@imput/helium-prism',
    'imputnet/helium-macos/wiki',
    # Copyright notices are never rewritten (GPL-3.0 s4/s5).
    'The Helium Authors',
    '2025 imput',
]

# Ordered (pattern, replacement) pairs applied before the generic rename.
SPECIFIC = [
    # Product identity
    (r'COMPANY_FULLNAME=The Helium Authors', 'COMPANY_FULLNAME=The Hark Authors'),
    (r'COMPANY_SHORTNAME=The Helium Authors', 'COMPANY_SHORTNAME=The Hark Authors'),
    (r'@LASTCHANGE_YEAR@ The Helium Authors', '@LASTCHANGE_YEAR@ The Hark Authors'),
    (r'MAC_TEAM_ID=S4Q33XPHB4', 'MAC_TEAM_ID='),
    (r'net\.imput\.helium', 'com.cognify.hark'),
    # Endpoints Hark must never talk to as if it were Helium
    (r'https://updates\.helium\.computer/', 'https://updates.hark.invalid/'),
    (r'https://crash\.helium\.computer/crash', 'https://crash.hark.invalid/crash'),
    (r'set_ping_enabled_domain\("helium\.computer"\)', 'set_ping_enabled_domain("hark.invalid")'),
    (r'https://helium\.computer/(privacy|terms)', 'https://github.com/masonxxyz/hark'),
    (r'helium-bot@imput\.net', 'hark-bot@users.noreply.github.com'),
    # Repositories
    (r'imputnet/helium-macos', 'masonxxyz/hark-macos'),
    (r'imputnet/helium-onboarding', 'masonxxyz/hark-onboarding'),
    (r'imputnet/helium-(windows|linux)', 'masonxxyz/hark'),
    (r'imputnet/helium-chromium', 'masonxxyz/hark'),
    (r'imputnet/helium-', 'masonxxyz/hark-'),
    (r'imputnet/helium\b', 'masonxxyz/hark'),
    (r'https?://helium\.computer/?', 'https://github.com/masonxxyz/hark'),
    # Dev shell flourish
    ('\U0001F388', '\U0001F4EF'),  # balloon -> postal horn
]

GENERIC = [
    (re.compile(r'HELIUM'), 'HARK'),
    (re.compile(r'Helium'), 'Hark'),
    (re.compile(r'helium'), 'hark'),
]

# Never rewritten (licence texts).
SKIP_FILE = re.compile(r'(^|/)(LICENSE[^/]*|rebrand\.py)$')


def protect(text):
    table = {}
    for i, token in enumerate(PROTECT):
        if token in text:
            key = f'\x00P{i}\x00'
            table[key] = token
            text = text.replace(token, key)
    return text, table


def restore(text, table):
    for key, token in table.items():
        text = text.replace(key, token)
    return text


def rebrand_text(text):
    for pattern, repl in SPECIFIC[:3]:  # BRANDING lines contain a protected token
        text = re.sub(pattern, repl, text)
    text, table = protect(text)
    for pattern, repl in SPECIFIC[3:]:
        text = re.sub(pattern, repl, text)
    for regex, repl in GENERIC:
        text = regex.sub(repl, text)
    return restore(text, table)


def tracked_files(repo):
    out = subprocess.check_output(['git', '-C', repo, 'ls-files', '-z'])
    return [p for p in out.decode().split('\0') if p]


def is_text(path):
    with open(path, 'rb') as f:
        chunk = f.read(8192)
    return b'\0' not in chunk


def rebrand_repo(repo):
    changed = 0
    for rel in tracked_files(repo):
        path = os.path.join(repo, rel)
        if os.path.islink(path) or not os.path.isfile(path):
            continue
        if SKIP_FILE.search(rel) or not is_text(path):
            continue
        with open(path, encoding='utf-8', errors='surrogateescape', newline='') as f:
            text = f.read()
        new = rebrand_text(text)
        if new != text:
            with open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
                f.write(new)
            changed += 1

    # Rename tracked files one by one, then drop the emptied directories.
    renamed = 0
    old_dirs = set()
    for rel in tracked_files(repo):
        new_rel = rebrand_text(rel)
        if new_rel == rel or not os.path.isfile(os.path.join(repo, rel)):
            continue
        os.makedirs(os.path.join(repo, os.path.dirname(new_rel)), exist_ok=True)
        subprocess.check_call(['git', '-C', repo, 'mv', rel, new_rel])
        old_dirs.add(os.path.dirname(rel))
        renamed += 1
    for d in sorted(old_dirs, key=lambda p: -p.count('/')):
        while d:
            full = os.path.join(repo, d)
            if os.path.isdir(full) and not os.listdir(full):
                os.rmdir(full)
            d = os.path.dirname(d)
    print(f'{repo}: rewrote {changed} files, renamed {renamed} paths')


if __name__ == '__main__':
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    for r in sys.argv[1:]:
        rebrand_repo(os.path.abspath(r))
