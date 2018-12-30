#!/usr/bin/python3

# This script imports all the spaces from the spaces folder under where this script is stored.
#
# Each folder under spaces is expected to have 2 files:
# - definition.json:  A definition file for the space
# - export.json: An export of all the objects in the space, taken from the Management->Saved Objects page of the UI
#
#
# Some extra work is done to the export.json file.
# The export format and the expected format for loading from the UI don't quite match. Have to rename a few fields to their expected values.
# _id => id
# _type => type
# _source => attributes
# _migrationVersion => migrationVersion


import os, sys, requests
from pprint import pprint

# Change to the script's directory
os.chdir(sys.path[0])

# Setup the headers that are used in every request to Kibana
headers = {
    'Content-Type': 'application/json',
    'kbn-version': '6.5.4'
}

# Make sure Kibana is running
try:
    response = requests.get('http://localhost:5601/api/spaces/space', headers=headers)
except:
    sys.stderr.write('Error connecting to kibana - make sure it is running.\n')
    sys.exit(1)

if response.status_code != 200:
    sys.stderr.write('Error: HTTP status code %s - make sure kibana is running and ready.\n' % response.status_code)
    sys.exit(2)

print("Kibana is ready")

directories = [d for d in os.listdir("spaces") if os.path.isdir(os.path.join("spaces", d))]
for directory in directories:
    definition = f"./spaces/{directory}/definition.json"
    export = f"./spaces/{directory}/export.json"

    # Skip the folder if definition.json is missing
    if not os.path.isfile(definition):
        sys.stderr.write(f"{definition} is missing, skipping folder\n")
        continue

    # Try to import the space
    with open(definition) as data:
        response = requests.post('http://localhost:5601/api/spaces/space', headers=headers, data=data)

    if response.status_code == 409:
        sys.stderr.write(f"Error creating space in {definition} - space already exists. If you want to update it to a newer definition, you must delete it first. Skipping.\n")
        continue
    if response.status_code != 200:
        sys.stderr.write(f"Error creating space in {definition} - HTTP status code {response.status_code}. Skipping.\n")
        continue

    # Get the name of the space from the response data
    info = response.json()
    spaceid = info['id']
    name = info['name']
    print(f"Space {name} ({spaceid}) created")

    # Import the exported data
    if not os.path.isfile(export):
        sys.stderr.write(f"{export} is missing. Space will be left empty.\n")
        continue    

    # Read in the export.json file
    with open(export) as f:
        data = f.read()

    # Fix the field names
    data = data.replace('"_id":', '"id":')
    data = data.replace('"_type":', '"type":')
    data = data.replace('"_source":', '"attributes":')
    data = data.replace('"_migrationVersion":', '"migrationVersion":')

    response = requests.post(f'http://localhost:5601/s/{spaceid}/api/saved_objects/_bulk_create', headers=headers, data=data)

    if response.status_code != 200:
        sys.stderr.write(f"Error importing objects for {spaceid} - HTTP status code {response.status_code}, message: {response.content}\n")
        continue

    print(f"Objects imported into {spaceid}")
