import json
import os
import subprocess
import tempfile

def run_getrefs_sh(event_repository=None, event_ref=None):
    env = os.environ.copy()
    if event_repository:
        env["EVENT_REPOSITORY"] = event_repository
    if event_ref:
        env["EVENT_REF"] = event_ref
    subprocess.run(["ls", "-l"], check=True, env=env)
    output = subprocess.check_output(["bash", "./getrefs.sh"], env=env)
    return json.loads(output.split(b'matrix<<EOF')[1].strip())

def run_getrefs_py(event_repository=None, event_ref=None):
    env = os.environ.copy()
    if event_repository:
        env["EVENT_REPOSITORY"] = event_repository
    if event_ref:
        env["EVENT_REF"] = event_ref

    subprocess.run(["python", "getrefs.py"], check=True, env=env)
    with open("matrix.json", "r") as f:
        return json.load(f)

def compare_outputs(sh_output, py_output):
    return sh_output == py_output

def run_test(event_repository=None, event_ref=None):
    print(f"Running test with EVENT_REPOSITORY={event_repository} and EVENT_REF={event_ref}")
    sh_output = run_getrefs_sh(event_repository, event_ref)
    py_output = run_getrefs_py(event_repository, event_ref)

    if compare_outputs(sh_output, py_output):
        print("Outputs are identical")
    else:
        print("Outputs are different")
        print("getrefs.sh output:")
        print(json.dumps(sh_output, indent=2))
        print("getrefs.py output:")
        print(json.dumps(py_output, indent=2))

def main():
    run_test()
    run_test(event_repository="pyhightech", event_ref="test_ref_string")

if __name__ == "__main__":
    main()
