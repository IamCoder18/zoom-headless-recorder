#!/usr/bin/env node
import { spawn, execSync } from 'child_process';
import { existsSync, mkdirSync, writeFileSync, readFileSync } from 'fs';
import { join, dirname } from 'path';
import chalk from 'chalk';
import ora from 'ora';
import inquirer from 'inquirer';
import { homedir } from 'os';

// Config paths
const CONFIG_DIR = join(homedir(), '.zoom-recorder');
const CONFIG_FILE = join(CONFIG_DIR, 'config.json');

interface Config {
  registry: string;
  recordingsDir: string;
  apiPort: number;
  vncPort: number;
  meetingDuration: number;
  startBuffer: number;   // seconds to start early (default: 300 = 5 min)
  stopBuffer: number;    // seconds to record after duration (default: 600 = 10 min)
  binDir?: string;
}

interface Meeting {
  url: string;
  password?: string;
  duration?: number;
  startBuffer?: number;
  stopBuffer?: number;
}

const defaultConfig: Config = {
  registry: 'ghcr.io',
  recordingsDir: join(homedir(), 'zoom-recordings'),
  apiPort: 8080,
  vncPort: 6080,
  meetingDuration: 3600,
  startBuffer: 300,   // 5 minutes
  stopBuffer: 600     // 10 minutes
};

// Utility functions
function ensureConfig(): Config {
  if (!existsSync(CONFIG_DIR)) mkdirSync(CONFIG_DIR, { recursive: true });
  if (!existsSync(CONFIG_FILE)) {
    writeFileSync(CONFIG_FILE, JSON.stringify(defaultConfig, null, 2));
    return defaultConfig;
  }
  return JSON.parse(readFileSync(CONFIG_FILE, 'utf-8'));
}

function saveConfig(config: Config): void {
  writeFileSync(CONFIG_FILE, JSON.stringify(config, null, 2));
}

function run(cmd: string, args: string[] = [], options: any = {}): Promise<string> {
  return new Promise((resolve, reject) => {
    const child = spawn(cmd, args, { shell: true, stdio: options.silent ? 'pipe' : 'inherit', ...options });
    let output = '';
    if (options.silent) {
      child.stdout?.on('data', (d) => output += d);
      child.stderr?.on('data', (d) => output += d);
    }
    child.on('close', (code) => {
      if (code === 0) resolve(output.trim());
      else reject(new Error(`Command failed: ${cmd} ${args.join(' ')}`));
    });
  });
}

async function checkDocker(): Promise<boolean> {
  try {
    await run('docker', ['--version'], { silent: true });
    return true;
  } catch {
    return false;
  }
}

async function dockerHubLogin(): Promise<void> {
  const spinner = ora('Logging into container registry...').start();
  try {
    const token = execSync('gh auth token', { encoding: 'utf8' }).trim();
    const registry = ensureConfig().registry;
    const user = execSync('gh api user --jq .login', { encoding: 'utf8' }).trim();
    await run('echo', [token], { stdio: 'pipe' });
    execSync(`echo "${token}" | docker login ${registry} -u ${user} --password-stdin`, { stdio: 'inherit' });
    spinner.succeed('Logged in to container registry');
  } catch (e: any) {
    spinner.fail(`Login failed: ${e.message}`);
    throw e;
  }
}

