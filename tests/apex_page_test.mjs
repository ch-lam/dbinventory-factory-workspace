#!/usr/bin/env node
// ============================================================================
// apex_page_test.mjs
// ----------------------------------------------------------------------------
// Opens the deployed APEX pages in a real browser and fails when one of them
// renders an error.
//
// WHY THIS EXISTS
//   APEXlang validation proves the .apx compiles; it never opens a page. Page 71
//   passed five validations and still died on first render, because an attribute
//   the .apx cannot express fell back to a default that breaks at runtime.
//   T_001_apex_page_smoke.sql covers the database side -- region SQL, plugin
//   attributes, LOV references. This covers the half neither of them reaches:
//   what the user actually gets.
//
// WHY A BROWSER
//   Logging in over raw HTTP does not work. APEX protects page submission with a
//   salt, a single-use p_page_submission_id and protected values, all assembled
//   by JavaScript. Three curl conventions were tried and all came back to the
//   login page. A real browser runs that JavaScript, so it stays correct across
//   APEX upgrades instead of re-implementing a protocol that moves.
//
//   Edge is driven over the Chrome DevTools Protocol using Node's built-in
//   WebSocket: no npm dependency, which matters on a machine with no registry
//   access.
//
// USAGE
//   node tests/apex_page_test.mjs                  every page in PAGES
//   node tests/apex_page_test.mjs --pages 70,71    after a targeted change
//   node tests/apex_page_test.mjs --profile RSSI   as another user
//   node tests/apex_page_test.mjs --head           watch it run
//
//   Configuration comes from .env at the repository root; see .env.example.
//   Exits non-zero when a page fails, so it can gate a deployment script.
// ============================================================================

import { spawn } from 'node:child_process';
import { mkdtempSync, readFileSync, existsSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const sleep = ms => new Promise(r => setTimeout(r, ms));

// ---------------------------------------------------------------- configuration

function loadEnv () {
  const path = join(ROOT, '.env');
  if (!existsSync(path)) {
    fail(`.env not found at ${path}. Copy .env.example and fill it in.`);
  }
  const env = {};
  for (const line of readFileSync(path, 'utf8').split(/\r?\n/)) {
    const m = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*)$/);
    if (m) env[m[1]] = m[2].trim().replace(/^["']|["']$/g, '');
  }
  return env;
}

function fail (msg) { console.error('ERROR: ' + msg); process.exit(2); }

const args = process.argv.slice(2);
const argOf = name => {
  const i = args.indexOf('--' + name);
  return i >= 0 ? args[i + 1] : null;
};

const env      = loadEnv();
const profile  = (argOf('profile') || 'ADMIN').toUpperCase();
const baseUrl  = (env.APEX_BASE_URL || '').replace(/\/+$/, '');
const appId    = env.APEX_APP_ID || '100';
const user     = env[`APEX_USER_${profile}`];
const password = env[`APEX_PASS_${profile}`];
const browser  = env.APEX_TEST_BROWSER || 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe';
const headless = !args.includes('--head');

if (!baseUrl) fail('APEX_BASE_URL is not set in .env');
if (!user || !password) {
  fail(`profile ${profile} has no credentials in .env `
     + `(expected APEX_USER_${profile} and APEX_PASS_${profile})`);
}

// Pages to open. Kept here rather than read from the dictionary so the test says
// out loud what it covers, and so a page can be excluded with a reason.
const PAGES = argOf('pages')
  ? argOf('pages').split(',').map(s => s.trim()).filter(Boolean)
  : ['1', '20', '30', '31', '40', '70', '71', '90', '10002'];

// Modal pages cannot be opened by URL. APEX answers "Dialog page N cannot be
// rendered successfully" whatever the page actually does, which reads as a broken
// page and hides the real one. They have to be reached the way a user reaches
// them: open the parent, then follow the link.
const MODAL_PARENT = { '71': '70', '91': '90' };

// What counts as a broken page. The first entry is the failure that motivated
// this test.
const ERROR_PATTERNS = [
  /has to have a valid/i,
  /\bORA-\d{5}/,
  /apex_error_code/i,
  /Internal Server Error/i,
  /Contact your application administrator/i
];

// ---------------------------------------------------------------- CDP plumbing

async function waitForCdp (port, tries = 40) {
  for (let i = 0; i < tries; i++) {
    try {
      const r = await fetch(`http://127.0.0.1:${port}/json/version`);
      if (r.ok) return r.json();
    } catch { /* not up yet */ }
    await sleep(500);
  }
  throw new Error(`the browser never exposed CDP on port ${port}`);
}

function connect (wsUrl) {
  const ws = new WebSocket(wsUrl);
  let id = 0;
  const pending = new Map();
  ws.onmessage = e => {
    const m = JSON.parse(e.data);
    if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); }
  };
  const ready = new Promise((res, rej) => { ws.onopen = res; ws.onerror = rej; });
  const send = (method, params = {}) => new Promise(res => {
    const i = ++id;
    pending.set(i, res);
    ws.send(JSON.stringify({ id: i, method, params }));
  });
  return { ws, ready, send };
}

