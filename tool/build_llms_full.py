#!/usr/bin/env python3
"""Writes web/llms-full.txt (the whole catalog as plain text for AI assistants) from assets/catalog/catalog.json."""
import json
from pathlib import Path

root = Path(__file__).resolve().parent.parent
catalog = json.loads((root / 'assets/catalog/catalog.json').read_text(encoding='utf-8'))
out = ['# BesideOS: full catalog', '',
       '> Operating systems BesideOS can install beside the current one, without a USB stick. https://besideos.com/', '']
for d in catalog['distros']:
    out += [f"## {d['name']}", f"- id: {d['id']}", f"- family: {d['family']}", f"- tagline: {d['tagline']}",
            f"- best for: {d['bestFor']}", f"- desktop: {d['desktop']}", f"- official download page: {d['downloadPage']}",
            f"- page: https://besideos.com/#/distros/{d['id']}"]
    for i in d.get('isos', []):
        out.append(f"- ISO ({i['arch']}): {i['url']} (checksums: {i['checksumUrl']})")
    if d.get('userSuppliedIso'):
        out.append('- ISO: the user picks their own ISO file')
    out.append('')
(root / 'web/llms-full.txt').write_text('\n'.join(out), encoding='utf-8')
