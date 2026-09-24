"""Validate versioned guidance and snapshots, reporting absent local evidence separately."""
import argparse
import hashlib
import json
import re
import sys
from pathlib import Path
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[2]
ARCHIVE = ROOT / "docs/archive/2026-09-24-documentation-reset"
FROZEN = {ROOT / "docs/P0_BASELINE.md", ROOT / "docs/ENGINE_READINESS_REPORT.md"}
LINK = re.compile(r"!?\[[^\]\n]*\]\((<[^>]+>|[^\s)]+)(?:\s+\"[^\"]*\")?\)")

def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()

def relative(path):
    return path.relative_to(ROOT).as_posix()

def prose(path):
    text = path.read_text(encoding="utf-8-sig")
    return re.sub(r"^```[^\n]*\n.*?^```\s*$", "", text, flags=re.M | re.S)

def anchors(path):
    text = prose(path)
    result = set(re.findall(r'<a\s+(?:id|name)=[\"\']([^\"\']+)', text))
    counts = {}
    for heading in re.findall(r"^#{1,6}\s+(.+?)\s*#*\s*$", text, flags=re.M):
        # GitHub-style anchors used by the local Markdown documents.
        slug = re.sub(r"[^\w\- ]", "", heading.lower()).replace(" ", "-")
        count = counts.get(slug, 0)
        counts[slug] = count + 1
        result.add(slug + (f"-{count}" if count else ""))
    return result

def check_links(files):
    failures, unavailable, count = [], [], 0
    for path in files:
        for match in LINK.finditer(prose(path)):
            target = match.group(1).strip("<>")
            url = urlsplit(target)
            if url.scheme or target.startswith("//"):
                continue
            count += 1
            destination = (path.parent / unquote(url.path)).resolve() if url.path else path
            problem = None
            if not destination.exists():
                if any(destination.is_relative_to(ROOT / folder) for folder in ("artifacts", "generated")):
                    unavailable.append({"source": relative(path), "target": target})
                else:
                    problem = "missing local target"
            elif url.fragment and destination.suffix.lower() == ".md":
                if unquote(url.fragment) not in anchors(destination):
                    problem = "missing heading anchor"
            if problem:
                failures.append({"source": relative(path), "target": target, "problem": problem})
    return {"files": len(files), "local_links": count, "failures": failures,
            "unavailable_local_evidence": unavailable}

def check_archives():
    count, failures = 0, []
    bases = (ROOT / "docs/archive", ROOT / "plans/archive")
    for manifest_path in sorted(path for base in bases for path in base.rglob("manifest.json")):
        manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
        rows = manifest if isinstance(manifest, list) else manifest.get("entries", manifest.get("files", [manifest]))
        for row in rows:
            count += 1
            stored = row.get("archived", row.get("archived_path", row.get("path", ""))).replace("\\", "/")
            # Early manifests store absolute Windows paths. Relocate their archive
            # suffix without rewriting the preserved historical manifest itself.
            for prefix in ("docs/archive/", "plans/archive/"):
                if "/" + prefix in stored:
                    stored = prefix + stored.split("/" + prefix, 1)[1]
            path = ((ROOT if stored.startswith(("docs/archive/", "plans/archive/")) else manifest_path.parent) / stored).resolve()
            valid = any(path.is_relative_to(base) for base in bases) and path.is_file()
            if valid:
                valid = sha256(path) == row.get("sha256", "").lower()
                if "bytes" in row:
                    valid = valid and path.stat().st_size == row["bytes"]
            if not valid:
                failures.append({"manifest": relative(manifest_path), "target": stored})
    return {"entries": count, "failures": failures}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", required=True, type=Path)
    parser.add_argument("--preservation", type=Path)
    args = parser.parse_args()
    report_path = args.report.resolve()
    if not report_path.is_relative_to(ROOT):
        raise SystemExit("Report must stay in the workspace")
    if report_path.exists():
        raise SystemExit("Choose a new report path; existing evidence is not overwritten")

    files = [ROOT / "README.md", ROOT / "AGENTS.md", ARCHIVE / "INDEX.md"]
    for base in (ROOT / "docs", ROOT / "plans"):
        files.extend(path for path in base.rglob("*.md")
                     if "archive" not in path.relative_to(base).parts and path not in FROZEN)
    current = check_links(sorted(files))
    references = check_links(sorted(FROZEN))
    archive = check_archives()

    preservation_failures, protected_count = [], 0
    if args.preservation:
        snapshot = json.loads(args.preservation.read_text(encoding="utf-8"))
        protected_count = len(snapshot["files"])
        for row in snapshot["files"]:
            path = ROOT / row["path"]
            if not path.is_file() or sha256(path) != row["sha256"]:
                preservation_failures.append(row["path"])

    status = "pass" if not (current["failures"] or archive["failures"] or preservation_failures) else "fail"
    report = {"status": status, "scope": "Local active Markdown links/anchors, preserved snapshot bytes, optional dated preservation baseline; no runtime or perceptual validation",
              "active": current, "unchanged_historical_references": references,
              "archive": archive,
              "preservation": {"checked_files": protected_count, "failures": preservation_failures}}
    report_path.parent.mkdir(parents=True, exist_ok=True)
    with report_path.open("x", encoding="utf-8") as stream:
        json.dump(report, stream, indent=2)
        stream.write("\n")
    print(json.dumps(report, indent=2))
    return 0 if status == "pass" else 1

if __name__ == "__main__":
    sys.exit(main())
