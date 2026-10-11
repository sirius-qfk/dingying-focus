const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const root = path.resolve(__dirname, '..');
const name = 'EllesmereUIGradient';
const toc = fs.readFileSync(path.join(root, `${name}.toc`), 'utf8');
const version = toc.match(/^## Version: (.+)$/m)[1];
const files = [`${name}.toc`, ...toc.split(/\r?\n/).filter(line => line.endsWith('.lua')).map(line => line.replaceAll('\\', '/')), 'README.md', 'docs/IN_GAME_CHECKLIST.md', 'docs/ARCHITECTURE.md', 'docs/COMPATIBILITY.md'];
const dist = path.join(root, 'dist');
fs.mkdirSync(dist, { recursive: true });
const staging = fs.mkdtempSync(path.join(require('node:os').tmpdir(), 'eui-gradient-package-'));
for (const file of files) {
  const target = path.join(staging, name, file);
  fs.mkdirSync(path.dirname(target), { recursive: true });
  fs.copyFileSync(path.join(root, file), target);
}
const archive = path.join(dist, `${name}-${version}.zip`);
// Build a fresh archive, never update an old ZIP with potentially stale entries.
const tempArchive = path.join(staging, 'addon.zip');
execFileSync('/usr/bin/zip', ['-qr', tempArchive, name], { cwd: staging });
fs.copyFileSync(tempArchive, archive);
// Verify the deliverable, not only the working tree: exact allowlist + byte equality.
execFileSync('/usr/bin/unzip', ['-tq', archive]);
const members = execFileSync('/usr/bin/unzip', ['-Z1', archive], { encoding: 'utf8' }).trim().split('\n').filter(entry => !entry.endsWith('/'));
const expected = files.map(file => `${name}/${file}`).sort();
if (JSON.stringify(members.sort()) !== JSON.stringify(expected)) throw new Error('Unexpected ZIP contents');
for (const file of files) {
  const bytes = execFileSync('/usr/bin/unzip', ['-p', archive, `${name}/${file}`]);
  if (!bytes.equals(fs.readFileSync(path.join(root, file)))) throw new Error(`ZIP mismatch: ${file}`);
}
console.log(archive);
console.log(`Verified ${files.length} files byte-for-byte. No Node dependencies or EUI source included.`);
