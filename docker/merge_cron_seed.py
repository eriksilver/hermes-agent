#!/usr/bin/env python3
"""Merge the image-baked cron seed into the volume's jobs.json.

Why: the old write-once pattern silently dropped any new or edited cron
entry unless HERMES_FORCE_RESEED_CRON=1 was set in Railway env, because
the volume already had a jobs.json from a prior deploy. This script does
a field-level merge instead.

Rules:
    * Seed owns each job's declarative shape (prompt, schedule, enabled,
      deliver, name, skills, model overrides, workdir, etc.).
    * Volume owns runtime state Hermes mutates per run — declared
      explicitly in RUNTIME_FIELDS below.
    * Jobs in the volume whose id isn't in the seed are preserved
      (treated as user/Atlas-added at runtime via Slack commands).
    * Removing a job from the seed does NOT remove it from the volume.
      Use HERMES_FORCE_RESEED_CRON=1 for a full reset.

Atomic write via tempfile + os.replace so a crash mid-write can't
corrupt the volume file.
"""
import json
import os
import sys
import tempfile

RUNTIME_FIELDS = {
    "repeat",
    "state",
    "paused_at",
    "paused_reason",
    "last_run_at",
    "next_run_at",
}


def merge(seed_jobs, vol_jobs):
    vol_by_id = {j["id"]: j for j in vol_jobs if "id" in j}
    seed_ids = {j["id"] for j in seed_jobs if "id" in j}
    out = []
    for sj in seed_jobs:
        vj = vol_by_id.get(sj.get("id"))
        if vj is None:
            out.append(sj)
            continue
        merged = dict(sj)
        for k in RUNTIME_FIELDS:
            if k in vj:
                merged[k] = vj[k]
        for k, v in vj.items():
            if k not in merged and k not in sj:
                merged[k] = v
        out.append(merged)
    out.extend(j for j in vol_jobs if j.get("id") not in seed_ids)
    return out


def main():
    seed_path, vol_path = sys.argv[1], sys.argv[2]
    with open(seed_path) as f:
        seed = json.load(f)
    try:
        with open(vol_path) as f:
            vol = json.load(f)
    except (FileNotFoundError, json.JSONDecodeError) as e:
        print(
            f"[merge_cron_seed] volume jobs.json unreadable ({e}); using seed verbatim",
            file=sys.stderr,
        )
        with open(vol_path, "w") as out:
            json.dump(seed, out, indent=2)
        return

    merged_jobs = merge(seed.get("jobs", []), vol.get("jobs", []))
    output = {**vol, "jobs": merged_jobs}

    dir_ = os.path.dirname(vol_path) or "."
    fd, tmp_path = tempfile.mkstemp(dir=dir_, suffix=".tmp")
    try:
        with os.fdopen(fd, "w") as tmp:
            json.dump(output, tmp, indent=2)
        os.replace(tmp_path, vol_path)
    except Exception:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)
        raise


if __name__ == "__main__":
    main()
