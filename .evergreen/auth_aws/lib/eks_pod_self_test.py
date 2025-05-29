import os

from pymongo import MongoClient

mongodb_uri = os.environ["MONGODB_URI"]

print("Testing MONGODB-AWS on eks...")
c = MongoClient(f"{mongodb_uri}/?authMechanism=MONGODB-AWS")
c.aws.test.find_one({})
c.close()
print("Testing MONGODB-AWS on eks... done.")
print("Self test complete!")
