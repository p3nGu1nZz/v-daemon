#!/usr/bin/env node
const express = require('express');
const fs = require('fs');
const path = require('path');

const PORT = process.env.MOCK_MCP_PORT || 51823;
const BASE = path.join(__dirname);
const FIXTURES_DIR = path.join(BASE, 'fixtures');
const SCENARIOS_DIR = path.join(BASE, 'scenarios');

let currentScenario = 'default';
let recordedRequests = [];

function loadScenario(name) {
  const p = path.join(SCENARIOS_DIR, name + '.json');
  if (!fs.existsSync(p)) return { mappings: [] };
  return JSON.parse(fs.readFileSync(p, 'utf8'));
}

let scenario = loadScenario(currentScenario);

function matchMapping(body) {
  for (const m of (scenario.mappings || [])) {
    const match = m.match || {};
    let ok = true;
    if (match.type && body.type !== match.type) ok = false;
    if (match.model && body.model !== match.model) ok = false;
    if (ok) return m;
  }
  return null;
}

function readResponse(rel) {
  const p = path.join(FIXTURES_DIR, rel);
  if (!fs.existsSync(p)) return null;
  return JSON.parse(fs.readFileSync(p, 'utf8'));
}

const app = express();
app.use(express.json());

app.get('/health', (req,res)=>res.json({status:'ok'}));
app.get('/models',(req,res) => {
  const mpath = path.join(FIXTURES_DIR,'models.json');
  if (fs.existsSync(mpath)) return res.json(JSON.parse(fs.readFileSync(mpath,'utf8')));
  return res.json({models:[]});
});

app.post('/query',(req,res) => {
  recordedRequests.push({time: new Date().toISOString(), body: req.body});
  const mapping = matchMapping(req.body);
  if (mapping && mapping.response) {
    const resp = readResponse(mapping.response);
    if (resp) return res.json(resp);
  }
  return res.status(404).json({error:'no mapping found'});
});

app.post('/_admin/load-scenario',(req,res) => {
  const name = req.body && req.body.name;
  if (!name) return res.status(400).json({error:'missing name'});
  scenario = loadScenario(name);
  currentScenario = name;
  recordedRequests = [];
  return res.json({loaded:name});
});

app.post('/_admin/reset',(req,res) => { recordedRequests = []; res.json({reset:true}); });
app.get('/_admin/requests',(req,res) => res.json({requests:recordedRequests}));

app.listen(PORT,()=>console.log('mock-mcp listening on',PORT,'scenario=',currentScenario));
