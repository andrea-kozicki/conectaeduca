// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: Apache-2.0
// ConectaEduca GA-06: mocked browser regressions for Ferret Scan 2.4.3 UI.
// Uses the isolated patch-applied app.js prefix, never connects to EP126.
'use strict';
const fs = require('node:fs');
const assert = require('node:assert/strict');
const test = require('node:test');
const vm = require('node:vm');

if (!process.env.FERRET_APP_JS) throw new Error('FERRET_APP_JS is required');
const source = fs.readFileSync(process.env.FERRET_APP_JS, 'utf8');

function makeUI() {
  const dom = new Map();
  const timeouts = [];
  let responses = [];
  let nextResponse = 0;
  class Element {
    constructor() {
      this.id = '';
      this.textContent = '';
      this.className = '';
      this.attrs = {};
      this.children = [];
      this.parent = null;
      this.style = {};
      this.checked = false;
      this.value = 'MEDIUM';
      this.files = [];
      this.classList = {add() {}, remove() {}};
    }
    appendChild(child) { this.children.push(child); child.parent = this; return child; }
    insertBefore(child, before) {
      const position = before ? this.children.indexOf(before) : -1;
      if (position < 0) return this.appendChild(child);
      this.children.splice(position, 0, child);
      child.parent = this;
      return child;
    }
    get firstChild() { return this.children[0] || null; }
    querySelector(selector) {
      if (selector === '.container-content') return this.children.find(c => c.className === 'container-content') || null;
      return null;
    }
    remove() {
      if (this.parent) this.parent.children = this.parent.children.filter(c => c !== this);
      this.parent = null;
    }
    setAttribute(key, value) { this.attrs[key] = value; }
    getAttribute(key) { return this.attrs[key]; }
    addEventListener(type, callback) { this.handlers = this.handlers || {}; this.handlers[type] = callback; }
  }
  for (const id of ['alerts', 'scanForm', 'resultsContainer', 'progressContainer', 'exportFormat',
    'fileInput', 'scanButton', 'progressFill', 'progressText',
    'confidenceSelect', 'verboseCheck', 'recursiveCheck']) dom.set(id, new Element());
  const coverageContent = new Element();
  coverageContent.className = 'container-content';
  dom.get('resultsContainer').appendChild(coverageContent);
  const exportButton = new Element();
  let exportCalls = 0;
  const document = {
    querySelector: selector => selector === '[data-action="exportResults"]' ? exportButton : null,
    createElement: () => new Element(),
    getElementById: id => {
      if (id === 'ce-scan-status') return dom.get('alerts').children.find(c => c.id === id) || null;
      if (id === 'ce-results-coverage') return coverageContent.children.find(c => c.id === id) || null;
      return dom.get(id) || new Element();
    },
  };
  const ctx = {
    window: {}, document, console,
    setTimeout: fn => { timeouts.push(fn); return timeouts.length; },
    FormData: class { append() {} },
    getSelectedChecks: () => 'ALL',
    filterNewFindings: async () => {},
    updateDisplay: () => {},
    fetch: async (url) => {
      if (url === '/export') { exportCalls++; throw new Error('Unapproved export request in test'); }
      if (nextResponse >= responses.length) throw new Error('Unexpected scan request');
      const reply = responses[nextResponse++];
      if (reply.error) throw new Error(reply.error);
      return {
        ok: reply.status >= 200 && reply.status < 300,
        status: reply.status,
        json: async () => {
          if (reply.jsonError) throw new Error('malformed JSON');
          return reply.body;
        },
      };
    },
  };
  vm.createContext(ctx);
  vm.runInContext(source, ctx, { filename: process.env.FERRET_APP_JS });
  return {
    document, ctx, dom,
    queue(replies) {
      responses = replies;
      nextResponse = 0;
      return replies.map((_, i) => ({file:{name:'synthetic'+i+'.txt'}}));
    },
    async scan(replies) { return ctx.processScan(this.queue(replies)); },
    timedAlerts() { return dom.get('alerts').children.filter(x => x.id !== 'ce-scan-status'); },
    status() { return document.getElementById('ce-scan-status'); },
    banner() { return document.getElementById('ce-results-coverage'); },
    exportDisabled() { return exportButton.disabled; },
    getExportCalls() { return exportCalls; },
    flushTimeouts() { while (timeouts.length) timeouts.shift()(); },
    async submit(replies) {
      const queue = this.queue(replies);
      dom.get('fileInput').files = queue.map(x => x.file);
      await dom.get('scanForm').handlers.submit({preventDefault() {}});
    },
  };
}
const ok = (results=[], extras={}) => ({status:200, body:{success:true, results, ...extras}});
const bad = (status=403) => ({status, body:{error:'denied'}});

async function assertInconclusive(replies, detail) {
  const ui = makeUI();
  await ui.scan(replies);
  const warning = ui.status();
  assert.ok(warning, 'Persistent inconclusive status required');
  assert.match(warning.textContent, /Scan inconclusive/);
  if (detail) assert.match(warning.textContent, detail);
  assert.equal(warning.attrs.role, 'alert');
  assert.equal(warning.attrs['aria-live'], 'assertive');
  assert.equal(ui.timedAlerts().some(el => el.className.includes('success')), false);
  ui.flushTimeouts();
  assert.strictEqual(ui.status(), warning, 'Warning must remain after timeouts');
}

