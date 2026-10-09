import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, existsSync, readlinkSync, rmSync, copyFileSync, realpathSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const revision = 'a'.repeat(40);
const deployScript = fileURLToPath(new URL('../bin/deploy', import.meta.url));
const composeCli = spawnSync('docker', ['compose', 'version'], { encoding: 'utf8' });

function runDeploy(failure = '') {
  const project = realpathSync(mkdtempSync(join(tmpdir(), 'proser-deploy-')));
  const release = join(project, '.deploy/releases/new');
  const old = join(project, '.deploy/releases/old');
  const mockBin = join(project, 'mock-bin');
  const log = join(project, 'commands.jsonl');
  for (const dir of [join(release, 'bin'), old, mockBin, join(project, 'secrets'), join(project, 'geoip')]) mkdirSync(dir, { recursive: true });
  writeFileSync(join(project, '.env'), 'PRESERVE=existing\n');
  writeFileSync(join(project, 'secrets/license-private.pem'), 'existing-private-key');
  writeFileSync(join(project, 'compose.yml'), 'name: proser-studio-dashboard\n');
  writeFileSync(join(old, 'compose.yml'), 'name: proser-studio-dashboard\n');
  writeFileSync(join(release, 'compose.yml'), 'name: proser-studio-dashboard\n');
  copyFileSync(deployScript, join(release, 'bin/deploy'));
  // Persist a previous successful snapshot, just as the real deployment does.
  spawnSync('ln', ['-s', 'releases/old', join(project, '.deploy/current')]);
  const fakeDocker = `#!${process.execPath}
import { appendFileSync } from 'node:fs';
const args = process.argv.slice(2);
appendFileSync(process.env.DEPLOY_TEST_LOG, JSON.stringify(args) + '\\n');
const fail = process.env.DEPLOY_TEST_FAILURE;
const rollback = args.some(arg => arg.endsWith('compose.rollback.yml'));
if (args[0] === 'inspect') {
  console.log(args[2] === '{{.Image}}' ? 'sha256:previous' : 'healthy');
} else if (args.includes('ps')) {
  console.log('container-' + args.at(-1));
} else if (args.includes('pg_dump')) {
  if (fail === 'backup') process.exit(1);
  console.log('-- database snapshot');
} else if (args[0] === 'build' && fail === 'build') {
  process.exit(1);
} else if (args.includes('db:migrate') && fail === 'migrate') {
  process.exit(1);
} else if (args.includes('up') && !rollback && fail === 'health') {
  process.exit(1);
} else if (args[0] === 'exec' && fail === 'public') {
  process.exit(1);
}
`;
  writeFileSync(join(mockBin, 'docker'), fakeDocker, { mode: 0o755 });
  writeFileSync(join(mockBin, 'flock'), '#!/bin/sh\n[ "$DEPLOY_TEST_FAILURE" != lock ]\n', { mode: 0o755 });
  // The production server uses GNU mv; emulate its atomic -T rename on macOS.
  writeFileSync(join(mockBin, 'mv'), `#!${process.execPath}\nimport { renameSync } from 'node:fs';\nrenameSync(process.argv.at(-2), process.argv.at(-1));\n`, { mode: 0o755 });
  const result = spawnSync('bash', [join(release, 'bin/deploy'), project, revision], {
    env: { ...process.env, PATH: `${mockBin}:${process.env.PATH}`, DEPLOY_TEST_LOG: log, DEPLOY_TEST_FAILURE: failure },
    encoding: 'utf8',
  });
  const commands = existsSync(log) ? readFileSync(log, 'utf8').trim().split('\n').filter(Boolean).map(JSON.parse) : [];
  return { project, release, result, commands, clean: () => rmSync(project, { recursive: true, force: true }) };
}

test('deploy builds the exact snapshot, backs up, migrates and replaces only web', () => {
  const run = runDeploy();
  try {
    assert.equal(run.result.status, 0, run.result.stderr);
    const { commands } = run;
    const build = commands.findIndex(args => args[0] === 'build');
    const backup = commands.findIndex(args => args.includes('pg_dump'));
    const migration = commands.findIndex(args => args.includes('db:migrate'));
    const update = commands.findIndex(args => args.includes('up'));
    assert.ok(build < backup && backup < migration && migration < update);
    assert.equal(commands[build].at(-1), run.release);
    assert.ok(commands[update].includes('--no-deps'));
    assert.ok(commands[update].includes('--no-build'));
    assert.ok(commands[update].includes('--wait'));
    assert.equal(commands[update].at(-1), 'web');
    assert.ok(commands.every(args => !args.includes('down') && !args.includes('prune')));
    assert.equal(readFileSync(join(run.project, '.env'), 'utf8'), 'PRESERVE=existing\n');
    assert.equal(readFileSync(join(run.project, 'secrets/license-private.pem'), 'utf8'), 'existing-private-key');
    assert.equal(readlinkSync(join(run.project, '.deploy/current')), 'releases/new');
    assert.equal(readFileSync(join(run.project, '.deploy/revision'), 'utf8').trim(), revision);
  } finally { run.clean(); }
});

test('migration options are accepted by the real Docker Compose CLI', {
  skip: composeCli.status !== 0 && !process.env.CI ? 'Docker Compose CLI unavailable' : false,
}, () => {
  assert.equal(composeCli.status, 0, 'Docker Compose CLI is required for deploy validation in CI');
  const run = runDeploy();
  try {
    assert.equal(run.result.status, 0, run.result.stderr);
    const migration = run.commands.find(args => args.includes('db:migrate'));
    assert.ok(migration, 'Migration command was not executed');
    const options = migration.slice(migration.indexOf('run') + 1, migration.indexOf('web'));
    assert.ok(options.includes('--rm'));
    assert.ok(options.includes('--no-deps'), 'Migrations must not restart database or Redis');
    // --help checks the real CLI parser without connecting to a daemon or
    // starting containers. The command mock alone accepts unsupported flags.
    const parsed = spawnSync('docker', ['compose', 'run', ...options, '--help'], { encoding: 'utf8' });
    assert.equal(parsed.status, 0, parsed.stderr);
  } finally { run.clean(); }
});

for (const failure of ['build', 'backup', 'migrate', 'lock']) {
  test(`failure during ${failure} leaves the running web untouched`, () => {
    const run = runDeploy(failure);
    try {
      assert.notEqual(run.result.status, 0);
      assert.ok(run.commands.every(args => !args.includes('up')));
      assert.equal(readlinkSync(join(run.project, '.deploy/current')), 'releases/old');
      assert.equal(existsSync(join(run.project, '.deploy/revision')), false);
    } finally { run.clean(); }
  });
}

for (const failure of ['health', 'public']) {
  test(`failure during ${failure} restores the previous image and Compose`, () => {
    const run = runDeploy(failure);
    try {
      assert.notEqual(run.result.status, 0);
      const restore = run.commands.find(args => args.some(arg => arg.endsWith('compose.rollback.yml')) && args.includes('up'));
      assert.ok(restore);
      assert.ok(restore.includes(join(run.project, '.deploy/releases/old/compose.yml')));
      assert.ok(restore.includes('--no-deps'));
      assert.equal(restore.at(-1), 'web');
      assert.match(readFileSync(join(run.release, 'compose.rollback.yml'), 'utf8'), /image: sha256:previous/);
      assert.equal(readlinkSync(join(run.project, '.deploy/current')), 'releases/old');
      assert.equal(existsSync(join(run.project, '.deploy/revision')), false);
      assert.ok(run.commands.every(args => !args.includes('db:rollback') && !args.includes('down')));
    } finally { run.clean(); }
  });
}
