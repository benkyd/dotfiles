import fs from 'fs';
import opsys from 'os';
import path from 'path';
import { parseArgs } from 'node:util';
import subProcess from 'child_process';
import { log } from 'console';

const home = opsys.homedir() + '/';

const VERSION_MAJOR = 1;
const VERSION_MINOR = 0;
const VERSION_PATCH = 1;

// Install the packages that the dotfiles need to function properly

console.log('Ben\'s amazing dotfiles installer!');
console.log(`Version v${VERSION_MAJOR}.${VERSION_MINOR}.${VERSION_PATCH}`);

const {
    values: { 
        host, os 
    }
} = parseArgs({
    options: {
        host: {
            type: 'string',
            short: 'h',
        },
        os: {
            type: 'string',
            short: 'o',
        },
    },
});

const panic = (error) => {
    console.error('Error: ' + error);
    console.error('usage: bootstrap -h <host> -o <os>');
    process.exit(0);
}

if (!host || !os) {
    panic('Incorrect usage');
}

// check we have the host
const dir = fs.readdirSync('.', { withFileTypes: true }).filter(d => d.isDirectory() && !d.name.startsWith('.')).map(d => d.name);
if (!dir.includes(host)) {
    panic(`Host ${host} does not exist`);
}

// check we have the os 
const targetInstallScript = os + '.os';
const installScripts = fs.readdirSync('.').filter(f => f.endsWith('.os'));
if (!installScripts.includes(targetInstallScript)) {
    panic(`OS ${os} does not exist`);
}

console.log('Installing dependencies...');
subProcess.spawnSync('./' + targetInstallScript, [], {
    stdio: 'inherit', 
});

console.log('Successfully installed OS deps...');

const parentDir = 'common/';
const childDir = host + '/';

// we want to create a symlink between common/ & {host}/ to ~/
// for every file stored in this repo, beforeso we need
// to create a .bak/ of the origionals as this might 
// well cause some issues...
const copyRecursiveSync = (src, dest) => {
    const exists = fs.existsSync(src);
    const stats = exists && fs.statSync(src);
    const isDirectory = exists && stats.isDirectory();
    if (isDirectory) {
        fs.mkdirSync(dest);
        fs.readdirSync(src).forEach(function(childItemName) {
            copyRecursiveSync(path.join(src, childItemName),
                path.join(dest, childItemName));
        });
    } else {
        // recirsively make dest
        const newDir = dest.split('/').splice(-1).join();
        console.log(dir, newDir); 
        if (!fs.existsSync(newDir))
            fs.mkdirSync(newDir, { recursive: true, overwrite: true });
        
        fs.copyFileSync(src, dest, fs.constants.COPYFILE_FICLONE);
    }
};

// since we can recursively copy we only need the top level directories
const basePaths = fs.readdirSync(parentDir);
const childPaths = fs.readdirSync(childDir);

// start by making the backup
const backupDir = home + 'dotfiles.bak/'; // TODO: make this a cmd option
console.log(`Backing up current dotfiles to ${backupDir}`);

if (!fs.existsSync(backupDir))
    fs.mkdirSync(backupDir);

const allPaths = Array.from(new Set(basePaths.concat(childPaths)));
for (const path of allPaths) {
    const copyTarget = home + path;
    const backupTarget = backupDir + path;
    console.log(`Moving ${copyTarget} to ${backupTarget}`);
    copyRecursiveSync(copyTarget, backupTarget);
}

// we prioritise targetDir over parentDir



