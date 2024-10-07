import json
import urllib.error
import re
import urllib.request
import pprint
import sys

# Download a copy of full.json into memory.
print("Fetching version data...")
url = 'https://downloads.mongodb.org/full.json'
req = urllib.request.Request(url)
try:
    resp = urllib.request.urlopen(req)
except urllib.error.HTTPError as e:
    if e.code != 304:
        raise RuntimeError(
            'Failed to download [{u}]'.format(u=url)) from e
data = json.loads(resp.read().decode('utf-8'))
print("Fetching version data... done.")

# Read in the source file.
with open('.evergreen/download-mongodb.sh') as fid:
    source = fid.read()

# Set up variables.
versions = ["3.6", "4.0", "5.0", "6.0", "7.0", "8.0", "RAPID"]
versions = dict(zip(versions, [None for _ in versions]))
missing_links = []
missing_versions = []
groups = []
skip_targets = ["ubuntu1404", "amazon2"]
# The rapid version is the latest non-prerelease without a "0" minor version.
rapid_version="^\d\.[1-9]\.\d$"

# Parse the json data.
for version in data["versions"]:
    v = version["version"]
    key = v[:3]
    if key not in versions:
        if re.match(rapid_version, v):
            key = "RAPID"
        else:
            continue
    if versions[key] is None:
        versions[key] = v
    else:
        continue

    version_name = f"VERSION_{key.replace('.', '')}"
    couplets = []
    for download in version["downloads"]:
        if download["edition"] == "enterprise":
            if download["target"] in skip_targets:
                continue
            couplets.append((download["target"], download["arch"]))
            url = download['archive']['url']
            expected = url.replace('-' + v, '${DEBUG}-${' + version_name + '}')
            expected = expected.replace('https://downloads.mongodb.com', 'http://downloads.10gen.com')
            if expected not in source:
                missing_links.append(expected)
    groups.append((version_name, v, couplets))
    expected = f'{version_name}="{v}"'
    if expected not in source:
        missing_versions.append(expected)

# Print a summary of versions and supported target-arch pairs.
for (name, v, couplets) in groups:
    print("-" * 25)
    print(f'{name} ({v})')
    print("-" * 25)
    couplets = sorted(couplets, key=lambda tup: tup[0])
    for target, arch in couplets:
        print(f'{target}-{arch}')

# Print a summary of missing links.
if missing_links:
    print("-" * 25)
    print("Missing or incorrect links:")
    print("-" * 25)
    pprint.pprint(missing_links)

# Print a summary of missing versions.
if missing_versions:
    print("-" * 25)
    print("Missing or out of date versions:")
    print("-" * 25)
    pprint.pprint(missing_versions)

if missing_versions or missing_links:
    sys.exit(1)
