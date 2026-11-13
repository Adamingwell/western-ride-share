import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { routeGroups } from '../worker/communities.mjs';

const html = (await readFile('worker/index.html', 'utf8'))
  .replace('/* ROUTE_GROUPS */ []', JSON.stringify(routeGroups));
const messaging = await readFile('worker/messages.mjs', 'utf8');
const worker = await readFile('worker/index.mjs', 'utf8');
await mkdir('dist/server', { recursive: true });
await writeFile('dist/server/index.js', [
  'const html = ' + JSON.stringify(html) + ';',
  'const communities = new Set(' + JSON.stringify(routeGroups.flatMap(([, towns]) => towns)) + ');',
  messaging,
  worker
].join('\n'));
