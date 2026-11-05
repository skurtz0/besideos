// Remote MCP server (streamable HTTP, stateless, no auth) so AI assistants can look up distros and install steps.
// Cloudflare Pages Function: served at https://besideos.com/mcp. Reads the catalog the site itself ships.

const PROTOCOL = '2025-06-18';
const SUPPORTED = ['2025-06-18', '2025-03-26', '2024-11-05'];
const SERVER = { name: 'besideos', title: 'BesideOS', version: '1.0.0' };
const CATALOG_PATH = '/assets/assets/catalog/catalog.json';

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, GET, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Accept, Mcp-Session-Id, MCP-Protocol-Version',
};

const TOOLS = [
  {
    name: 'list_distros',
    title: 'List installable operating systems',
    description: 'Lists every operating system BesideOS can install beside the current one, without a USB stick.',
    inputSchema: {
      type: 'object',
      properties: { family: { type: 'string', enum: ['linux', 'windows'], description: 'Only this family.' } },
    },
    annotations: { readOnlyHint: true, openWorldHint: false },
  },
  {
    name: 'get_distro',
    title: 'Get one operating system',
    description: 'Details, requirements, official download page and ISO links of one operating system.',
    inputSchema: {
      type: 'object',
      properties: { id: { type: 'string', description: 'Id from list_distros, e.g. "ubuntu" or "linux-mint".' } },
      required: ['id'],
    },
    annotations: { readOnlyHint: true, openWorldHint: false },
  },
  {
    name: 'recommend_distro',
    title: 'Recommend an operating system',
    description: 'Suggests installable operating systems for a described need (e.g. "gaming", "old laptop", "coming from Windows", "development").',
    inputSchema: {
      type: 'object',
      properties: { need: { type: 'string', description: 'What the user wants, in plain words.' } },
      required: ['need'],
    },
    annotations: { readOnlyHint: true, openWorldHint: false },
  },
  {
    name: 'get_install_steps',
    title: 'Install steps without a USB stick',
    description: 'The BesideOS steps to install the given operating system next to the current one, and where to get the app.',
    inputSchema: {
      type: 'object',
      properties: { id: { type: 'string', description: 'Id from list_distros.' } },
      required: ['id'],
    },
    annotations: { readOnlyHint: true, openWorldHint: false },
  },
];

const KEYWORDS = {
  gaming: ['bazzite', 'cachyos', 'pop-os', 'fedora'],
  game: ['bazzite', 'cachyos', 'pop-os'],
  oyun: ['bazzite', 'cachyos', 'pop-os'],
  beginner: ['ubuntu', 'linux-mint', 'zorin-os'],
  'new to linux': ['ubuntu', 'linux-mint', 'zorin-os'],
  yeni: ['ubuntu', 'linux-mint', 'zorin-os'],
  windows: ['linux-mint', 'zorin-os', 'kubuntu'],
  'old': ['xubuntu', 'mx-linux', 'linux-mint'],
  eski: ['xubuntu', 'mx-linux', 'linux-mint'],
  lightweight: ['xubuntu', 'mx-linux'],
  hafif: ['xubuntu', 'mx-linux'],
  developer: ['fedora', 'ubuntu', 'omarchy', 'pop-os'],
  geliştirici: ['fedora', 'ubuntu', 'omarchy', 'pop-os'],
  stable: ['debian', 'linux-mint', 'ubuntu'],
  kararlı: ['debian', 'linux-mint', 'ubuntu'],
  arch: ['manjaro', 'cachyos', 'omarchy'],
  kde: ['kubuntu', 'opensuse', 'cachyos'],
  server: ['windows-server-2025', 'debian'],
  sunucu: ['windows-server-2025', 'debian'],
  retro: ['windows-xp', 'windows-7'],
  nostalgia: ['windows-xp', 'windows-7'],
};

async function loadCatalog(request, env) {
  const url = new URL(CATALOG_PATH, request.url);
  const res = env && env.ASSETS ? await env.ASSETS.fetch(url) : await fetch(url);
  if (!res.ok) throw new Error('catalog unavailable');
  return (await res.json()).distros;
}

const brief = (d) => ({ id: d.id, name: d.name, family: d.family, tagline: d.tagline, desktop: d.desktop, bestFor: d.bestFor });

function textResult(obj, isError = false) {
  return { content: [{ type: 'text', text: typeof obj === 'string' ? obj : JSON.stringify(obj, null, 2) }], isError };
}

function findDistro(distros, id) {
  const key = String(id || '').toLowerCase().trim();
  return distros.find((d) => d.id === key || d.name.toLowerCase() === key);
}

