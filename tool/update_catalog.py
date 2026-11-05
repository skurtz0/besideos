#!/usr/bin/env python3
"""Keeps the ISO entries of assets/catalog/catalog.json current.

For every distro with official ISOs it looks up the newest release on the official mirror, checks that the
file really exists (HTTP HEAD) and rewrites url, checksumUrl, fileName and sizeBytes. A lookup that fails keeps
the old entry; an entry whose link is dead and cannot be refreshed makes the script exit with 1.

    python3 tool/update_catalog.py            # update the catalog in place
    python3 tool/update_catalog.py --check    # change nothing; exit 1 if something is outdated or dead

Run weekly by .github/workflows/update-catalog.yml, which opens a pull request with the result.
"""
import json
import re
import sys
import urllib.request
from pathlib import Path

CATALOG = Path(__file__).resolve().parent.parent / 'assets' / 'catalog' / 'catalog.json'
UA = {'User-Agent': 'besideos-catalog-updater (+https://github.com/skurtz0/besideos)'}
MIN_ISO_BYTES = 500 * 1024 * 1024


def get(url):
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60) as r:
        return r.read().decode('utf-8', 'replace')


def links(url):
    return re.findall(r'href="([^"?#/][^"?#]*/?)"', get(url))


def head(url):
    """Size in bytes of the file behind url, or None when it is missing or too small to be an ISO."""
    try:
        req = urllib.request.Request(url, headers=UA, method='HEAD')
        with urllib.request.urlopen(req, timeout=60) as r:
            size = int(r.headers.get('Content-Length', 0))
        return size if size >= MIN_ISO_BYTES else None
    except Exception:
        return None


def vkey(v):
    return tuple(int(p) for p in re.findall(r'\d+', v))


def newest(names, pattern):
    found = [m.group(1) for n in names if (m := re.fullmatch(pattern, n))]
    return max(found, key=vkey) if found else None


def ubuntu_lts(names):
    # Only long-term support releases (xx.04 with an even year), newest point release first.
    lts = [n.rstrip('/') for n in names if re.fullmatch(r'\d\d\.04(\.\d+)?/', n) and int(n[:2]) % 2 == 0]
    return sorted(lts, key=vkey, reverse=True)


def resolve_ubuntu_like(distro_id, iso):
    flavour = {'ubuntu': None, 'xubuntu': 'xubuntu', 'kubuntu': 'kubuntu'}[distro_id]
    arch_pkg = 'amd64' if iso['arch'] == 'x86_64' else 'arm64'
    if flavour is None and arch_pkg == 'amd64':
        base = 'https://releases.ubuntu.com/'
        tail = lambda v: f'{v}/'
    else:
        base = f'https://cdimage.ubuntu.com/{flavour or "ubuntu"}/releases/'
        tail = lambda v: f'{v}/release/'
    for v in ubuntu_lts(links(base)):
        name = f'{flavour or "ubuntu"}-{v}-desktop-{arch_pkg}.iso'
        url = f'{base}{tail(v)}{name}'
        if head(url):
            return url, f'{base}{tail(v)}SHA256SUMS'
    return None


def edition(iso, pattern):
    m = re.search(pattern, iso['url'])
    return m.group(1) if m else None


def resolve_mint(iso):
    ed = edition(iso, r'linuxmint-[\d.]+-(\w+)-64bit')
    if not ed:
        return None
    base = 'https://mirrors.edge.kernel.org/linuxmint/stable/'
    for v in sorted((n.rstrip('/') for n in links(base) if re.fullmatch(r'\d+(\.\d+)?/', n)), key=vkey, reverse=True):
        url = f'{base}{v}/linuxmint-{v}-{ed}-64bit.iso'
        if head(url):
            return url, f'{base}{v}/sha256sum.txt'
    return None


def resolve_debian(iso):
    ed = edition(iso, r'debian-live-[\d.]+-amd64-(\w+)\.iso')
    if not ed:
        return None
    base = 'https://cdimage.debian.org/debian-cd/current-live/amd64/iso-hybrid/'
    name = next((n for n in links(base) if re.fullmatch(rf'debian-live-[\d.]+-amd64-{ed}\.iso', n)), None)
    return (base + name, base + 'SHA256SUMS') if name else None


def resolve_fedora(iso):
    arch = 'x86_64' if iso['arch'] == 'x86_64' else 'aarch64'
    root = 'https://dl.fedoraproject.org/pub/fedora/linux/releases/'
    for rel in sorted((n.rstrip('/') for n in links(root) if re.fullmatch(r'\d+/', n)), key=int, reverse=True)[:3]:
        base = f'{root}{rel}/Workstation/{arch}/iso/'
        try:
            names = links(base)
        except Exception:
            continue
        iso_name = next((n for n in names if re.fullmatch(rf'Fedora-Workstation-Live-{rel}-[\d.]+\.{arch}\.iso', n)), None)
        chk = next((n for n in names if n.endswith('-CHECKSUM')), None)
        if iso_name and chk and head(base + iso_name):
            return base + iso_name, base + chk
    return None


def resolve_omarchy(iso):
    m = re.search(r'/omarchy-(\d+)\.(\d+)\.(\d+)\.iso$', iso['url'])
    if not m:
        return None
    a, b, c = map(int, m.groups())
    candidates = [(a + 1, 0, z) for z in range(3)] + [(a, b + 1, z) for z in range(6)] + [(a, b, c + z) for z in range(1, 11)]
    for v in sorted(candidates, reverse=True):
        url = f'https://iso.omarchy.org/omarchy-{v[0]}.{v[1]}.{v[2]}.iso'
        if head(url):
            return url, url + '.sha256'
    return None


def resolve(distro_id, iso):
    if distro_id in ('ubuntu', 'xubuntu', 'kubuntu'):
        return resolve_ubuntu_like(distro_id, iso)
    return {'linux-mint': resolve_mint, 'debian': resolve_debian, 'fedora': resolve_fedora, 'omarchy': resolve_omarchy}.get(distro_id, lambda i: None)(iso)


def main():
    check = '--check' in sys.argv
    data = json.loads(CATALOG.read_text(encoding='utf-8'))
    changed, broken = [], []
    for d in data['distros']:
        entries = [(d['id'], i) for i in d.get('isos', [])]
        entries += [(f"{d['id']}/{v['id']}", i) for v in d.get('variants', []) for i in v.get('isos', [])]
        for name, iso in entries:
            label = f"{name} {iso['arch']}"
            try:
                found = resolve(d['id'], iso)  # Bazzite is rolling: same name, only the size moves
            except Exception as e:
                print(f'{label}: lookup failed ({e}); keeping the current entry')
                found = None
            if found:
                url, chk = found
                if url != iso['url']:
                    changed.append(label)
                    print(f"{label}: {iso['url'].rsplit('/', 1)[-1]} -> {url.rsplit('/', 1)[-1]}")
                    if not check:
                        iso['url'], iso['checksumUrl'], iso['fileName'] = url, chk, url.rsplit('/', 1)[-1]
                        iso['sizeBytes'] = head(url)
                    continue
            size = head(iso['url'])
            if size is None:
                broken.append(label)
                print(f"{label}: DEAD LINK {iso['url']}")
            elif size != iso.get('sizeBytes') and not check:
                iso['sizeBytes'] = size  # rolling images (Bazzite) change size without changing name
                changed.append(label)
                print(f'{label}: size updated')
    if changed and not check:
        CATALOG.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(f'{len(changed)} updated, {len(broken)} dead')
    return 1 if broken or (check and changed) else 0


if __name__ == '__main__':
    sys.exit(main())
