#!/usr/bin/env node
'use strict';
const { spawnSync, spawn } = require('child_process');
const path = require('path');
const fs = require('fs');

const REX = process.env.REX_BIN_DIR
  ? path.join(process.env.REX_BIN_DIR, 'rex')
  : 'rex';

const LOG = '/tmp/choose-tree.log';

function rx(s) {
  return s?.host ? [REX, '-S', s.host] : [REX];
}

function run(args) {
  const [cmd, ...rest] = args;
  return spawnSync(cmd, rest, { encoding: 'utf8' });
}

// --- Finish: close pane and switch ---
function finish(choice, cid, isGo = false) {
  if (!isGo) {
    esc('\x1b[?1004l\x1b[?25h\x1b[2J\x1b[H');
    try { process.stdin.setRawMode(false); } catch {}
  }

  const cmds = [];
  const block = process.env.REX_BLOCK, sess = process.env.REX_SESSION;
  if (block && sess) cmds.push([REX, 'block', 'close', '-s', sess, block]);

  if (choice?.defer) {
    cmds.push(choice.defer);
  } else if (choice?.type === 'switch') {
    cmds.push([REX, '-C', cid, 'do', 'client.host.switch']);
  } else if (choice?.type === 'new') {
    cmds.push([REX, '-C', cid, 'do', 'session.new']);
  } else if (choice?.type === 'select') {
    const { sessionId, windowId, host, active } = choice;
    if (host) {
      const cmd = remoteSelect(host, cid, sessionId);
      if (cmd) {
        cmds.push(cmd);
        if (windowId !== active) {
          cmds.push(['sleep', '0.5']);
          cmds.push([...cmd, `window_id=${windowId}`]);
        }
      }
    } else {
      // Use Lua queuing (server-side, no Remote Control required)
      const lua = `rex.client.queue("session.select",{session_id="${sessionId}",window_id="${windowId}"})`;
      cmds.push([REX, '-C', cid, 'do', '-e', lua]);
    }
  }

  if (cmds.length) {
    const script = cmds.map(c => c.map(p => `'${p.replace(/'/g, "'\\''")}'`).join(' ')).join(' ; ');
    fs.appendFileSync(LOG, `---\nchoice=${JSON.stringify(choice)}\nscript=${script}\n`);
    spawn('/bin/sh', ['-c', `${script} >>${LOG} 2>&1`], { detached: true, stdio: 'ignore' }).unref();
  }

  process.exit(0);
}

function remoteSelect(host, cid, sessionId) {
  try {
    const local = JSON.parse(run([REX, 'client', 'ls', '--json']).stdout)?.clients || [];
    const myLabel = local.find(c => c.client_id === cid)?.info?.label;
    const remote = JSON.parse(run([REX, '-S', host, 'client', 'ls', '--json']).stdout)?.clients || [];
    const apps = remote.filter(c => c.info?.kind === 'app');
    const match = myLabel ? apps.filter(c => c.info?.label === myLabel) : [];
    const target = (match.length ? match : apps.length === 1 ? apps : [])[0]?.client_id;
    if (!target) return null;
    return [REX, '-S', host, '-C', target, 'do', 'session.select', `session_id=${sessionId}`];
  } catch { return null; }
}

// --go subcommand: used by find_window to jump to a remote session
if (process.argv[2] === '--go') {
  const [, , , host, sessionId, windowId, active, cid] = process.argv;
  finish({ type: 'select', sessionId, windowId, host: host || null, active }, cid, true);
  return;
}

// --- Interactive UI ---
const sessions = JSON.parse(process.argv[2]);
const clientId = process.argv[3];
const folded = new Set();
let cursor = 0;
let status = '';

function getRows() {
  const out = [];
  const attached = sessions.some(s => s.at);
  const multi = attached || new Set(sessions.map(s => s.host || '')).size > 1;
  let lastHost = Symbol();
  for (let si = 0; si < sessions.length; si++) {
    const s = sessions[si];
    const host = s.host || '';
    if (multi && host !== lastHost) {
      out.push({ kind: 'heading', label: host || s.at || 'local' });
      lastHost = host;
    }
    out.push({ kind: 'session', si });
    if (!folded.has(s.id)) {
      for (let ti = 0; ti < s.tabs.length; ti++) out.push({ kind: 'tab', si, ti });
    }
  }
  if (attached) {
    out.push({ kind: 'heading', label: 'home' });
    out.push({ kind: 'back' });
  }
  return out.length ? out : [{ kind: 'empty' }];
}

// --- Terminal helpers ---
function esc(s) { process.stdout.write(s); }
const W = () => process.stdout.columns || 80;
const H = () => process.stdout.rows || 24;