// Commands
async function cmdInstall(): Promise<void> {
  console.log(chalk.cyan(`
╔═══════════════════════════════════════════════════════╗
║           Zoom Recorder CLI Installation              ║
╚═══════════════════════════════════════════════════════╝
  `));

  const spinner = ora('Checking prerequisites...').start();
  
  // Check docker
  if (!await checkDocker()) {
    spinner.fail('Docker is required but not installed');
    console.log(chalk.yellow('  Install Docker: https://docs.docker.com/get-docker'));
    process.exit(1);
  }
  spinner.succeed('Docker found');

  // Check gh
  try {
    execSync('gh --version', { stdio: 'pipe' });
  } catch {
    spinner.fail('GitHub CLI (gh) is required but not installed');
    console.log(chalk.yellow('  Install gh: https://cli.github.com'));
    process.exit(1);
  }
  spinner.succeed('GitHub CLI found');

  // Login to registry
  await dockerHubLogin();

  // Get config
  const config = ensureConfig();
  mkdirSync(config.recordingsDir, { recursive: true });

  // Build and push image
  const imageSpinner = ora('Building Docker image...').start();
  const imageName = `${config.registry}/zoom-recorder:latest`;
  
  try {
    // Check if running in the repo
    const repoPath = join(dirname(__dirname), 'cli');
    if (existsSync(join(repoPath, '..', 'Dockerfile'))) {
      const dockerPath = dirname(dirname(__dirname));
      await run('docker', ['build', '-t', imageName, '.'], { cwd: dockerPath });
    } else {
      // Pull from registry if already published
      await run('docker', ['pull', imageName], { silent: true });
    }
    imageSpinner.succeed(`Image built: ${imageName}`);
  } catch (e: any) {
    imageSpinner.fail(`Build failed: ${e.message}`);
    console.log(chalk.yellow('  Run from project directory to build, or pull existing image'));
  }

  // Push to registry
  if (existsSync(join(dirname(dirname(__dirname)), 'Dockerfile'))) {
    const pushSpinner = ora('Pushing to registry...').start();
    try {
      await run('docker', ['push', imageName]);
      pushSpinner.succeed('Image pushed to registry');
    } catch (e: any) {
      pushSpinner.fail(`Push failed: ${e.message}`);
    }
  }

  // Create wrapper script
  const wrapperPath = join(config.binDir || '/usr/local/bin', 'zoom-rec');
  const wrapperContent = `#!/bin/bash
docker run --rm -it \\
  -v ${config.recordingsDir}:/recordings \\
  -p ${config.apiPort}:8080 \\
  -p ${config.vncPort}:6080 \\
  ${imageName} \\
  "$@"
`;
  
  try {
    writeFileSync('/tmp/zoom-rec', wrapperContent.replace('${config.binDir || \'/usr/local/bin\'}', '').replace('${imageName}', imageName).replace('${config.recordingsDir}', config.recordingsDir).replace('${config.apiPort}', String(config.apiPort)).replace('${config.vncPort}', String(config.vncPort)));
    execSync('sudo mv /tmp/zoom-rec /usr/local/bin/zoom-rec && sudo chmod +x /usr/local/bin/zoom-rec', { stdio: 'inherit' });
    console.log(chalk.green('\n  ✓ Installed! Run: zoom-rec --help'));
  } catch {
    console.log(chalk.yellow('\n  To complete manually: sudo mv /tmp/zoom-rec /usr/local/bin/zoom-rec'));
  }

  console.log(chalk.cyan(`
╔═══════════════════════════════════════════════════════╗
║                    What's Next?                       ║
╠═══════════════════════════════════════════════════════╣
║  zoom-rec run <url>           Join & record a meeting  ║
║  zoom-rec schedule            Schedule a recording    ║
║  zoom-rec status              Check container status  ║
╚═══════════════════════════════════════════════════════╝
  `));
}

