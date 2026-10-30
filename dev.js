// npm run dev -> starts API (3001) + web (5173). Ctrl+C stops both.
const { spawn } = require('node:child_process');
const path = require('node:path');

const kids = ['api', 'web'].map((dir) =>
  spawn(process.execPath, ['--env-file=../.env', 'server.js'], { cwd: path.join(__dirname, dir), stdio: 'inherit' })
    .on('exit', (code) => { console.log(`${dir} stopped (${code})`); stop(code ?? 1); }));

// one dies -> stop the other too, so nothing is left holding a port
function stop(code) { for (const k of kids) k.kill(); process.exit(code); }
process.on('SIGINT', () => stop(0));