function draw() {
  const rows = getRows();
  const w = W(), h = H();
  const top = Math.max(0, cursor - h + 2);
  esc('\x1b[H');
  for (let y = 0; y < h - 1; y++) {
    const ri = top + y;
    esc(`\x1b[${y + 1};1H\x1b[2K`);
    if (ri >= rows.length) continue;
    const row = rows[ri];
    const s = row.si != null ? sessions[row.si] : null;
    let text, bold = false, dim = false;
    if (row.kind === 'empty') {
      text = 'no sessions: n makes one'; dim = true;
    } else if (row.kind === 'heading') {
      text = `── ${row.label} ` + '─'.repeat(Math.max(0, w - row.label.length - 5)); dim = true;
    } else if (row.kind === 'back') {
      text = '⇄ switch host…'; dim = true;
    } else if (row.kind === 'session') {
      const mark = folded.has(s.id) ? '+' : '-';
      const c = s.tabs.length;
      text = `${mark} ${row.si + 1}: ${s.label}: ${c} tab${c === 1 ? '' : 's'}`;
      if (s.current) text += ' (attached)';
      bold = true;
    } else {
      const tab = s.tabs[row.ti];
      const br = row.ti === s.tabs.length - 1 ? '└─>' : '├─>';
      text = `  ${br} ${row.ti + 1}: ${tab.name}`;
      if (tab.id === s.active) text += '*';
    }
    const sel = ri === cursor;
    const attr = (bold ? '\x1b[1m' : dim ? '\x1b[2m' : '') + (sel ? '\x1b[7m' : '');
    esc(attr + text.slice(0, w - 1).padEnd(w - 1) + '\x1b[0m');
  }
  esc(`\x1b[${h};1H\x1b[2K\x1b[2m`);
  const foot = status || 'j/k move  1-9 session  J/K reorder  h/l fold  r rename  x kill  n new  H host  enter go  q quit';
  esc(foot.slice(0, w - 1) + '\x1b[0m');
  status = '';
}

// --- Key reading ---
let keyWaiter = null;
const keyQueue = [];

process.stdin.on('data', data => {
  const key = parseKey(typeof data === 'string' ? data : data.toString('binary'));
  if (keyWaiter) { const r = keyWaiter; keyWaiter = null; r(key); }
  else keyQueue.push(key);
});

function parseKey(raw) {
  if (!raw.startsWith('\x1b')) return raw[0] ?? '';
  if (raw === '\x1b') return '\x1b';
  if (raw[1] === '[') {
    const c = raw[2];
    if (c === 'I') return 'focus-in';
    if (c === 'O') return 'focus-out';
    if (c === 'A') return 'up';
    if (c === 'B') return 'down';
    if (c === 'C') return 'right';
    if (c === 'D') return 'left';
  }
  return '\x1b';
}

function readKey() {
  if (keyQueue.length) return Promise.resolve(keyQueue.shift());
  return new Promise(r => { keyWaiter = r; });
}

// --- Prompt ---
async function prompt(label, value = '') {
  let text = value;
  while (true) {
    esc(`\x1b[${H()};1H\x1b[2K\x1b[?25h${label} ${text}`);
    const key = await readKey();
    if (key === '\r' || key === '\n') { esc('\x1b[?25l'); return text.trim(); }
    if (key === '\x1b') { esc('\x1b[?25l'); return null; }
    if (key === '\x7f' || key === '\b') text = text.slice(0, -1);
    else if (key === '\x15') text = '';
    else if (key === '\x17') text = text.trimEnd().replace(/\S+\s*$/, '');
    else if (key.length === 1 && key >= ' ') text += key;
  }
}

// --- Confirm ---
async function confirm(q) {
  esc(`\x1b[${H()};1H\x1b[2K\x1b[1m${q} (y/n)\x1b[0m`);
  while (true) {
    const key = await readKey();
    if (key === 'y' || key === 'Y') return true;
    if (key === 'n' || key === 'N' || key === '\x1b' || key === 'q') return false;
  }
}

// --- Reorder ---
function reorder(si, kind, ti, step) {
  const s = sessions[si];
  if (kind === 'session') {
    const other = si + step;
    if (other < 0 || other >= sessions.length) return null;
    if ((sessions[other].host || '') !== (s.host || '')) return null;
    if (run([...rx(s), 'session', 'move', s.id, step > 0 ? '--after' : '--before', sessions[other].id]).status)
      { status = 'move failed'; return null; }
    [sessions[si], sessions[other]] = [sessions[other], sessions[si]];
    return { kind: 'session', si: other, ti: null };
  } else {
    const other = ti + step;
    if (other < 0 || other >= s.tabs.length) return null;
    if (run([...rx(s), 'window', 'move', '-s', s.id, s.tabs[ti].id, step > 0 ? '--after' : '--before', s.tabs[other].id]).status)
      { status = 'move failed'; return null; }
    [s.tabs[ti], s.tabs[other]] = [s.tabs[other], s.tabs[ti]];
    return { kind: 'tab', si, ti: other };
  }
}

