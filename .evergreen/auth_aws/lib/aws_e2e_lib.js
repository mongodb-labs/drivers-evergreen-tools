
// Shim for supporting mongo and mongosh.
if (typeof jsTestLog == 'undefined') {
    var jsTestLog = console.error;

    function _isWindows() {
        return process.platform == 'win32';
    }
}


function readFile(fileName) {
    if (typeof cat != 'undefined') {
        return cat(fileName);
    }
    const fs = require('fs');
    return fs.readFileSync(fileName, 'utf8');
}



function readSetupJson() {
    let result;
    try {
        result = readFile("aws_e2e_setup.json");
    } catch (e) {
        jsTestLog(
            "Failed to parse read aws_e2e_setup.json. See evergreen.yml for how to generate this file which contains evergreen secrets.");
        throw e;
    }

    try {
        return JSON.parse(result);
    } catch (e) {
        jsTestLog("Failed to parse: aws_e2e_setup.json");
        throw e;
    }
}

function runWithEnv(args, env) {
    const pid = _startMongoProgram({args: args, env: env});
    return waitProgram(pid);
}

function runShellCmdWithEnv(argStr, env) {
    if (_isWindows()) {
        return runWithEnv(['cmd.exe', '/c', argStr], env);
    } else {
        return runWithEnv(['/bin/sh', '-c', argStr], env);
    }
}

function getPython3Binary() {
    if (_isWindows()) {
        return "python.exe";
    }

    return "python3";
}
