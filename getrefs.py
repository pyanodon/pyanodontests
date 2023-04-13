import os
import json
import subprocess

def main():
    event_repository = os.getenv("EVENT_REPOSITORY", "")
    event_ref = os.getenv("EVENT_REF", "")

    with open("mods.json", "r") as mods_file:
        mods_data = json.load(mods_file)
    
    with open("mod-sets.json", "r") as mod_sets_file:
        mod_sets_data = json.load(mod_sets_file)

    mod_name = ""
    if event_repository:
        mod_name = next((mod["name"] for mod in mods_data if mod["repository"] == event_repository), "")

    if mod_name:
        include_mod_sets = [ms for ms in mod_sets_data["include"] if mod_name in ms["mods"]]
    else:
        include_mod_sets = mod_sets_data["include"]

    mod_refs = []
    for mod in mods_data:
        repo = mod["repository"]
        if repo == event_repository:
            ref = event_ref
        else:
            url = mod["url"]
            branch_output = subprocess.getoutput(f"git remote show {url}")
            branch = branch_output.split("HEAD branch: ")[-1].split("\n")[0]
            ref_output = subprocess.getoutput(f"git ls-remote -h {url} {branch}")
            ref = ref_output.split()[0]

        mod_refs.append({"name": mod["name"], "repository": repo, "ref": ref})

    for mod_set in include_mod_sets:
        mod_set["mods"] = [next((f"{mod_ref['repository']}@{mod_ref['ref']}" for mod_ref in mod_refs if mod_ref["name"] == mod), mod) for mod in mod_set["mods"]]

    matrix = {"include": include_mod_sets}

    with open("matrix.json", "w") as matrix_file:
        json.dump(matrix, matrix_file, indent=2)

if __name__ == "__main__":
    main()
