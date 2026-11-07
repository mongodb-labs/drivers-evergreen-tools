#!/usr/bin/env bash
#
# (Copied over from Compass - https://github.com/mongodb-js/compass/blob/b6fec9cbbb2c6949e9ece3fffe861c3f52e30a4f/.evergreen/retry-with-backoff.sh)
# Retries a command a with backoff.
#
# The retry count is given by ATTEMPTS (default 5), the
# initial backoff timeout is given by TIMEOUT in seconds
# (default 1.)
#
# Successive backoffs double the timeout.
#
retry_with_backoff() {
  local max_attempts=${ATTEMPTS-5}
  local timeout=${TIMEOUT-1}
  local attempt=0
  local exitCode=0
  local attempt_stdout

  command="$*"
  while [[ $attempt -lt $max_attempts ]]; do
    attempt_prompt=$(( attempt + 1 ))
    # Progress goes to stderr so the helper is safe inside command
    # substitutions (the wrapped command owns stdout).
    echo "retry_with_backoff: running '${command}' - attempt n. ${attempt_prompt} ..." 1>&2

    # Buffer this attempt's stdout and emit it only on success: a failed
    # attempt may have written a partial response (e.g. curl cut off
    # mid-transfer), and emitting it would concatenate with the next
    # attempt's output inside a command substitution. Trailing newlines are
    # stripped by the capture.
    exitCode=0
    attempt_stdout=$("$@") || exitCode=$?
    if [[ $exitCode == 0 ]]; then
      printf '%s' "${attempt_stdout}"
      break
    fi

    echo "retry_with_backoff: attempt failed! Retrying in ${timeout}.." 1>&2
    sleep "${timeout}"
    attempt=$(( attempt + 1 ))
    timeout=$(( timeout * 2 ))
  done

  if [[ $exitCode != 0 ]]; then
    echo "retry_with_backoff: All attempts failed" 1>&2
  fi

  return $exitCode
}
retry_with_backoff "$@"