test('fila vazia nunca vira limpa', async () => assertInconclusive([], /0\/0/));
test('HTTP 403 inconclusivo persistente', async () => assertInconclusive([bad(403)], /1 request\(s\) failed/));
test('HTTP 500 inconclusivo persistente', async () => assertInconclusive([bad(500)]));
test('timeout inconclusivo persistente', async () => assertInconclusive([{error:'timeout'}]));
test('success false inconclusivo', async () => assertInconclusive([{status:200, body:{success:false,error:'denied'}}]));
test('success string nao e true', async () => assertInconclusive([{status:200, body:{success:'true',results:[]}}]));
test('success true sem results inconclusivo', async () => assertInconclusive([{status:200, body:{success:true}}]));
test('results null inconclusivo', async () => assertInconclusive([{status:200, body:{success:true,results:null}}]));
test('results objeto inconclusivo', async () => assertInconclusive([{status:200, body:{success:true,results:{}}}]));
test('results string inconclusivo', async () => assertInconclusive([{status:200, body:{success:true,results:'found'}}]));
test('JSON invalido inconclusivo', async () => assertInconclusive([{status:200, jsonError:true}]));
test('sucesso parcial e HTTP 403', async () => assertInconclusive([ok(),bad(403)],/1\/2 files succeeded/));
test('sucesso parcial com achado', async () => assertInconclusive([ok([{type:'synthetic'}]),bad(403)], /1 finding\(s\) observed/));
test('incomplete true sem achados', async () => assertInconclusive([ok([],{incomplete:true,incomplete_reason:'budget'})],/1 incomplete scan/));
test('incomplete true com achados', async () => assertInconclusive([ok([{type:'synthetic'}],{incomplete:true})]));

test('sucesso limpo legitimo', async () => {
  const ui = makeUI(); await ui.scan([ok()]);
  assert.equal(ui.status(), null);
  assert.equal(ui.timedAlerts().some(x=>x.textContent.includes('No sensitive data found')),true);
});
test('sucesso com achado', async () => {
  const ui = makeUI(); await ui.scan([ok([{type:'synthetic'}])]);
  assert.equal(ui.status(), null);
  assert.equal(ui.timedAlerts().some(x=>x.textContent.includes('1 findings detected')),true);
});
test('nova analise limpa remove aviso anterior', async () => {
  const ui = makeUI(); await ui.scan([bad(403)]); assert.ok(ui.status());
  await ui.scan([ok()]); assert.equal(ui.status(), null);
});
test('duas falhas mantem apenas um aviso', async () => {
  const ui = makeUI(); await ui.scan([bad(403)]); await ui.scan([bad(500)]);
  assert.equal(ui.dom.get('alerts').children.filter(x=>x.id==='ce-scan-status').length,1);
});
test('erro inesperado de renderizacao no submit', async () => {
  const ui = makeUI(); ui.ctx.filterNewFindings = async()=>{ throw new Error('renderer failed'); };
  await ui.submit([ok()]);
  assert.match(ui.status()?.textContent||'',/Scan inconclusive: renderer failed/);
});

test('v5: no painel, falha gera banner INCONCLUSIVE e export disabled', async () => {
  const ui = makeUI();
  await ui.scan([bad(403)]);
  assert.match(ui.banner()?.textContent || '', /^INCONCLUSIVE/);
  assert.equal(ui.banner().attrs.role, 'status');
  assert.equal(ui.exportDisabled(), true);
  ui.ctx.exportResults();
  assert.equal(ui.getExportCalls(), 0);
});
test('v5: scan valido vazio gera COMPLETED, export desabilitado', async () => {
  const ui = makeUI();
  await ui.scan([ok()]);
  assert.match(ui.banner()?.textContent || '', /^COMPLETED/);
  assert.equal(ui.exportDisabled(), true);
});
test('v5: scan parcial com achados nao permite exportacao', async () => {
  const ui = makeUI();
  await ui.scan([ok([{type:'synthetic'}]), bad(403)]);
  assert.match(ui.banner()?.textContent || '', /INCONCLUSIVE/);
  assert.equal(ui.exportDisabled(), true);
  ui.ctx.exportResults();
  assert.equal(ui.getExportCalls(), 0);
});
test('v5: incompleto de backend bloqueia export', async () => {
  const ui = makeUI();
  await ui.scan([ok([{type:'synthetic'}], {incomplete:true})]);
  assert.equal(ui.exportDisabled(), true);
  ui.ctx.exportResults();
  assert.equal(ui.getExportCalls(), 0);
});
test('v5: scan com achados legitimos habilita export', async () => {
  const ui = makeUI();
  await ui.scan([ok([{type:'synthetic'}])]);
  assert.match(ui.banner()?.textContent || '', /^COMPLETED/);
  assert.equal(ui.exportDisabled(), false);
});
test('v5: nova analise sem recarregar remove banner antigo', async () => {
  const ui = makeUI();
  await ui.scan([bad(403)]);
  const before = ui.banner();
  assert.ok(before);
  await ui.scan([ok()]);
  assert.notStrictEqual(ui.banner(), before);
  assert.match(ui.banner()?.textContent || '', /^COMPLETED/);
  assert.equal(ui.status(), null);
});
