import os
import json

orch_file = os.environ['ORCHESTRATION_FILE']

with open(orch_file) as fid:
    data = json.load(fid)

items = []

# Gather all the items that have process settings.
def traverse(root):
    if isinstance(root, list):
        [traverse(i) for i in list]
        return
    if 'ipv6' in root:
        items.append(root)
        return
    for value in root.values():
        if isinstance(value, (dict, list)):
            traverse(value)

for item in items:
    item['ipv6'] = False
    item['bind_ip'] = '0.0.0.0,::1'
    item['dpath'] = f'/tmp/mongod-{item['port']}'


print(json.dumps(data, indent=2))

with open(orch_file, 'w') as fid:
    json.dump(data, fid)