// Evaluate an expression in the page and return its value.
async function evalIn (send, expression) {
  const r = await send('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true });
  if (r.result?.exceptionDetails) {
    throw new Error(r.result.exceptionDetails.text || 'evaluation failed');
  }
  return r.result?.result?.value;
}

// Navigate and wait until the document is complete. Polling the ready state is
// deliberate: APEX pages finish rendering after the load event, and waiting on a
// CDP lifecycle event alone reads the page too early.
async function goto (send, url, timeoutMs = 30000) {
  await send('Page.navigate', { url });
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    await sleep(400);
    try {
      if (await evalIn(send, 'document.readyState') === 'complete') {
        await sleep(700);           // let APEX finish its own initialisation
        return;
      }
    } catch { /* navigating, context swapped */ }
  }
  throw new Error(`page did not finish loading within ${timeoutMs / 1000}s`);
}

// ---------------------------------------------------------------- the test

const port = 9400 + Math.floor(Math.random() * 400);
const userDataDir = mkdtempSync(join(tmpdir(), 'apex-test-'));
let browserProc, ws;
let failures = 0;

let skipped = 0;
const report = [];
// status: 'ok' | 'fail' | 'skip'. A skip is a page the test could not reach, not
// a page that works: it is counted and shown, never folded into the passes.
const record = (page, status, detail) => {
  if (status === 'fail') failures++;
  if (status === 'skip') skipped++;
  report.push({ page, status, detail });
  const tag = status === 'ok' ? 'ok  ' : status === 'skip' ? 'skip' : 'FAIL';
  console.log(`  ${tag}  page ${String(page).padEnd(5)} ${detail || ''}`);
};

