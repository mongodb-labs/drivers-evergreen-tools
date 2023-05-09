
// Shim for supporting mongo and mongosh.
if (typeof jsTestLog == 'undefined') {
    var jsTestLog = console.error;


}

function isWindows() {
    if (typeof _isWindows == 'undefined') {
        return process.platform == 'win32';
    }
    return _isWindows()
}


function startMongoProgram(opts) {
    if (typeof _startMongoProgram != 'undefined') {
        pid = _startMongoProgram(opts);
        return waitProgram(pid);
    }
    const childProcess = require('child_process');
    const cmd = opts.args.join(' ');
    console.log('running cmd:', cmd)
    return childProcess.execSync(cmd, {
      env: opts.env,
      stdio: 'inherit',
      shell: true
    });
}



function readFile(fileName) {
    if (typeof cat != 'undefined') {
        return cat(fileName);
    }
    const fs = require('fs');
    return fs.readFileSync(fileName, 'utf8');
}


function assert_eq(val, eq, msg) {
    if (typeof jsTestLog == 'undefined') {
        return assert.eq(val, eq, msg);
    }
    if (val != eq) {
        throw new Error(msg);
    }
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
    return startMongoProgram({args: args, env: env});
}

function runShellCmdWithEnv(argStr, env) {
    if (isWindows()) {
        return runWithEnv(['cmd.exe', '/c', argStr], env);
    } else {
        return runWithEnv(['/bin/sh', '-c', argStr], env);
    }
}

function getPython3Binary() {
    if (isWindows()) {
        return "python.exe";
    }

    return "python3";
}