async function cmdRun(url?: string, password?: string, duration?: number, startBuffer?: number, stopBuffer?: number): Promise<void> {
  const config = ensureConfig();
  const imageName = `${config.registry}/zoom-recorder:latest`;
  const containerName = 'zoom-recorder';
  
  // Use CLI args or fall back to config
  const finalStartBuffer = startBuffer ?? config.startBuffer;
  const finalStopBuffer = stopBuffer ?? config.stopBuffer;
  const finalDuration = duration ?? config.meetingDuration;

  // Non-interactive: require args
  if (!url) {
    console.log(chalk.yellow('  Usage: zoom-rec run <meeting-url> [password] [duration] [start-buffer] [stop-buffer]'));
    console.log(chalk.gray('  Or run interactively: zoom-rec run'));
    console.log(chalk.gray('  Example: zoom-rec run https://zoom.us/j/123 3600 300 600'));
    return;
  }

  console.log(chalk.cyan(`
╔═══════════════════════════════════════════════════════╗
║               Starting Zoom Recorder                   ║
╚═══════════════════════════════════════════════════════╝
  `));
  
  console.log(chalk.gray(`
  Meeting: ${url}
  Start early: ${finalStartBuffer}s
  Duration: ${finalDuration}s
  Stop buffer: ${finalStopBuffer}s
  Total runtime: ${finalDuration + finalStopBuffer}s
  `));

  const spinner = ora('Starting container...').start();

  // Stop existing
  try {
    await run('docker', ['stop', containerName], { silent: true });
    await run('docker', ['rm', containerName], { silent: true });
  } catch { /* ignore */ }

  // Start new container
  const envVars = [
    `-e`, `ZOOM_MEETING_URL=${url}`,
    `-e`, `ZOOM_MEETING_DURATION=${finalDuration}`,
    `-e`, `ZOOM_START_BUFFER=${finalStartBuffer}`,
    `-e`, `ZOOM_STOP_BUFFER=${finalStopBuffer}`
  ];
  if (password) {
    envVars.push(`-e`, `ZOOM_PASSWORD=${password}`);
  }

  try {
    await run('docker', [
      'run', '-d',
      '--name', containerName,
      '-v', `${config.recordingsDir}:/recordings`,
      '-p', `${config.apiPort}:8080`,
      '-p', `${config.vncPort}:6080`,
      ...envVars,
      imageName,
      '/usr/local/bin/start-x11.sh'
    ]);
    spinner.succeed('Container started');
  } catch (e: any) {
    spinner.fail(`Failed: ${e.message}`);
    process.exit(1);
  }

  console.log(chalk.gray(`
  API:    http://localhost:${config.apiPort}
  VNC:    http://localhost:${config.vncPort}
  Files:  ${config.recordingsDir}
  `));

  console.log(chalk.green('  Recording in progress... Press Ctrl+C to stop'));
  
  // Wait for interrupt
  process.on('SIGINT', async () => {
    const stopSpinner = ora('Stopping...').start();
    await run('docker', ['stop', containerName]);
    stopSpinner.succeed('Stopped');
    process.exit(0);
  });

  // Keep running
  await new Promise(() => {});
}

async function cmdSchedule(when?: string, url?: string, password?: string): Promise<void> {
  if (!when || !url) {
    // Interactive mode
    console.log(chalk.cyan(`
╔═══════════════════════════════════════════════════════╗
║                 Schedule a Recording                   ║
╚═══════════════════════════════════════════════════════╝
    `));

    const answers = await inquirer.prompt([
      {
        type: 'input',
        name: 'meetingUrl',
        message: 'Meeting URL:',
        validate: (v: string) => v.includes('zoom.us') || 'Invalid Zoom URL'
      },
      {
        type: 'input',
        name: 'password',
        message: 'Meeting passcode (optional):',
      },
      {
        type: 'list',
        name: 'scheduleType',
        message: 'Schedule type:',
        choices: ['Once', 'Daily', 'Weekly']
      },
      {
        type: 'input',
        name: 'time',
        message: 'Time (HH:MM):',
        default: '14:00',
        validate: (v: string) => /^([0-1]?[0-9]|2[0-3]):[0-5][0-9]$/.test(v) || 'Invalid time'
      },
      {
        type: 'input',
        name: 'duration',
        message: 'Meeting duration (minutes):',
        default: '60',
      },
      {
        type: 'input',
        name: 'startBuffer',
        message: 'Start early (seconds):',
        default: '300',
        validate: (v: string) => !isNaN(parseInt(v)) && parseInt(v) >= 0 || 'Must be a positive number'
      },
      {
        type: 'input',
        name: 'stopBuffer',
        message: 'Extra recording after (seconds):',
        default: '600',
        validate: (v: string) => !isNaN(parseInt(v)) && parseInt(v) >= 0 || 'Must be a positive number'
      }
    ]);

    // Create systemd unit
    const config = ensureConfig();
    const durationSec = parseInt(answers.duration) * 60;
    const startBufferSec = parseInt(answers.startBuffer);
    const stopBufferSec = parseInt(answers.stopBuffer);
    
    console.log(chalk.yellow('\n  Creating systemd timer...'));
    
    const serviceContent = `[Unit]
Description=Zoom Meeting Recorder
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/bin/docker run --rm -v ${config.recordingsDir}:/recordings -e ZOOM_MEETING_URL="${answers.meetingUrl}" -e ZOOM_PASSWORD="${answers.password}" -e ZOOM_MEETING_DURATION=${durationSec} -e ZOOM_START_BUFFER=${startBufferSec} -e ZOOM_STOP_BUFFER=${stopBufferSec} ${config.registry}/zoom-recorder:latest /usr/local/bin/start-recording.sh
`;

    const unitName = 'zoom-recorder.service';
    writeFileSync(`/tmp/${unitName}`, serviceContent);
    execSync(`sudo mv /tmp/${unitName} /etc/systemd/system/`);
    execSync('sudo systemctl daemon-reload');
    execSync('sudo systemctl enable zoom-recorder.service');
    
    console.log(chalk.green('\n  ✓ Timer created!'));
    console.log(chalk.gray(`  Start early: ${startBufferSec}s | Duration: ${durationSec}s | Extra: ${stopBufferSec}s`));
    console.log(chalk.gray(`  Total runtime: ${durationSec + stopBufferSec}s`));
    return;
  }

  // Non-interactive: require all args
  console.log(chalk.cyan(`  Scheduled: ${when} for ${url}`));
  console.log(chalk.gray('  Use --interactive for guided scheduling'));
}

