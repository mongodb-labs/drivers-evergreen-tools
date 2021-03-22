
const PARSE_FAILURE = "Failed to parse: kms_setup.json"

function readSetupJson() {
    let result;
    try {
        result = cat("kms_setup.json");
    } catch (e) {
        jsTestLog(PARSE_FAILURE);
        throw e;
    }

    let config;
    try {
        config = JSON.parse(result);
    } catch (e) {
        jsTestLog(PARSE_FAILURE);
        throw e;
    }

    if (config["kms_ca_file"] == "") {
        jsTestLog(PARSE_FAILURE);
        throw new Error("Value for kms_ca_file must be supplied in kms_setup.json")
    }
    if (config["kms_cert_file"] == "") {
        jsTestLog(PARSE_FAILURE);
        throw new Error("Value for kms_cert_file must be supplied in kms_setup.json")
    }

    return config
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
