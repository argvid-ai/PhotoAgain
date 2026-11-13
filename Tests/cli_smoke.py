"""Generated-image-only CLI integration checks. Pass built photoagain path."""
import json, pathlib, subprocess, sys, tempfile
exe = sys.argv[1]
def run(*args, ok=True):
    p = subprocess.run([exe, *map(str, args)], capture_output=True, text=True)
    assert (p.returncode == 0) == ok, (args, p.returncode, p.stdout, p.stderr)
    return p
with tempfile.TemporaryDirectory(prefix="photoagain-smoke-") as d:
    root = pathlib.Path(d)
    assert "recommend" in run("--help").stdout
    demo = root / "demo"
    run("demo", "--output", demo)
    evidence = json.loads((demo / "evidence.json").read_text())
    assert evidence["synthetic"] and len(evidence["assets"]) == 3
    run("validate", "--input", demo / "evidence.json")
    run("demo", "--output", demo, ok=False)
    run("analyze", "--input", demo / "synthetic-1.png", "--output", root / "single.json")
    run("analyze", "--input", demo / "synthetic-1.png", "--output", root / "single.json", ok=False)
    mixed = root / "mixed"
    mixed.mkdir()
    (mixed / "b.png").write_bytes((demo / "synthetic-2.png").read_bytes())
    public = root / "mapped.json"
    private = root / "inputs.private.json"
    run("analyze", "--input", demo / "synthetic-1.png", "--input", mixed, "--output", public, "--private-manifest", private)
    mapping = json.loads(private.read_text())
    mapped_evidence = json.loads(public.read_text())
    assert mapping["privacy"] == "private-local-input-map"
    assert mapping["datasetID"] == mapped_evidence["datasetID"]
    assert [x["assetID"] for x in mapping["entries"]] == ["asset-0001", "asset-0002"]
    assert pathlib.Path(mapping["entries"][0]["path"]).resolve() == (demo / "synthetic-1.png").resolve()
    assert pathlib.Path(mapping["entries"][1]["path"]).resolve() == (mixed / "b.png").resolve()
    assert private.stat().st_mode & 0o777 == 0o600
    assert "synthetic-1.png" not in public.read_text()
    collision = root / "collision.private.json"
    run("analyze", "--input", demo / "synthetic-1.png", "--output", collision, "--private-manifest", collision, ok=False)
    assert not collision.exists()
    untouched = root / "untouched.json"
    run("analyze", "--input", demo / "synthetic-1.png", "--output", untouched, "--private-manifest", private, ok=False)
    assert not untouched.exists()
    ledger = root / "ledger.json"
    ledger.write_text(json.dumps({"schemaVersion": 1, "datasetID": evidence["datasetID"], "entries": [{"id":"d1","assetID":"asset-0001","action":"keep"}]}))
    run("recommend", "--input", public, "--recipe", demo / "recipe.json", "--decisions", ledger, "--output", root / "wrong.json", ok=False)
    run("recommend", "--input", demo / "evidence.json", "--recipe", demo / "recipe.json", "--output", root / "rec.json")
    run("validate", "--kind", "recommendations", "--input", root / "rec.json", "--evidence", demo / "evidence.json")
    evidence["schemaVersion"] = 99
    (root / "invalid.json").write_text(json.dumps(evidence))
    run("validate", "--input", root / "invalid.json", ok=False)
    run("analyze", "--input", root / "missing.png", "--output", root / "bad.json", ok=False)
    run("--unknown", ok=False)
print("CLI smoke passed")