function recommend(distros, need) {
  const q = String(need || '').toLowerCase();
  const score = new Map();
  for (const [word, ids] of Object.entries(KEYWORDS)) {
    if (!q.includes(word)) continue;
    ids.forEach((id, i) => score.set(id, (score.get(id) || 0) + (ids.length - i)));
  }
  for (const d of distros) {
    const hay = `${d.name} ${d.tagline} ${d.bestFor} ${d.desktop}`.toLowerCase();
    for (const w of q.split(/[^\p{L}\p{N}]+/u).filter((w) => w.length > 3)) {
      if (hay.includes(w)) score.set(d.id, (score.get(d.id) || 0) + 1);
    }
  }
  let picks = [...score.entries()].sort((a, b) => b[1] - a[1]).slice(0, 3).map(([id]) => distros.find((d) => d.id === id)).filter(Boolean);
  if (!picks.length) picks = ['ubuntu', 'linux-mint', 'fedora'].map((id) => distros.find((d) => d.id === id)).filter(Boolean);
  return picks.map(brief);
}

async function callTool(name, args, request, env) {
  const distros = await loadCatalog(request, env);
  switch (name) {
    case 'list_distros':
      return textResult(distros.filter((d) => !args.family || d.family === args.family).map(brief));
    case 'get_distro': {
      const d = findDistro(distros, args.id);
      if (!d) return textResult(`Unknown id "${args.id}". Call list_distros.`, true);
      return textResult({
        ...brief(d),
        basedOn: d.basedOn,
        description: d.description,
        look: d.look,
        requirements: d.requirements,
        license: d.license,
        officialDownloadPage: d.downloadPage,
        isos: (d.isos || []).map((i) => ({ arch: i.arch, url: i.url, checksumUrl: i.checksumUrl, sizeBytes: i.sizeBytes })),
        userSuppliedIso: d.userSuppliedIso,
        page: `https://besideos.com/#/distros/${d.id}`,
      });
    }
    case 'recommend_distro':
      return textResult({ need: args.need, suggestions: recommend(distros, args.need) });
    case 'get_install_steps': {
      const d = findDistro(distros, args.id);
      if (!d) return textResult(`Unknown id "${args.id}". Call list_distros.`, true);
      return textResult({
        name: d.name,
        getTheApp: 'https://besideos.com/ (Windows .exe, Linux .deb/.rpm/.pkg.tar.zst)',
        steps: d.guide,
        note: 'No USB stick needed. Nothing is changed on the disk until the user confirms the plan; "Undo" restores the previous state.',
      });
    }
    default:
      return textResult(`Unknown tool ${name}`, true);
  }
}

const rpcError = (id, code, message) => ({ jsonrpc: '2.0', id: id ?? null, error: { code, message } });

async function handle(msg, request, env) {
  if (!msg || msg.jsonrpc !== '2.0' || typeof msg.method !== 'string') return rpcError(msg && msg.id, -32600, 'Invalid request');
  const isNotification = msg.id === undefined;
  switch (msg.method) {
    case 'initialize': {
      const asked = msg.params && msg.params.protocolVersion;
      return {
        jsonrpc: '2.0', id: msg.id,
        result: {
          protocolVersion: SUPPORTED.includes(asked) ? asked : PROTOCOL,
          capabilities: { tools: { listChanged: false } },
          serverInfo: SERVER,
          instructions: 'BesideOS installs Linux (or an old Windows) beside the current OS without a USB stick. Use recommend_distro to pick, get_distro for details, get_install_steps for the steps.',
        },
      };
    }
    case 'ping':
      return { jsonrpc: '2.0', id: msg.id, result: {} };
    case 'tools/list':
      return { jsonrpc: '2.0', id: msg.id, result: { tools: TOOLS } };
    case 'tools/call': {
      const p = msg.params || {};
      if (!TOOLS.some((t) => t.name === p.name)) return rpcError(msg.id, -32602, `Unknown tool: ${p.name}`);
      try {
        return { jsonrpc: '2.0', id: msg.id, result: await callTool(p.name, p.arguments || {}, request, env) };
      } catch (e) {
        return { jsonrpc: '2.0', id: msg.id, result: textResult('Catalog temporarily unavailable.', true) };
      }
    }
    default:
      return isNotification ? null : rpcError(msg.id, -32601, `Method not found: ${msg.method}`);
  }
}

const json = (body, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json', ...CORS } });

export async function onRequest({ request, env }) {
  if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: CORS });
  if (request.method === 'GET') {
    return new Response('BesideOS MCP server. POST JSON-RPC 2.0 here (streamable HTTP). See https://besideos.com/llms.txt\n', {
      status: 405, headers: { Allow: 'POST, OPTIONS', 'Content-Type': 'text/plain', ...CORS },
    });
  }
  if (request.method !== 'POST') return new Response(null, { status: 405, headers: { Allow: 'POST, OPTIONS', ...CORS } });

  let body;
  try {
    body = await request.json();
  } catch {
    return json(rpcError(null, -32700, 'Parse error'), 400);
  }
  if (Array.isArray(body)) {
    const out = (await Promise.all(body.slice(0, 20).map((m) => handle(m, request, env)))).filter(Boolean);
    return out.length ? json(out) : new Response(null, { status: 202, headers: CORS });
  }
  const res = await handle(body, request, env);
  return res ? json(res) : new Response(null, { status: 202, headers: CORS });
}