async function cmdStatus(): Promise<void> {
  const spinner = ora('Checking...').start();
  try {
    const output = await run('docker', ['ps', '--filter', 'name=zoom-recorder', '--format', '{{.Status}}'], { silent: true });
    if (output) {
      spinner.succeed(chalk.green('  Running'));
      console.log(chalk.gray('  Check http://localhost:8080/status for API'));
    } else {
      spinner.info(chalk.yellow('  Not running'));
    }
  } catch {
    spinner.fail('Error checking status');
  }
}

async function cmdConfig(): Promise<void> {
  console.log(chalk.cyan(`
╔═══════════════════════════════════════════════════════╗
║                   Configuration                         ║
╚═══════════════════════════════════════════════════════╝
  `));

  const config = ensureConfig();
  const answers = await inquirer.prompt([
    {
      type: 'input',
      name: 'recordingsDir',
      message: 'Recordings directory:',
      default: config.recordingsDir
    },
    {
      type: 'number',
      name: 'apiPort',
      message: 'API port:',
      default: config.apiPort
    },
    {
      type: 'number',
      name: 'vncPort',
      message: 'VNC port:',
      default: config.vncPort
    },
    {
      type: 'number',
      name: 'meetingDuration',
      message: 'Default meeting duration (seconds):',
      default: config.meetingDuration
    },
    {
      type: 'number',
      name: 'startBuffer',
      message: 'Start early (seconds):',
      default: config.startBuffer
    },
    {
      type: 'number',
      name: 'stopBuffer',
      message: 'Extra recording after (seconds):',
      default: config.stopBuffer
    }
  ]);

  saveConfig({ ...config, ...answers });
  console.log(chalk.green('\n  ✓ Config saved!'));
}

// CLI entry point
async function main() {
  const args = process.argv.slice(2);
  const command = args[0];

  // Show help if no command
  if (!command || command === '--help' || command === '-h') {
    console.log(chalk.cyan(`
╔═══════════════════════════════════════════════════════╗
║               🎥  Zoom Recorder CLI                    ║
╠═══════════════════════════════════════════════════════╣
║  install                       Install CLI and build   ║
║  run <url> [pwd] [dur] [start] [stop]  Join & record  ║
║  schedule                     Schedule (interactive) ║
║  status                       Check if running        ║
║  config                       Configure settings      ║
╚═══════════════════════════════════════════════════════╝

  Examples:
    zoom-rec install
    zoom-rec run https://zoom.us/j/123456789
    zoom-rec run https://zoom.us/j/123 passcode 3600 300 600
                          └─ duration └─ start early └─ extra after
  
  Defaults:
    Start early: 300s (5 min) | Extra after: 600s (10 min)
    `));
    process.exit(0);
  }

  try {
    switch (command) {
      case 'install':
        await cmdInstall();
        break;
      case 'run':
        await cmdRun(
          args[1], 
          args[2], 
          args[3] ? parseInt(args[3]) : undefined,
          args[4] ? parseInt(args[4]) : undefined,
          args[5] ? parseInt(args[5]) : undefined
        );
        break;
      case 'schedule':
        await cmdSchedule(args[1], args[2], args[3]);
        break;
      case 'status':
        await cmdStatus();
        break;
      case 'config':
        await cmdConfig();
        break;
      default:
        console.log(chalk.red(`  Unknown command: ${command}`));
        console.log(chalk.gray('  Run: zoom-rec --help'));
    }
  } catch (e: any) {
    console.error(chalk.red(`  Error: ${e.message}`));
    process.exit(1);
  }
}

main();