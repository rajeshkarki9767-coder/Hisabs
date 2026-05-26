// =====================================================================
// run-self-test.js — runs window.hisabsSelfTest() in a Node sandbox
// =====================================================================
//
// This is a smoke test for the pure-logic helpers inside index.html.
// It does NOT exercise the DOM, network, or any browser-only feature.
// It only validates that the helper functions (DOB validation,
// birthday math, entry math, etc) still behave correctly.
//
// Usage:
//   node .github/scripts/run-self-test.js [path-to-index.html]
//   (defaults to ./index.html)
//
// Exit codes:
//   0 — all self-test checks pass
//   1 — one or more failed
//   2 — bundle could not be loaded at all
//
// Why VM not jsdom: jsdom is 30MB and slow. We don't need DOM emulation,
// just enough stubs that the module-init code doesn't throw before
// our test function is registered. Module-init errors AFTER the test
// function is registered are tolerable — they only happen when init
// code tries to touch real DOM that isn't there in Node, which is
// expected. The test function itself doesn't touch DOM.
// =====================================================================

const fs = require('fs');
const vm = require('vm');
const path = require('path');

const target = process.argv[2] || 'index.html';
if (!fs.existsSync(target)) {
  console.error(`File not found: ${target}`);
  process.exit(2);
}

const src = fs.readFileSync(target, 'utf-8');
const matches = [...src.matchAll(/<script(?![^>]*\bsrc=)[^>]*>([\s\S]*?)<\/script>/g)];
if (matches.length === 0) {
  console.error('No inline <script> blocks found');
  process.exit(2);
}
const combined = matches.map(m => m[1]).join('\n;\n');

// ----- Sandbox with browser stubs -----
// We provide enough of the browser API that module-init code can run
// without throwing before reaching the function-definition lines.
// Functions like hisabsSelfTest() can then be called via the sandbox.

const sandbox = {
  console,
  setTimeout, clearTimeout, setInterval, clearInterval,
  Promise,
  Date, Math, JSON, Object, Array, String, Number, Boolean,
  Map, Set, WeakMap, WeakSet, Symbol,
  Error, TypeError, RangeError, SyntaxError, ReferenceError,
  Intl,
  URL, URLSearchParams,
  TextEncoder, TextDecoder,
  encodeURIComponent, decodeURIComponent,
  parseInt, parseFloat, isNaN, isFinite,
  Buffer,  // for btoa/atob
};

sandbox.window = sandbox;
sandbox.globalThis = sandbox;
sandbox.self = sandbox;

// Document stubs — every call returns a safe no-op
const noopEl = () => ({
  style: {},
  classList: { add() {}, remove() {}, toggle() {}, contains: () => false },
  appendChild: () => {},
  removeChild: () => {},
  setAttribute: () => {},
  getAttribute: () => null,
  removeAttribute: () => {},
  remove: () => {},
  addEventListener: () => {},
  removeEventListener: () => {},
  cloneNode: () => noopEl(),
  querySelectorAll: () => [],
  querySelector: () => null,
  innerHTML: '',
  textContent: '',
  value: '',
  focus: () => {},
  blur: () => {},
});

sandbox.document = {
  getElementById: () => null,
  querySelector: () => null,
  querySelectorAll: () => [],
  addEventListener: () => {},
  removeEventListener: () => {},
  body: { ...noopEl(), classList: { add() {}, remove() {}, contains: () => false }, style: {} },
  documentElement: {
    scrollHeight: 0,
    scrollTop: 0,
    clientWidth: 1000,
    clientHeight: 800,
    setAttribute: () => {},
    getAttribute: () => null,
    style: { setProperty: () => {} },
    classList: { add() {}, remove() {} },
  },
  head: { appendChild: () => {} },
  createElement: () => noopEl(),
  activeElement: null,
  hidden: false,
};

// Storage stubs — backed by an object so reads after writes work
const storage = (initial = {}) => ({
  _store: { ...initial },
  getItem(k) { return this._store[k] != null ? this._store[k] : null; },
  setItem(k, v) { this._store[k] = String(v); },
  removeItem(k) { delete this._store[k]; },
  clear() { this._store = {}; },
  key: () => null,
  get length() { return Object.keys(this._store).length; },
});
sandbox.localStorage = storage();
sandbox.sessionStorage = storage();

