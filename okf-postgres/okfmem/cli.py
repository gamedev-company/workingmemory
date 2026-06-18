"""okfmem CLI — the enrichment daemon's entry points.

  okfmem index                 full sweep: card every code folder in the repo
  okfmem enrich <folder>       (re)enrich one folder
  okfmem enrich-changed        enrich folders touched by the last commit (git hook)
  okfmem stale                 list cards whose covered code has drifted
  okfmem recall "<query>"      debug: hybrid recall from the terminal
"""
from __future__ import annotations
import argparse
import os
import subprocess
import sys
from pathlib import Path
from . import config, db, enrich, recall


def _code_folders() -> list[Path]:
    found = []
    for root, dirs, files in os.walk(config.REPO):
        dirs[:] = [d for d in dirs if d not in config.IGNORE_DIRS]
        rootp = Path(root)
        if any(Path(f).suffix in config.CODE_EXTS for f in files):
            found.append(rootp)
    return found


def _changed_folders(since: str) -> list[Path]:
    out = subprocess.run(
        ["git", "-C", str(config.REPO), "diff", "--name-only", since, "HEAD"],
        capture_output=True, text=True, check=True).stdout.split()
    folders = {(config.REPO / f).parent for f in out
               if not any(part in config.IGNORE_DIRS for part in Path(f).parts)}
    return [f for f in folders if f.exists()]


def cmd_index(args):
    project = args.project
    for folder in _code_folders():
        res = enrich.enrich_folder(folder, project=project)
        print(res)


def cmd_enrich(args):
    print(enrich.enrich_folder(Path(args.folder), project=args.project))


def cmd_enrich_changed(args):
    for folder in _changed_folders(args.since):
        print(enrich.enrich_folder(folder, project=args.project))


def cmd_stale(args):
    with db.connect() as conn:
        rows = db.stale_sources(conn)
    by_card: dict[str, list[str]] = {}
    for r in rows:
        p = config.REPO / r["source_path"]
        if not p.exists() or enrich.git_sha(p) != r["source_sha"]:
            by_card.setdefault(r["card_path"], []).append(r["source_path"])
    if not by_card:
        print("All cards fresh.")
        return
    for card, drifted in by_card.items():
        print(f"STALE {card}  ({len(drifted)} drifted): {drifted}")


def cmd_recall(args):
    for hit in recall.search(args.query, k=args.k):
        fr = hit["freshness"]
        flag = "STALE" if fr["stale"] else "fresh"
        print(f"[{flag}] {hit['title']}  ({hit['resource']})")
        print(f"        {hit['description']}")


def main(argv=None):
    p = argparse.ArgumentParser(prog="okfmem")
    p.add_argument("--project", default=None)
    sub = p.add_subparsers(required=True)

    sub.add_parser("index").set_defaults(func=cmd_index)
    e = sub.add_parser("enrich"); e.add_argument("folder"); e.set_defaults(func=cmd_enrich)
    ec = sub.add_parser("enrich-changed"); ec.add_argument("--since", default="HEAD~1")
    ec.set_defaults(func=cmd_enrich_changed)
    sub.add_parser("stale").set_defaults(func=cmd_stale)
    rc = sub.add_parser("recall"); rc.add_argument("query"); rc.add_argument("-k", type=int, default=6)
    rc.set_defaults(func=cmd_recall)

    args = p.parse_args(argv)
    args.func(args)


if __name__ == "__main__":
    main()
