import os
import json
import sys
from github import Github, GithubException

def main():
    # Set up Github access with an access token
    access_token = os.environ.get("GITHUB_TOKEN", "")
    if not access_token:
        print("Error: GITHUB_TOKEN environment variable is missing.")
        sys.exit(1)

    github = Github(access_token)

    event_repository = os.environ.get("EVENT_REPOSITORY", "")
    event_ref = os.environ.get("EVENT_REF", "")
    event_branch = os.environ.get("EVENT_BRANCH", "")

    with open("mods.json", "r") as f:
        mods = json.load(f)

    with open("mod-sets.json", "r") as f:
        mod_sets = json.load(f)

    mod_name = None
    if event_repository:
        mod_name = next((mod["name"] for mod in mods if mod["repository"] == event_repository), None)

    if mod_name:
        include_mod_sets = [ms for ms in mod_sets["include"] if mod_name in ms["mods"]]
    else:
        include_mod_sets = mod_sets["include"]

    mod_refs = []

    for mod in mods:
        try:
            repo = github.get_repo(mod["repository"])
        except GithubException as e:
            print(f"Error accessing repository for {mod["name"]} at {mod['repository']}")
            raise e

        if mod["repository"] == event_repository:
            ref = event_ref
        else:
            try:
                branch = repo.get_branch(event_branch)
            except GithubException:
                branch = repo.get_branch(repo.default_branch)
            ref = branch.commit.sha

        mod_refs.append({"name": mod["name"], "repository": mod["repository"], "ref": ref})

    result = []

    for mod_set in include_mod_sets:
        new_mod_set = {"name": mod_set["name"], "mods": []}
        for mod_name in mod_set["mods"]:
            mod_ref = next((mr for mr in mod_refs if mr["name"] == mod_name), None)
            if mod_ref:
                new_mod_set["mods"].append(f"{mod_ref['repository']}@{mod_ref['ref']}")
            else:
                new_mod_set["mods"].append(mod_name)
        result.append(new_mod_set)

    print(json.dumps({"include": result}, indent=2))

if __name__ == "__main__":
    main()