sandbox.navigator = { userAgent: 'NodeCI', onLine: true, language: 'en-US', languages: ['en-US'], platform: 'Linux' };
sandbox.location = { hostname: 'localhost', protocol: 'https:', href: '', pathname: '/', hash: '', search: '' };
sandbox.history = { replaceState: () => {}, pushState: () => {} };
sandbox.requestAnimationFrame = (fn) => setTimeout(fn, 0);
sandbox.cancelAnimationFrame = clearTimeout;
sandbox.matchMedia = () => ({ matches: false, addEventListener: () => {}, removeEventListener: () => {} });
sandbox.addEventListener = () => {};
sandbox.removeEventListener = () => {};
sandbox.fetch = () => Promise.reject(new Error('fetch stubbed in CI'));
sandbox.MutationObserver = function () { return { observe() {}, disconnect() {} }; };
sandbox.AudioContext = function () {
  return {
    createOscillator: () => ({ connect() {}, start() {}, stop() {}, disconnect() {}, frequency: { value: 0, setValueAtTime() {}, exponentialRampToValueAtTime() {} } }),
    createGain: () => ({ connect() {}, gain: { value: 0, setValueAtTime() {}, linearRampToValueAtTime() {}, exponentialRampToValueAtTime() {} } }),
    destination: {},
    currentTime: 0,
    state: 'running',
    resume: () => Promise.resolve(),
  };
};
sandbox.webkitAudioContext = sandbox.AudioContext;
sandbox.Notification = { permission: 'default', requestPermission: () => Promise.resolve('denied') };
sandbox.crypto = {
  randomUUID: () => 'uuid-' + Math.random().toString(36).slice(2),
  getRandomValues: (a) => { for (let i = 0; i < a.length; i++) a[i] = Math.floor(Math.random() * 256); return a; },
};
sandbox.btoa = (s) => Buffer.from(s, 'binary').toString('base64');
sandbox.atob = (s) => Buffer.from(s, 'base64').toString('binary');
sandbox.alert = () => {};
sandbox.confirm = () => false;
sandbox.prompt = () => null;
sandbox.scrollTo = () => {};
sandbox.scrollBy = () => {};
sandbox.innerWidth = 1000;
sandbox.innerHeight = 800;
sandbox.scrollX = 0;
sandbox.scrollY = 0;
sandbox.devicePixelRatio = 1;
sandbox.indexedDB = { open: () => ({ onsuccess: null, onerror: null }) };

// Stub the Supabase client factory so the auth-state code path doesn't throw
sandbox.supabase = {
  createClient: () => ({
    auth: {
      onAuthStateChange: () => ({ data: { subscription: { unsubscribe: () => {} } } }),
      getSession: () => Promise.resolve({ data: { session: null } }),
      getUser: () => Promise.resolve({ data: { user: null } }),
      signOut: () => Promise.resolve(),
    },
    channel: () => ({ on: function () { return this; }, subscribe: () => ({ unsubscribe: () => {} }) }),
    from: () => ({
      select: () => ({ eq: () => ({ data: [], error: null }) }),
      upsert: () => Promise.resolve({ error: null }),
      delete: () => ({ eq: () => Promise.resolve({ error: null }) }),
    }),
    removeChannel: () => {},
    rpc: () => Promise.resolve({ data: null, error: null }),
  }),
};

vm.createContext(sandbox);

// Run the bundle. Some module-init code will throw because it expects
// a real DOM — that's OK, our test function only needs the function
// definitions to be in scope, and those land before any DOM-touching
// init runs.
try {
  vm.runInContext(combined, sandbox, { timeout: 10000, displayErrors: false });
} catch (e) {
  // Module-init error AFTER hisabsSelfTest is defined is acceptable.
  // We'll know if the test function is missing in the next check.
}

const hasFn = vm.runInContext('typeof window.hisabsSelfTest', sandbox);
if (hasFn !== 'function') {
  console.error('hisabsSelfTest is not defined — bundle is broken or missing the test suite');
  process.exit(2);
}

let result;
try {
  result = vm.runInContext('window.hisabsSelfTest({verbose: false})', sandbox, { timeout: 10000 });
} catch (e) {
  console.error('Self-test threw:', e.message);
  process.exit(1);
}

console.log(`Self-test: ${result.passed}/${result.total} passed, ${result.failed} failed`);

if (result.failed > 0) {
  console.log('\n-- Re-running with verbose output to show failures --\n');
  try {
    vm.runInContext('window.hisabsSelfTest({verbose: true})', sandbox);
  } catch (_) {}
  process.exit(1);
}

process.exit(0);
