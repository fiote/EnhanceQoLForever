"""Read-only paths, inventory and Forever release discovery for the upqol skill."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import urllib.request


PROJECT_ID = 1076354
DEFAULT_INTERFACE = Path(r"C:\Program Files (x86)\World of Warcraft\_forever_\Interface")
MODULE = re.compile(r"EnhanceQoL[A-Za-z0-9_]*\Z")
API = "https://www.curseforge.com/api/v1/mods/{}/files?pageIndex={}&pageSize=50&sort=dateCreated&sortDescending=true&removeAlphas=true"


def settings(args):
    repo = Path(args.repo or Path(__file__).resolve().parents[3]).resolve()
    workspace = Path(args.workspace or os.environ.get("ENHANCEQOL_UPDATER_WORKSPACE") or repo.parent / "EnhanceQoLUpdater").resolve()
    config_path = workspace / ".upqol" / "paths.json"
    config = {}
    if config_path.is_file():
        config = json.loads(config_path.read_text(encoding="utf-8-sig"))
        if not isinstance(config, dict):
            raise ValueError("paths.json must contain an object")
        if "interface" in config and (not isinstance(config["interface"], str) or not config["interface"].strip()):
            raise ValueError("paths.json interface must be a non-empty path")
    interface = Path(args.interface or os.environ.get("ENHANCEQOL_INTERFACE") or config.get("interface") or DEFAULT_INTERFACE).resolve()
    return {"repository": str(repo), "interface": str(interface), "addons": str(interface / "AddOns"),
            "updater_workspace": str(workspace), "config": str(config_path)}


def toc_fields(path):
    result = {}
    for line in path.read_text(encoding="utf-8-sig", errors="strict").splitlines():
        match = re.match(r"^##\s*([^:]+):\s*(.*?)\s*$", line)
        if match:
            result[match[1]] = match[2]
    return result


def modules(repo):
    return sorted((p for p in repo.iterdir() if MODULE.fullmatch(p.name) and p.is_dir()
                   and any(p.glob("*.toc"))), key=lambda p: p.name)


def reparse(path):
    return path.is_symlink() or bool(getattr(path.lstat(), "st_file_attributes", 0) & 0x400)


def module_hashes(folder):
    if reparse(folder):
        raise ValueError("Unexpected repository module link: " + str(folder))
    result = {}
    for root, dirs, files in os.walk(folder, followlinks=False):
        for name in dirs + files:
            path = Path(root) / name
            if reparse(path):
                raise ValueError("Unexpected link inside module: " + str(path))
        dirs[:] = [d for d in dirs if d.lower() != ".git"]
        for name in files:
            if name.lower() == "agents.md":
                continue
            path = Path(root) / name
            digest = hashlib.sha256()
            with path.open("rb") as stream:
                for block in iter(lambda: stream.read(1024 * 1024), b""):
                    digest.update(block)
            result[path.relative_to(folder.parent).as_posix()] = digest.hexdigest()
    return result


def git(repo, *args, optional=False):
    command = ["git", "--no-optional-locks", "-c", "safe.directory=" + repo.as_posix(), "-C", str(repo), *args]
    run = subprocess.run(command, capture_output=True, encoding="utf-8", errors="replace")
    if run.returncode:
        if optional:
            return None
        raise ValueError(run.stderr.strip())
    return run.stdout.rstrip("\r\n")


def active_core(repo):
    core = repo / "EnhanceQoL" / "EnhanceQoL_Camelot.toc"
    fields = toc_fields(core)
    if fields.get("X-EQOL-Flavor") != "forever":
        raise ValueError("The active core TOC is not marked as Forever")
    if fields.get("X-Curse-Project-ID") != str(PROJECT_ID):
        raise ValueError("The installed TOC project ID differs from this skill")
    if not fields.get("Version"):
        raise ValueError("The active core TOC has no Version")
    return fields


def inventory(paths, hashes=False):
    repo = Path(paths["repository"])
    fields = active_core(repo)
    result = {"paths": paths, "version": fields["Version"], "project_id": PROJECT_ID,
              "flavor": fields["X-EQOL-Flavor"], "interface_version": fields.get("Interface"),
              "head": git(repo, "rev-parse", "HEAD"), "branch": git(repo, "branch", "--show-current"),
              "upstream": git(repo, "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}", optional=True),
              "git_status": git(repo, "status", "--porcelain=v1", "--untracked-files=all").splitlines(), "modules": []}
    snapshots = {}
    for folder in modules(repo):
        if reparse(folder):
            raise ValueError("Unexpected repository module link: " + str(folder))
        link = Path(paths["addons"]) / folder.name
        result["modules"].append({"name": folder.name, "repository_path": str(folder),
            "addon_path": str(link), "addon_is_link": link.exists() and reparse(link),
            "addon_matches_repository": link.exists() and link.samefile(folder),
            "tocs": {p.name: toc_fields(p).get("Version") for p in sorted(folder.glob("*.toc"))}})
        if hashes:
            snapshots.update(module_hashes(folder))
    if hashes:
        result["sha256"] = snapshots
    return result


def forever_file(file):
    tags = [file.get("fileName", ""), str(file.get("gameVersionFlavor", "")), *map(str, file.get("gameVersions") or [])]
    return any("forever" in tag.lower() for tag in tags)


def file_version(file):
    match = re.search(r"(?<!\d)(\d+\.\d+(?:\.\d+)*)(?!\d)", file.get("fileName", ""))
    return match[1] if match else None


def catalog(paths):
    version = active_core(Path(paths["repository"]))["Version"]
    candidates = []
    for page in range(100):
        url = API.format(PROJECT_ID, page)
        request = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"})
        with urllib.request.urlopen(request, timeout=30) as response:
            data = json.load(response)
        batch = data.get("data")
        pagination = data.get("pagination")
        if not isinstance(batch, list) or not isinstance(pagination, dict):
            raise ValueError("Unrecognized CurseForge response; review source before proceeding")
        for item in batch:
            if forever_file(item) and file_version(item):
                candidates.append({"id": item["id"], "fileName": item["fileName"],
                    "version": file_version(item), "fileLength": item.get("fileLength"),
                    "dateCreated": item.get("dateCreated"), "releaseType": item.get("releaseType"),
                    "source": "https://www.curseforge.com/wow/addons/enhance-qol/files/" + str(item["id"])})
        total = pagination.get("totalCount")
        size = pagination.get("pageSize")
        if not isinstance(total, int) or not isinstance(size, int) or size <= 0:
            raise ValueError("Invalid CurseForge pagination")
        if (page + 1) * size >= total:
            break
        if not batch:
            raise ValueError("CurseForge returned an incomplete catalog")
    else:
        raise ValueError("Catalog pagination limit reached; review before proceeding")
    candidates.sort(key=lambda f: (tuple(map(int, f["version"].split("."))), f["id"]), reverse=True)
    return {"project_id": PROJECT_ID, "installed_version": version, "forever_candidates": candidates,
            "note": "Candidates require package/flavor validation. No files downloaded or installed."}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo")
    parser.add_argument("--interface")
    parser.add_argument("--workspace")
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("paths")
    inv = commands.add_parser("inventory")
    inv.add_argument("--hashes", action="store_true")
    commands.add_parser("catalog")
    args = parser.parse_args(argv)
    paths = settings(args)
    if args.command == "paths":
        data = paths
    elif args.command == "inventory":
        data = inventory(paths, args.hashes)
    else:
        data = catalog(paths)
    print(json.dumps(data, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError) as error:
        print("ERROR:", error, file=sys.stderr)
        sys.exit(1)
