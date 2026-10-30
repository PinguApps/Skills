"""Write LF-only PR bodies and verify GitHub's saved body without hiding spacing changes."""

import argparse
import json
from pathlib import Path
import re
import subprocess


def normalize_line_endings(body: str) -> str:
    return re.sub(r"\r+\n", "\n", body).replace("\r", "\n")


def read_body(path: Path, *, json_body: bool = False) -> str:
    # Universal-newline reads would turn CRCRLF into two newlines before repair.
    with path.open(encoding="utf-8", newline="") as stream:
        text = stream.read()
    body = json.loads(text)["body"] if json_body else text
    if not isinstance(body, str):
        raise ValueError("Expected a string body")
    return body


def write_body(path: Path, body: str) -> None:
    body = normalize_line_endings(body)
    path.write_text(body, encoding="utf-8", newline="\n")


def verify_body(intended: str, saved: str) -> None:
    expected = normalize_line_endings(intended).removesuffix("\n")
    actual = normalize_line_endings(saved).removesuffix("\n")
    if actual != expected:
        raise ValueError(
            "Saved PR body differs from the intended body. Inspect the saved JSON "
            "and intended file, repair the discrepancy, then verify again."
        )


def fetch_body(gh: str, pr: str) -> str:
    result = subprocess.run(
        [gh, "pr", "view", pr, "--json", "body"],
        check=True,
        capture_output=True,
    )
    # Decode bytes directly: text=True also performs universal-newline conversion.
    body = json.loads(result.stdout.decode("utf-8"))["body"]
    if not isinstance(body, str):
        raise ValueError("Expected a string body from GitHub")
    return body


def main(argv=None) -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    write = commands.add_parser("write", help="Normalize a Markdown file or JSON body")
    write.add_argument("--input", type=Path, required=True)
    write.add_argument("--json", action="store_true", help='Input is a JSON object with "body"')
    write.add_argument("--output", type=Path, required=True)
    verify = commands.add_parser("verify", help="Compare intended body with saved GitHub body")
    verify.add_argument("--expected", type=Path, required=True)
    saved = verify.add_mutually_exclusive_group(required=True)
    saved.add_argument("--saved-json", type=Path, help="Saved API/gh JSON response (offline checks)")
    saved.add_argument("--pr", help="PR URL to read back from GitHub")
    verify.add_argument("--gh", help="Absolute gh executable path; required with --pr")
    args = parser.parse_args(argv)
    if args.command == "write":
        write_body(args.output, read_body(args.input, json_body=args.json))
        print(f"Wrote LF-only UTF-8 body: {args.output}")
    else:
        if args.pr and (not args.gh or not Path(args.gh).is_absolute()):
            parser.error("--pr requires an absolute --gh executable path")
        saved_body = (
            fetch_body(args.gh, args.pr)
            if args.pr else read_body(args.saved_json, json_body=True)
        )
        verify_body(read_body(args.expected), saved_body)
        print("Saved PR body matches (line endings and one optional final newline only).")


if __name__ == "__main__":
    main()
