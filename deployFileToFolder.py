import json
import shutil
import os

# Load configuration from deployConfig.json
with open("deployConfig.json", "r") as config_file:
    config = json.load(config_file)

# Extract the first file path from the script list
script_list = config.get("scriptList", [])
if not script_list:
    raise ValueError("No script paths found in deployConfig.json")

source_file = script_list[0]

destination_folder = "C:\\Program Files\\Beyond-All-Reason\\data\\LuaUI\\Widgets\\"

# Ensure the destination folder exists
if not os.path.exists(destination_folder):
    raise FileNotFoundError(f"Destination folder '{destination_folder}' does not exist.")

# Copy the file to the destination
shutil.copy(source_file, destination_folder)
print(f"Copied {source_file} to {destination_folder}")
