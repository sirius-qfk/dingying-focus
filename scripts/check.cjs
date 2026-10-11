const fs = require('node:fs');
const path = require('node:path');
const parser = require('luaparse');
const root = path.resolve(__dirname, '..');
const toc = fs.readFileSync(path.join(root, 'EllesmereUIGradient.toc'), 'utf8');
const files = toc.split(/\r?\n/).filter(line => line.endsWith('.lua')).map(line => line.replaceAll('\\', '/'));
for (const file of files) {
  const source = fs.readFileSync(path.join(root, file), 'utf8');
  parser.parse(source, { luaVersion: '5.1' });
  if (!file.startsWith('Integrations/') && file !== 'Bootstrap.lua' && /\b(?:EllesmereUI|EllesmereUIDB|_EAB_Apply|_ECME_Apply)\b/.test(source)) {
    throw new Error(`EUI dependency escaped its integration layer: ${file}`);
  }
}
if (/^## Dependencies:.*EllesmereUI/m.test(toc)) throw new Error('Core must load without EUI');
const core = fs.readFileSync(path.join(root, 'Core.lua'), 'utf8');
if (toc.match(/^## Version: (.+)$/m)[1] !== core.match(/G.version = "([^"]+)"/)[1]) throw new Error('Version mismatch');
const tests = fs.readdirSync(path.join(root, 'tests')).filter(file => file.endsWith('.lua'));
for (const file of tests.map(file => `tests/${file}`)) {
  parser.parse(fs.readFileSync(path.join(root, file), 'utf8'), { luaVersion: '5.1' });
}
console.log(`Lua 5.1 syntax OK: ${files.length} addon files + ${tests.length} test files; TOC paths exist.`);
