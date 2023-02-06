// Ben's amazing dotfiles installer!
// it would be super cool if it did stuff like notice a new hostname
// and respond by backing up the current dotfiles in a new host file
//
// FEATURES:
//  - Backup current dotfiles to dotfiles.bak/
//  - Create symlinks between dotfiles and the actual dotfiles

import fs from 'fs';
import { readdir } from 'fs/promises';
import opsys from 'os';
import path from 'path';
import { parseArgs } from 'node:util';
import subProcess from 'child_process';

const HOME = opsys.homedir() + '/';

const VERSION_MAJOR = 1;
const VERSION_MINOR = 0;
const VERSION_PATCH = 1;

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

// install the packages that the dotfiles need to function properly
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

// HELPERS //
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
        
        //fs.copyFileSync(src, dest, fs.constants.COPYFILE_FICLONE);
    }
};

const deepReadDir = async (dirPath) => await Promise.all(
    (await readdir(dirPath, {withFileTypes: true})).map(async (dirent) => {
        const currentPath = path.join(dirPath, dirent.name)
        return dirent.isDirectory() ? await deepReadDir(currentPath) : currentPath;
    }),
)

// END //


// we want to create a symlink between common/ & {host}/ to ~/
// for every file stored in this repo, beforeso we need
// to create a .bak/ of the origionals as this might 
// well cause some issues...

const parentDir = 'common/';
const childDir = host + '/';
const basePaths = (await deepReadDir(parentDir)).flat(999);
const childPaths = (await deepReadDir(childDir)).flat(999);

// start by making the backup
const backupDir = HOME + 'dotfiles.bak/'; // TODO: make this a cmd option
console.log(`Backing up current dotfiles to ${backupDir}`);

// delete current backupDir first, we might want to warn the user of this Y/n
if (fs.existsSync(backupDir))
    fs.rmSync(backupDir, { recursive: true });
if (!fs.existsSync(backupDir))
    fs.mkdirSync(backupDir);

console.log(basePaths, childPaths);

const anonBasePaths = basePaths.map(e => e.split('/').slice(1).join('/'));
const anonChildPaths = basePaths.map(e => e.split('/').slice(1).join('/'));
const allAnonPaths = Array.from(new Set(anonBasePaths.concat(anonChildPaths)));

for (const path of allAnonPaths) {
    const copyTarget = HOME + path;
    const backupTarget = backupDir + path;
    console.log(`Moving ${copyTarget} to ${backupTarget}`);
    copyRecursiveSync(copyTarget, backupTarget);
}

// we prioritise targetDir over parentDir

