// Read-only source provenance check. No fetching, installing or executing EUI.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const manifest = require('../contracts/eui-9.4.json');
const root = process.argv[2];
if (!root) throw new Error('Usage: npm run audit:upstream -- /absolute/path/to/EUI-source');
for (const source of manifest.sources) {
  const officialPath = path.join(root, source.path);
  const file = fs.existsSync(officialPath) ? officialPath : path.join(root, source.cacheFile);
  const bytes = fs.readFileSync(file);
  const actual = crypto.createHash('sha1').update(`blob ${bytes.length}\0`).update(bytes).digest('hex');
  if (actual !== source.sha) throw new Error(`Source changed or incomplete: ${source.path}`);
}
console.log(`EUI ${manifest.version}: ${manifest.sources.length} source files match reviewed Git blobs.`);
console.log('Provenance only. Private hooks are not an official API; in-game release gates remain OPEN.');