// --- Kill ---
async function kill(si, kind, ti) {
  const s = sessions[si];
  if (kind === 'session') {
    if (!await confirm(`kill session ${s.label}?`)) return null;
    if (s.current) return { defer: [REX, 'session', 'kill', s.id] };
    if (run([...rx(s), 'session', 'kill', s.id]).status) { status = 'kill failed'; return null; }
    sessions.splice(si, 1);
    return sessions.length === 0 ? 'done' : null;
  } else {
    const tab = s.tabs[ti];
    if (!await confirm(`kill tab ${tab.name}?`)) return null;
    if (s.current && s.tabs.length === 1) return { defer: [REX, 'session', 'kill', s.id] };
    if (run([...rx(s), 'window', 'close', '-s', s.id, tab.id]).status) { status = 'kill failed'; return null; }
    s.tabs.splice(ti, 1);
    if (!s.tabs.length) sessions.splice(si, 1);
    else if (tab.id === s.active) s.active = s.tabs[0].id;
    return sessions.length === 0 ? 'done' : null;
  }
}

// --- Main loop ---
async function main() {
  if (!process.stdin.isTTY) process.exit(1);
  process.stdin.setRawMode(true);
  process.stdin.resume();
  process.stdin.setEncoding('binary');

  // Find initial cursor at the active tab of the current session
  const rows0 = getRows();
  for (let i = 0; i < rows0.length; i++) {
    const r = rows0[i];
    if (r.kind === 'tab') {
      const s = sessions[r.si];
      if (s.current && s.tabs[r.ti].id === s.active) { cursor = i; break; }
    } else if (r.kind === 'session' && sessions[r.si]?.current) {
      cursor = i;
    }
  }

  esc('\x1b[?25l\x1b[2J\x1b[?1004h'); // hide cursor, clear, enable focus events
  process.stdout.on('resize', draw);

  while (true) {
    const rows = getRows();
    cursor = Math.max(0, Math.min(cursor, rows.length - 1));
    draw();

    const key = await readKey();
    if (key === 'focus-in') continue;
    if (key === 'focus-out' || key === '\x1b') { finish(null, clientId); return; }

    const row = rows[cursor];
    const s = row.si != null ? sessions[row.si] : null;
    const { kind } = row;

    if (key === 'q' || key === '\x03') { finish(null, clientId); return; }
    if (key === 'j' || key === 'down') { cursor = (cursor + 1) % rows.length; continue; }
    if (key === 'k' || key === 'up') { cursor = (cursor - 1 + rows.length) % rows.length; continue; }
    if (key === 'g') { cursor = 0; continue; }
    if (key === 'G') { cursor = rows.length - 1; continue; }
    if (key === 'n') { finish({ type: 'new' }, clientId); return; }
    if (key === 'H') { finish({ type: 'switch' }, clientId); return; }

    if (key >= '1' && key <= '9') {
      const n = parseInt(key) - 1;
      if (n < sessions.length) {
        const sv = sessions[n];
        finish({ type: 'select', sessionId: sv.id, windowId: sv.active, host: sv.host || null, active: sv.active }, clientId);
      }
      continue;
    }

    if (kind === 'empty' || kind === 'heading') continue;
    if (kind === 'back' && (key === '\r' || key === '\n')) { finish({ type: 'switch' }, clientId); return; }

    if ((key === 'h' || key === 'left') && s) {
      if (kind === 'tab') cursor = getRows().findIndex(r => r.kind === 'session' && r.si === row.si);
      else folded.add(s.id);
    } else if ((key === 'l' || key === 'right') && s) {
      folded.delete(s.id);
    } else if ((key === 'J' || key === 'K') && s) {
      const target = reorder(row.si, kind, row.ti, key === 'J' ? 1 : -1);
      if (target) cursor = getRows().findIndex(r => r.kind === target.kind && r.si === target.si && (target.ti == null || r.ti === target.ti));
    } else if (key === 'r' && s) {
      const cur = kind === 'session' ? s.label : s.tabs[row.ti].name;
      const lbl = await prompt(`rename ${kind}:`, cur);
      if (lbl && lbl !== cur) {
        const cmd = kind === 'session'
          ? [...rx(s), 'session', 'rename', s.id, lbl]
          : [...rx(s), 'window', 'rename', '-s', s.id, s.tabs[row.ti].id, lbl];
        if (run(cmd).status) status = 'rename failed';
        else if (kind === 'session') s.label = lbl;
        else s.tabs[row.ti].name = lbl;
      }
    } else if (key === 'x' && s) {
      const result = await kill(row.si, kind, row.ti);
      if (result === 'done') { finish(null, clientId); return; }
      if (result?.defer) { finish(result, clientId); return; }
    } else if (key === '\r' || key === '\n') {
      if (kind === 'tab') {
        finish({ type: 'select', sessionId: s.id, windowId: s.tabs[row.ti].id, host: s.host || null, active: s.active }, clientId);
        return;
      } else if (kind === 'session') {
        finish({ type: 'select', sessionId: s.id, windowId: s.active, host: s.host || null, active: s.active }, clientId);
        return;
      }
    }
  }
}

main().catch(e => {
  try { esc('\x1b[?25h\x1b[?1004l'); process.stdin.setRawMode(false); } catch {}
  fs.appendFileSync(LOG, `error: ${e}\n`);
  process.exit(1);
});
