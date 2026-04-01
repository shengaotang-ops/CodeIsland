#!/usr/bin/env bun
// Compute Claude Code buddy bones using Bun.hash (matches Claude Code exactly)
// Usage: bun buddy-bones.js
// Output: JSON with species, rarity, eye, hat, shiny, stats

const fs = require('fs');
const path = require('path');
const os = require('os');

const configPath = path.join(os.homedir(), '.claude.json');
let config;
try {
  config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
} catch {
  console.error(JSON.stringify({ error: 'Cannot read ~/.claude.json' }));
  process.exit(1);
}

const userId = config.oauthAccount?.accountUuid ?? config.userID ?? 'anon';
const SALT = 'friend-2026-401';
const key = userId + SALT;

const h = Number(BigInt(Bun.hash(key)) & 0xffffffffn);

function mulberry32(seed) {
  let a = seed >>> 0;
  return function() {
    a |= 0;
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const rng = mulberry32(h);

const SPECIES = ['duck','goose','blob','cat','dragon','octopus','owl','penguin','turtle','snail','ghost','axolotl','capybara','cactus','robot','rabbit','mushroom','chonk'];
const RARITIES = ['common','uncommon','rare','epic','legendary'];
const RARITY_WEIGHTS = {common:60,uncommon:25,rare:10,epic:4,legendary:1};
const EYES = ['·','✦','×','◉','@','°'];
const HATS = ['none','crown','tophat','propeller','halo','wizard','beanie','tinyduck'];
const STAT_NAMES = ['DEBUGGING','PATIENCE','CHAOS','WISDOM','SNARK'];
const RARITY_FLOOR = {common:5,uncommon:15,rare:25,epic:35,legendary:50};

function pick(rng, arr) { return arr[Math.floor(rng() * arr.length)]; }

const total = Object.values(RARITY_WEIGHTS).reduce((a,b)=>a+b,0);
let roll = rng() * total;
let rarity = 'common';
for (const r of RARITIES) { roll -= RARITY_WEIGHTS[r]; if (roll < 0) { rarity = r; break; } }

const species = pick(rng, SPECIES);
const eye = pick(rng, EYES);
const hat = rarity === 'common' ? 'none' : pick(rng, HATS);
const shiny = rng() < 0.01;

const floor = RARITY_FLOOR[rarity];
const peak = pick(rng, STAT_NAMES);
let dump = pick(rng, STAT_NAMES);
while (dump === peak) dump = pick(rng, STAT_NAMES);

const stats = {};
for (const name of STAT_NAMES) {
  if (name === peak) stats[name] = Math.min(100, floor + 50 + Math.floor(rng() * 30));
  else if (name === dump) stats[name] = Math.max(1, floor - 10 + Math.floor(rng() * 15));
  else stats[name] = floor + Math.floor(rng() * 40);
}

const companion = config.companion || {};

console.log(JSON.stringify({
  name: companion.name || 'Unknown',
  personality: companion.personality || '',
  species,
  rarity,
  eye,
  hat,
  shiny,
  stats,
  hatchedAt: companion.hatchedAt || null
}));
