These "disableStapling" configuration files have the OCSP failpoint
removed because the failpoint results in the mongod erroring out on
Windows.

Until [SPEC-1587](https://jira.mongodb.org/browse/SPEC-1587) is
resolved, we will not be able to test OCSP stapling on Windows. This
also means since stapling is unavailable on Windows, we can use these
modified configuration files in this directory to test non-stapled
OCSP on Windows until the server supports stapling on Windows, at
which point we will need a new set of configuration files.

