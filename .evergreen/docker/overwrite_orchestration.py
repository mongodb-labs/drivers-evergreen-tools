import json
import os

orch_file = os.environ['ORCHESTRATION_FILE']

with open(orch_file) as fid:
    data = json.load(fid)

items = []

# Gather all the items that have process settings.
def traverse(root):
    if isinstance(root, list):
        [traverse(i) for i in root]
        return
    if 'ipv6' in root:
        items.append(root)
        return
    for key, value in root.items():
        if key == 'routers':
            continue
        if isinstance(value, (dict, list)):
            traverse(value)

traverse(data)

# Docker does not enable ipv6 by default.
# https://docs.docker.com/config/daemon/ipv6/
# We also need to use 0.0.0.0 instead of 127.0.0.1
for item in items:
    item['ipv6'] = False
    item['bind_ip'] = '0.0.0.0,::1'
    item['dbpath'] = f"/tmp/mongo-{item['port']}"

if 'routers' in data:
    for router in data['routers']:
        router['ipv6'] = False
        router['bind_ip'] = '0.0.0.0,::1'
        router['logpath'] = f"/tmp/mongodb-{item['port']}.log"

print(json.dumps(data, indent=2))

with open(orch_file, 'w') as fid:
    json.dump(data, fid)