try {
  console.log(`APEX page test - ${baseUrl} - application ${appId} - profile ${profile}`);
  console.log('-'.repeat(78));

  browserProc = spawn(browser, [
    ...(headless ? ['--headless=new'] : []),
    `--remote-debugging-port=${port}`,
    `--user-data-dir=${userDataDir}`,
    '--ignore-certificate-errors',   // apex.internal presents a self-signed cert
    '--no-first-run', '--no-default-browser-check',
    'about:blank'
  ], { stdio: 'ignore' });
  browserProc.on('error', e => fail(`cannot start the browser (${browser}): ${e.message}`));

  await waitForCdp(port);
  const target = await (await fetch(`http://127.0.0.1:${port}/json/new?about:blank`, { method: 'PUT' })).json();
  const conn = connect(target.webSocketDebuggerUrl);
  ws = conn.ws;
  await conn.ready;
  const send = conn.send;
  await send('Page.enable');
  await send('Runtime.enable');

  // ---- log in -------------------------------------------------------------
  await goto(send, `${baseUrl}/f?p=${appId}`);

  const onLogin = await evalIn(send, '!!document.getElementById("P9999_USERNAME")');
  if (!onLogin) fail('the login page did not appear - check APEX_BASE_URL and APEX_APP_ID');

  // Set the values the way the page would, then submit through APEX's own
  // function so the salt and submission id are assembled by APEX itself.
  await evalIn(send, `
    (function () {
      document.getElementById('P9999_USERNAME').value = ${JSON.stringify(user)};
      document.getElementById('P9999_PASSWORD').value = ${JSON.stringify(password)};
      if (window.apex && apex.page && apex.page.submit) { apex.page.submit('LOGIN'); }
      else { document.querySelector('form').submit(); }
      return true;
    })()`);
  await sleep(4000);
  const deadline = Date.now() + 25000;
  while (Date.now() < deadline) {
    if (await evalIn(send, 'document.readyState').catch(() => null) === 'complete') break;
    await sleep(400);
  }

  const stillLogin = await evalIn(send, '!!document.getElementById("P9999_USERNAME")');
  if (stillLogin) {
    const msg = await evalIn(send, `
      (document.querySelector('.t-Alert--danger, .a-Notification--error, #t_Alert_Notification')
        || {}).innerText || ''`);
    fail('login failed for profile ' + profile + (msg ? ' - ' + msg.trim().slice(0, 200) : ''));
  }

  // Carry the session id explicitly. `f?p=100:70` with an empty session slot
  // starts a NEW, unauthenticated session and the page bounces straight back to
  // the login screen -- which looks exactly like a broken page if you do not
  // know to look for it. APEX puts the id either in ?session= on a friendly URL
  // or in the third colon-separated position of an f?p= URL.
  const landedOn = await evalIn(send, 'location.href');
  const session = (landedOn.match(/[?&]session=(\d+)/)
                || landedOn.match(/f\?p=\d+:[^:]*:(\d+)/)
                || [])[1]
    || await evalIn(send, '(window.apex && apex.env && apex.env.APP_SESSION) || ""');

  if (!session) fail('logged in but could not determine the session id from ' + landedOn);
  console.log(`  logged in as ${user} (session ${session})\n`);

  // ---- open each page -----------------------------------------------------
  for (const page of PAGES) {
    try {
      const parent = MODAL_PARENT[page];
      if (parent) {
        // Open the parent, then click the first link that targets this page --
        // the same route a user takes. The dialog renders into the parent
        // document, so everything below still applies.
        await goto(send, `${baseUrl}/f?p=${appId}:${parent}:${session}`);
        // Friendly-URL applications do not render a dialog link as f?p=...; they
        // render an action such as
        //   #action$a-dialog-open?url=...&pageId=71&tmpl=modal-dialog
        // so match on the page id in any of the shapes APEX emits.
        const clicked = await evalIn(send, `
          (function () {
            var re = new RegExp('(pageId=${page}\\\\b)|(:${page}:)|(p${page}_)', 'i');
            var a = Array.from(document.querySelectorAll('a[href]'))
              .find(function (x) { return re.test(x.getAttribute('href') || '') || re.test(x.href || ''); });
            if (!a) return false;
            a.click();
            return true;
          })()`);
        if (!clicked) {
          record(page, 'skip', 'no link on page ' + parent + ' to open it - nothing to open it from?');
          continue;
        }
        await sleep(4000);
      } else {
        await goto(send, `${baseUrl}/f?p=${appId}:${page}:${session}`);
      }

      // Falling back to the login screen means the session died, which would
      // otherwise be reported as a clean page.
      if (await evalIn(send, '!!document.getElementById("P9999_USERNAME")')) {
        record(page, 'fail', 'bounced back to the login screen - session lost');
        continue;
      }

      // A modal dialog renders inside a same-origin iframe, so the parent's
      // innerText does not contain it. Read both, or a broken dialog looks clean.
      const text = await evalIn(send, `
        (function () {
          var out = document.body ? document.body.innerText : '';
          for (var f of document.querySelectorAll('iframe')) {
            try { out += '\\n' + (f.contentDocument.body.innerText || ''); } catch (e) { /* cross-origin */ }
          }
          return out;
        })()`);
      const title = await evalIn(send, `
        (function () {
          for (var f of document.querySelectorAll('iframe')) {
            try { if (f.contentDocument.title) return f.contentDocument.title; } catch (e) {}
          }
          return document.title;
        })()`);
      const alert = await evalIn(send, `
        (function () {
          var sel = '.t-Alert--danger, .a-Notification--error, #t_Alert_Notification';
          var e = document.querySelector(sel);
          if (e) return e.innerText;
          for (var f of document.querySelectorAll('iframe')) {
            try { var x = f.contentDocument.querySelector(sel); if (x) return x.innerText; } catch (err) {}
          }
          return '';
        })()`);

      // "Page not found" means the page exists in source but was never imported.
      // Reported apart from a rendering error on purpose: after every source
      // change you would otherwise get failures that only mean "not deployed
      // yet", and a test people learn to ignore protects nothing.
      if (/Page "?\d+"? not found/i.test(text || '')) {
        record(page, 'fail', 'not deployed in application ' + appId + ' - import it first');
        continue;
      }

      const hit = ERROR_PATTERNS.find(re => re.test(text || ''));
      if (hit) {
        // Report the most useful line, not merely the first match. APEX renders
        // a specific cause ("P71_UPLOAD has to have a valid BLOB column as
        // source.") next to a generic "Contact your application administrator.";
        // reporting the generic one tells the reader nothing.
        const lines = (text || '').split('\n').map(l => l.trim()).filter(Boolean);
        const generic = /^(Contact your application administrator|Technical Info)/i;
        const detail = lines.find(l => ERROR_PATTERNS.some(re => re.test(l)) && !generic.test(l))
                    || lines.find(l => hit.test(l))
                    || '';
        record(page, 'fail', detail.slice(0, 130));
      } else if (alert && alert.trim()) {
        record(page, 'fail', 'alert: ' + alert.trim().split('\n')[0].slice(0, 110));
      } else if (!title) {
        record(page, 'fail', 'rendered without a title');
      } else {
        record(page, 'ok', title.slice(0, 60));
      }
    } catch (e) {
      record(page, 'fail', e.message.slice(0, 120));
    }
  }

  console.log('-'.repeat(78));
  console.log(`${report.length} page(s) attempted, ${failures} failure(s)`
            + (skipped ? `, ${skipped} skipped` : ''));
  if (failures > 0) {
    const notDeployed = report.filter(r => r.status === 'fail' && /not deployed/.test(r.detail || ''));
    if (notDeployed.length) {
      console.log(`\n${notDeployed.length} page(s) exist in source but not in the application:`);
      console.log('import them, then run this again. That is a deployment gap, not a bug.');
    }
    if (failures > notDeployed.length) {
      console.log('\nThe other failures are real rendering errors: the page was opened as a');
      console.log('user would. Check the detail above, then the builder.');
    }
  }
  if (skipped > 0) {
    console.log('\nA skipped page was never opened, so it is NOT known to work. Modal');
    console.log('pages need a row in their parent report to have a link to follow;');
    console.log('load some data, or pass --pages to test them once one exists.');
  }
  process.exitCode = failures > 0 ? 1 : 0;

} catch (e) {
  console.error('ERROR: ' + e.message);
  process.exitCode = 2;
} finally {
  try { ws?.close(); } catch {}
  try { browserProc?.kill(); } catch {}
  await sleep(500);
  try { rmSync(userDataDir, { recursive: true, force: true }); } catch {}
}
