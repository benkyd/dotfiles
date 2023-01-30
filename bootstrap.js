import fs from 'fs';
import { parseArgs } from 'node:util';
import subProcess from 'child_process';

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
//const installOutput = subProcess.spawn('./' + targetInstallScript, {
    //detached: true,
//});
//console.log(installOutput.toString());

const parentDir = 'common';
const targetDir = host;


