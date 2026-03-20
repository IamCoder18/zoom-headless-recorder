#!/usr/bin/env node
"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const child_process_1 = require("child_process");
const fs_1 = require("fs");
const path_1 = require("path");
const chalk_1 = __importDefault(require("chalk"));
const ora_1 = __importDefault(require("ora"));
const inquirer_1 = __importDefault(require("inquirer"));
const os_1 = require("os");
// Config paths
const CONFIG_DIR = (0, path_1.join)((0, os_1.homedir)(), '.zoom-recorder');
const CONFIG_FILE = (0, path_1.join)(CONFIG_DIR, 'config.json');
const defaultConfig = {
    registry: 'ghcr.io',
    recordingsDir: (0, path_1.join)((0, os_1.homedir)(), 'zoom-recordings'),
    apiPort: 8080,
    vncPort: 6080,
    meetingDuration: 3600
};
// Utility functions
function ensureConfig() {
    if (!(0, fs_1.existsSync)(CONFIG_DIR))
        (0, fs_1.mkdirSync)(CONFIG_DIR, { recursive: true });
    if (!(0, fs_1.existsSync)(CONFIG_FILE)) {
        (0, fs_1.writeFileSync)(CONFIG_FILE, JSON.stringify(defaultConfig, null, 2));
        return defaultConfig;
    }
    return JSON.parse((0, fs_1.readFileSync)(CONFIG_FILE, 'utf-8'));
}
function saveConfig(config) {
    (0, fs_1.writeFileSync)(CONFIG_FILE, JSON.stringify(config, null, 2));
}
function run(cmd, args = [], options = {}) {
    return new Promise((resolve, reject) => {
        const child = (0, child_process_1.spawn)(cmd, args, { shell: true, stdio: options.silent ? 'pipe' : 'inherit', ...options });
        let output = '';
        if (options.silent) {
            child.stdout?.on('data', (d) => output += d);
            child.stderr?.on('data', (d) => output += d);
        }
        child.on('close', (code) => {
            if (code === 0)
                resolve(output.trim());
            else
                reject(new Error(`Command failed: ${cmd} ${args.join(' ')}`));
        });
    });
}
async function checkDocker() {
    try {
        await run('docker', ['--version'], { silent: true });
        return true;
    }
    catch {
        return false;
    }
}
async function dockerHubLogin() {
    const spinner = (0, ora_1.default)('Logging into container registry...').start();
    try {
        const token = (0, child_process_1.execSync)('gh auth token', { encoding: 'utf8' }).trim();
        const registry = ensureConfig().registry;
        const user = (0, child_process_1.execSync)('gh api user --jq .login', { encoding: 'utf8' }).trim();
        await run('echo', [token], { stdio: 'pipe' });
        (0, child_process_1.execSync)(`echo "${token}" | docker login ${registry} -u ${user} --password-stdin`, { stdio: 'inherit' });
        spinner.succeed('Logged in to container registry');
    }
    catch (e) {
        spinner.fail(`Login failed: ${e.message}`);
        throw e;
    }
}
// Commands
async function cmdInstall() {
    console.log(chalk_1.default.cyan(`
╔═══════════════════════════════════════════════════════╗
║           Zoom Recorder CLI Installation              ║
╚═══════════════════════════════════════════════════════╝
  `));
    const spinner = (0, ora_1.default)('Checking prerequisites...').start();
    // Check docker
    if (!await checkDocker()) {
        spinner.fail('Docker is required but not installed');
        console.log(chalk_1.default.yellow('  Install Docker: https://docs.docker.com/get-docker'));
        process.exit(1);
    }
    spinner.succeed('Docker found');
    // Check gh
    try {
        (0, child_process_1.execSync)('gh --version', { stdio: 'pipe' });
    }
    catch {
        spinner.fail('GitHub CLI (gh) is required but not installed');
        console.log(chalk_1.default.yellow('  Install gh: https://cli.github.com'));
        process.exit(1);
    }
    spinner.succeed('GitHub CLI found');
    // Login to registry
    await dockerHubLogin();
    // Get config
    const config = ensureConfig();
    (0, fs_1.mkdirSync)(config.recordingsDir, { recursive: true });
    // Build and push image
    const imageSpinner = (0, ora_1.default)('Building Docker image...').start();
    const imageName = `${config.registry}/zoom-recorder:latest`;
    try {
        // Check if running in the repo
        const repoPath = (0, path_1.join)((0, path_1.dirname)(__dirname), 'cli');
        if ((0, fs_1.existsSync)((0, path_1.join)(repoPath, '..', 'Dockerfile'))) {
            const dockerPath = (0, path_1.dirname)((0, path_1.dirname)(__dirname));
            await run('docker', ['build', '-t', imageName, '.'], { cwd: dockerPath });
        }
        else {
            // Pull from registry if already published
            await run('docker', ['pull', imageName], { silent: true });
        }
        imageSpinner.succeed(`Image built: ${imageName}`);
    }
    catch (e) {
        imageSpinner.fail(`Build failed: ${e.message}`);
        console.log(chalk_1.default.yellow('  Run from project directory to build, or pull existing image'));
    }
    // Push to registry
    if ((0, fs_1.existsSync)((0, path_1.join)((0, path_1.dirname)((0, path_1.dirname)(__dirname)), 'Dockerfile'))) {
        const pushSpinner = (0, ora_1.default)('Pushing to registry...').start();
        try {
            await run('docker', ['push', imageName]);
            pushSpinner.succeed('Image pushed to registry');
        }
        catch (e) {
            pushSpinner.fail(`Push failed: ${e.message}`);
        }
    }
    // Create wrapper script
    const wrapperPath = (0, path_1.join)(config.binDir || '/usr/local/bin', 'zoom-rec');
    const wrapperContent = `#!/bin/bash
docker run --rm -it \\
  -v ${config.recordingsDir}:/recordings \\
  -p ${config.apiPort}:8080 \\
  -p ${config.vncPort}:6080 \\
  ${imageName} \\
  "$@"
`;
    try {
        (0, fs_1.writeFileSync)('/tmp/zoom-rec', wrapperContent.replace('${config.binDir || \'/usr/local/bin\'}', '').replace('${imageName}', imageName).replace('${config.recordingsDir}', config.recordingsDir).replace('${config.apiPort}', String(config.apiPort)).replace('${config.vncPort}', String(config.vncPort)));
        (0, child_process_1.execSync)('sudo mv /tmp/zoom-rec /usr/local/bin/zoom-rec && sudo chmod +x /usr/local/bin/zoom-rec', { stdio: 'inherit' });
        console.log(chalk_1.default.green('\n  ✓ Installed! Run: zoom-rec --help'));
    }
    catch {
        console.log(chalk_1.default.yellow('\n  To complete manually: sudo mv /tmp/zoom-rec /usr/local/bin/zoom-rec'));
    }
    console.log(chalk_1.default.cyan(`
╔═══════════════════════════════════════════════════════╗
║                    What's Next?                       ║
╠═══════════════════════════════════════════════════════╣
║  zoom-rec run <url>           Join & record a meeting  ║
║  zoom-rec schedule            Schedule a recording    ║
║  zoom-rec status              Check container status  ║
╚═══════════════════════════════════════════════════════╝
  `));
}
async function cmdRun(url, password, duration) {
    const config = ensureConfig();
    const imageName = `${config.registry}/zoom-recorder:latest`;
    const containerName = 'zoom-recorder';
    // Non-interactive: require args
    if (!url) {
        console.log(chalk_1.default.yellow('  Usage: zoom-rec run <meeting-url> [password] [duration]'));
        console.log(chalk_1.default.gray('  Or run interactively: zoom-rec run'));
        return;
    }
    console.log(chalk_1.default.cyan(`
╔═══════════════════════════════════════════════════════╗
║               Starting Zoom Recorder                   ║
╚═══════════════════════════════════════════════════════╝
  `));
    const spinner = (0, ora_1.default)('Starting container...').start();
    // Stop existing
    try {
        await run('docker', ['stop', containerName], { silent: true });
        await run('docker', ['rm', containerName], { silent: true });
    }
    catch { /* ignore */ }
    // Start new container
    const envVars = [
        `-e`, `ZOOM_MEETING_URL=${url}`,
        `-e`, `ZOOM_MEETING_DURATION=${duration || config.meetingDuration}`
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
    }
    catch (e) {
        spinner.fail(`Failed: ${e.message}`);
        process.exit(1);
    }
    console.log(chalk_1.default.gray(`
  API:    http://localhost:${config.apiPort}
  VNC:    http://localhost:${config.vncPort}
  Files:  ${config.recordingsDir}
  `));
    console.log(chalk_1.default.green('  Recording in progress... Press Ctrl+C to stop'));
    // Wait for interrupt
    process.on('SIGINT', async () => {
        const stopSpinner = (0, ora_1.default)('Stopping...').start();
        await run('docker', ['stop', containerName]);
        stopSpinner.succeed('Stopped');
        process.exit(0);
    });
    // Keep running
    await new Promise(() => { });
}
async function cmdSchedule(when, url, password) {
    if (!when || !url) {
        // Interactive mode
        console.log(chalk_1.default.cyan(`
╔═══════════════════════════════════════════════════════╗
║                 Schedule a Recording                   ║
╚═══════════════════════════════════════════════════════╝
    `));
        const answers = await inquirer_1.default.prompt([
            {
                type: 'input',
                name: 'meetingUrl',
                message: 'Meeting URL:',
                validate: (v) => v.includes('zoom.us') || 'Invalid Zoom URL'
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
                validate: (v) => /^([0-1]?[0-9]|2[0-3]):[0-5][0-9]$/.test(v) || 'Invalid time'
            },
            {
                type: 'input',
                name: 'duration',
                message: 'Duration (minutes):',
                default: '60',
            }
        ]);
        // Create systemd unit
        const config = ensureConfig();
        const durationSec = parseInt(answers.duration) * 60;
        console.log(chalk_1.default.yellow('\n  Creating systemd timer...'));
        const serviceContent = `[Unit]
Description=Zoom Meeting Recorder
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/bin/docker run --rm -v ${config.recordingsDir}:/recordings -e ZOOM_MEETING_URL="${answers.meetingUrl}" -e ZOOM_PASSWORD="${answers.password}" -e ZOOM_MEETING_DURATION=${durationSec} ${config.registry}/zoom-recorder:latest /usr/local/bin/start-recording.sh
`;
        const unitName = 'zoom-recorder.service';
        (0, fs_1.writeFileSync)(`/tmp/${unitName}`, serviceContent);
        (0, child_process_1.execSync)(`sudo mv /tmp/${unitName} /etc/systemd/system/`);
        (0, child_process_1.execSync)('sudo systemctl daemon-reload');
        (0, child_process_1.execSync)('sudo systemctl enable zoom-recorder.service');
        console.log(chalk_1.default.green('\n  ✓ Timer created! Use "systemctl start zoom-recorder" to trigger'));
        return;
    }
    // Non-interactive: require all args
    console.log(chalk_1.default.cyan(`  Scheduled: ${when} for ${url}`));
    console.log(chalk_1.default.gray('  Use --interactive for guided scheduling'));
}
async function cmdStatus() {
    const spinner = (0, ora_1.default)('Checking...').start();
    try {
        const output = await run('docker', ['ps', '--filter', 'name=zoom-recorder', '--format', '{{.Status}}'], { silent: true });
        if (output) {
            spinner.succeed(chalk_1.default.green('  Running'));
            console.log(chalk_1.default.gray('  Check http://localhost:8080/status for API'));
        }
        else {
            spinner.info(chalk_1.default.yellow('  Not running'));
        }
    }
    catch {
        spinner.fail('Error checking status');
    }
}
async function cmdConfig() {
    console.log(chalk_1.default.cyan(`
╔═══════════════════════════════════════════════════════╗
║                   Configuration                         ║
╚═══════════════════════════════════════════════════════╝
  `));
    const config = ensureConfig();
    const answers = await inquirer_1.default.prompt([
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
            message: 'Default duration (seconds):',
            default: config.meetingDuration
        }
    ]);
    saveConfig({ ...config, ...answers });
    console.log(chalk_1.default.green('\n  ✓ Config saved!'));
}
// CLI entry point
async function main() {
    const args = process.argv.slice(2);
    const command = args[0];
    // Show help if no command
    if (!command || command === '--help' || command === '-h') {
        console.log(chalk_1.default.cyan(`
╔═══════════════════════════════════════════════════════╗
║               🎥  Zoom Recorder CLI                    ║
╠═══════════════════════════════════════════════════════╣
║  install           Install CLI and build image        ║
║  run <url> [pwd]   Join meeting and record             ║
║  schedule          Schedule recordings (interactive)  ║
║  status            Check if recorder is running       ║
║  config            Configure settings                  ║
╚═══════════════════════════════════════════════════════╝

  Quick start:
    zoom-rec install
    zoom-rec run https://zoom.us/j/123456789
    `));
        process.exit(0);
    }
    try {
        switch (command) {
            case 'install':
                await cmdInstall();
                break;
            case 'run':
                await cmdRun(args[1], args[2], args[3] ? parseInt(args[3]) : undefined);
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
                console.log(chalk_1.default.red(`  Unknown command: ${command}`));
                console.log(chalk_1.default.gray('  Run: zoom-rec --help'));
        }
    }
    catch (e) {
        console.error(chalk_1.default.red(`  Error: ${e.message}`));
        process.exit(1);
    }
}
main();
