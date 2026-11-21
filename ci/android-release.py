"""Build a tagged Flutter release and upload verified, immutable Gitee attachments."""
import argparse
import getpass
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
from urllib.error import HTTPError
from urllib.request import Request, urlopen

APP = Path(__file__).resolve().parents[1]
API = "https://gitee.com/api/v5/repos/Gjbone/zlib-android"
ABIS = ("arm64-v8a", "armeabi-v7a", "x86_64")


def run(*args, cwd=APP, output=False):
    command = [shutil.which(str(args[0])) or str(args[0]), *map(str, args[1:])]
    return subprocess.run(command, cwd=cwd, check=True, text=True,
                          stdout=subprocess.PIPE if output else None).stdout


def digest(path):
    with path.open("rb") as stream:
        h = hashlib.sha256()
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
        return h.hexdigest()


def api(path, data=None, missing_ok=False):
    req = Request(API + path, headers={
        "Authorization": "Bearer " + os.environ["ZLIB_RELEASE_TOKEN"],
        "Content-Type": "application/json",
    }, data=json.dumps(data).encode() if data else None)
    try:
        with urlopen(req, timeout=45) as res:
            return json.load(res)
    except HTTPError as exc:
        if missing_ok and exc.code == 404:
            return None
        raise


def artifact_request(path, *args):
    # curl reads the credential from stdin; redirects to storage use curl's
    # default same-host credential policy.
    cmd = ["curl.exe" if os.name == "nt" else "curl", "--silent", "--show-error",
           "--fail", "--location", "--proto", "=https", "--proto-redir", "=https",
           "--max-time", "300", "--header", "@-", *args, API + path]
    subprocess.run(cmd, input="Authorization: Bearer " + os.environ["ZLIB_RELEASE_TOKEN"] + "\n",
                   text=True, check=True, stdout=subprocess.DEVNULL)


def test():
    version = json.loads(run("flutter", "--version", "--machine", output=True))
    if version["frameworkVersion"] != "3.47.9":
        raise ValueError("Install Flutter 3.47.9 for this release branch")
    run("flutter", "pub", "get", "--enforce-lockfile")
    run("flutter", "test", "--no-pub")


def build(directory, version, number):
    directory.mkdir(parents=True, exist_ok=False)
    test()
    symbols = directory / "private-symbols"
    run("flutter", "build", "apk", "--release", "--split-per-abi", "--obfuscate",
        "--no-pub", "--extra-gen-snapshot-options=--strip", "--split-debug-info=" + str(symbols))
    run("pwsh", "-NoProfile", "-File", APP / "scripts/sign-stable.ps1",
        "-Version", version, "-OutputDirectory", directory)
    shutil.copy2(APP / "build/app/outputs/mapping/release/mapping.txt", symbols)
    files = [directory / f"xlib-android-v{version}-{abi}.apk" for abi in ABIS]
    with (directory / "SHA256SUMS.txt").open("w", encoding="ascii", newline="\n") as sums:
        for file in files:
            sums.write(f"{digest(file)}  {file.name}\n")


def publish(directory, tag, commit, marker, release):
    if release is None:
        notes = (APP / "releases" / (tag + "-stable") / "更新说明.md").read_text(encoding="utf-8-sig")
        release = api("/releases", {"tag_name": tag, "target_commitish": commit,
                      "name": f"xlib Android {tag}", "body": notes + "\n\n" + marker,
                      "prerelease": False})
    if marker not in release["body"]:
        raise ValueError("Existing release belongs to a different publication")
    endpoint = f"/releases/{release['id']}/attach_files"
    for name in [f"xlib-android-{tag}-{abi}.apk" for abi in ABIS] + ["SHA256SUMS.txt"]:
        path = directory / name
        def existing():
            return next((a for a in api(endpoint) if a["name"] == name), None)
        asset = existing()
        if asset is None:
            artifact_request(endpoint, "--form", f'file=@"{path.as_posix()}"')
            asset = existing()
        if asset is None:
            raise RuntimeError(f"Missing uploaded attachment: {name}")
        with tempfile.TemporaryDirectory() as tmp:
            check = Path(tmp) / name
            artifact_request(f"{endpoint}/{asset['id']}/download", "--output", str(check))
            if digest(check) != digest(path):
                raise RuntimeError(f"Attachment checksum mismatch: {name}; stopped without replacing it")
        print("Verified", name)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("test", "build", "publish"))
    args = parser.parse_args()
    if args.mode == "test":
        test()
        return
    version, number = re.search(r"(?m)^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$",
                                (APP / "pubspec.yaml").read_text(encoding="utf-8")).groups()
    commit = run("git", "rev-parse", "HEAD", output=True).strip()
    tag = "v" + version
    marker = f"<!-- android-release-ci {commit} -->"
    if args.mode == "publish":
        if not os.environ.get("ZLIB_RELEASE_TOKEN"):
            os.environ["ZLIB_RELEASE_TOKEN"] = getpass.getpass("Gitee Release token: ")
        if api("/commits/" + tag)["sha"] != commit:
            raise ValueError(f"Remote tag {tag} must point to this exact commit")
        release = api("/releases/tags/" + tag, missing_ok=True)
        if release and marker not in (release.get("body") or ""):
            raise ValueError(f"Release {tag} already exists; refusing to modify it")
        if run("git", "status", "--porcelain", output=True).strip():
            raise ValueError("Publish from a clean checkout")
        if not (APP / "releases" / (tag + "-stable") / "更新说明.md").is_file():
            raise ValueError("Commit the release notes before tagging")
    cache = Path(os.getenv("ZLIB_RELEASE_CACHE", Path.home() / ".zlib-release-cache"))
    cache.mkdir(parents=True, exist_ok=True)
    directory = cache / f"{tag}-{number}-{commit}"
    if args.mode == "build":
        with tempfile.TemporaryDirectory(dir=cache) as tmp:
            dest = Path(tmp) / "signed"
            build(dest, version, number)
            print("Build and signature verification passed")
        return
    if not directory.exists():
        with tempfile.TemporaryDirectory(dir=cache) as tmp:
            dest = Path(tmp) / "signed"
            build(dest, version, number)
            dest.rename(directory)
    publish(directory, tag, commit, marker, release)


if __name__ == "__main__":
    main()
