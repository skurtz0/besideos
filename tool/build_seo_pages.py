#!/usr/bin/env python3
"""Writes one crawlable static page per distro (web/distros/<id>/index.html), an index page and web/sitemap.xml.

The Flutter app draws on a canvas under hash routes (/#/distros/ubuntu), which search engines cannot index
page by page. These plain HTML pages carry the same facts and link into the app.
"""
import html
import json
from pathlib import Path

root = Path(__file__).resolve().parent.parent
SITE = 'https://besideos.com'
catalog = json.loads((root / 'assets/catalog/catalog.json').read_text(encoding='utf-8'))['distros']
e = html.escape

STYLE = '''<style>
body{margin:0;background:#181C26;color:#F5F7FA;font:17px/1.6 system-ui,sans-serif}
main{max-width:760px;margin:0 auto;padding:32px 20px 64px}
a{color:#60A5FF}h1{font-size:2rem;margin:.2em 0}h2{margin-top:1.6em}
.btn{display:inline-block;background:#60A5FF;color:#101420;padding:12px 22px;border-radius:14px;font-weight:700;text-decoration:none}
.muted{color:#C0C9DA}footer{margin-top:48px;color:#C0C9DA;font-size:14px}
</style>'''


def page(title, desc, canonical, body, ld):
    return f'''<!DOCTYPE html>
<html lang="tr">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>{e(title)}</title>
<meta name="description" content="{e(desc)}">
<link rel="canonical" href="{canonical}">
<meta name="robots" content="index, follow, max-image-preview:large">
<meta property="og:type" content="website">
<meta property="og:title" content="{e(title)}">
<meta property="og:description" content="{e(desc)}">
<meta property="og:url" content="{canonical}">
<meta property="og:image" content="{SITE}/og-image.png">
<meta name="twitter:card" content="summary_large_image">
<link rel="icon" type="image/png" href="/favicon.png">
<script type="application/ld+json">{json.dumps(ld, ensure_ascii=False)}</script>
{STYLE}
</head>
<body><main>
{body}
<footer><a href="{SITE}/">BesideOS</a> · <a href="{SITE}/distros/">Tüm sistemler</a> · <a href="https://github.com/skurtz0/besideos">GitHub</a> · <a href="https://www.skurtinati.com/">SKURTINATI</a></footer>
</main></body></html>
'''


for d in catalog:
    url = f"{SITE}/distros/{d['id']}/"
    app = f"{SITE}/#/distros/{d['id']}"
    title = f"{d['name']} kurulumu: USB bellek olmadan | BesideOS"
    desc = f"{d['tagline']} {d['name']}'i USB bellek olmadan mevcut sisteminin yanına kur: resmi ISO indirilir, doğrulanır, çift önyükleme hazırlanır."
    steps = ''.join(f"<li><strong>{e(s['title'])}</strong>: {e(s['body'])}</li>" for s in d['guide'])
    reqs = ''.join(f'<li>{e(r)}</li>' for r in d['requirements'])
    body = f'''<p class="muted"><a href="{SITE}/distros/">Sistemler</a> › {e(d['name'])}</p>
<h1>{e(d['name'])}</h1>
<p>{e(d['tagline'])}</p>
<p><a class="btn" href="{app}">BesideOS'ta aç</a></p>
<p>{e(d['description'])}</p>
<h2>Kimler için</h2><p>{e(d['bestFor'])}</p>
<h2>Nasıl görünür</h2><p>{e(d['look'])}</p>
<h2>USB bellek olmadan kurulum</h2><ol>{steps}</ol>
<h2>Gereksinimler</h2><ul>{reqs}</ul>
<p>Resmî indirme sayfası: <a href="{e(d['downloadPage'])}" rel="noopener">{e(d['downloadPage'])}</a><br>Lisans: {e(d['license'])}</p>
<p><a href="{SITE}/">BesideOS</a> Windows ve Linux için ücretsiz, açık kaynaklı bir uygulamadır (MIT).</p>'''
    ld = {'@context': 'https://schema.org', '@type': 'HowTo', 'name': f"{d['name']} USB bellek olmadan nasıl kurulur",
          'description': desc, 'inLanguage': 'tr', 'url': url,
          'step': [{'@type': 'HowToStep', 'name': s['title'], 'text': s['body']} for s in d['guide']]}
    out = root / 'web/distros' / d['id']
    out.mkdir(parents=True, exist_ok=True)
    (out / 'index.html').write_text(page(title, desc, url, body, ld), encoding='utf-8')

items = ''.join(f"<li><a href=\"/distros/{d['id']}/\">{e(d['name'])}</a>: {e(d['tagline'])}</li>" for d in catalog)
idx_body = f'<h1>BesideOS ile kurabileceğin sistemler</h1><p>USB bellek olmadan, mevcut sisteminin yanına.</p><ul>{items}</ul>'
idx_ld = {'@context': 'https://schema.org', '@type': 'ItemList',
          'itemListElement': [{'@type': 'ListItem', 'position': i + 1, 'url': f"{SITE}/distros/{d['id']}/", 'name': d['name']} for i, d in enumerate(catalog)]}
(root / 'web/distros/index.html').write_text(
    page('Kurulabilecek işletim sistemleri | BesideOS', 'Ubuntu, Linux Mint, Fedora, Debian, Windows ve daha fazlası: USB bellek olmadan, BesideOS ile.',
         f'{SITE}/distros/', idx_body, idx_ld), encoding='utf-8')

urls = [(f'{SITE}/', '1.0'), (f'{SITE}/distros/', '0.8')] + [(f"{SITE}/distros/{d['id']}/", '0.7') for d in catalog]
(root / 'web/sitemap.xml').write_text(
    '<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n'
    + ''.join(f'  <url><loc>{u}</loc><changefreq>weekly</changefreq><priority>{p}</priority></url>\n' for u, p in urls)
    + '</urlset>\n', encoding='utf-8')
