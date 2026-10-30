# Write and verify PR bodies

Use this procedure for every PR create or body edit, including updates from
`finish-pr`. The shared helper is [pr_body.py](../scripts/pr_body.py); resolve
its absolute path from the installed `create-pr` directory. It requires Python
3.10+ and the standard library. If `create-pr` or its helper is missing, install
that dependency before editing the body.

1. For an existing PR, fetch its current body as JSON (`gh pr view <pr-url>
   --json body`) and decode the JSON before making only the intended content
   changes. Preserve the existing Markdown spacing and structure, including
   consecutive checkboxes unless the template or user requests blank lines.
   Preserve paragraphs, intentional blank lines and fenced code spacing.
2. Keep a UTF-8 source file outside the worktree. Read it with newline translation
   disabled (`path.open(encoding="utf-8", newline="")`), including when reading
   Markdown directly: universal-newline reads turn corrupted CRCRLF into two LF
   characters before normalization can repair it. For Python strings (including
   decoded JSON bodies), use the helper's `write_body(path, body)`, which performs:

   ```python
   body = re.sub(r"\r+\n", "\n", body).replace("\r", "\n")
   path.write_text(body, encoding="utf-8", newline="\n")
   ```

   Alternatively, normalize an existing UTF-8 source with the CLI. Add `--json`
   when the source is a JSON object containing `body`; the output is Markdown.

   ```powershell
   & <absolute-python> <absolute-create-pr>/scripts/pr_body.py write `
     --input <source-file> --output <body-file>
   ```

   Keep the intended normalized file for comparison. Never collapse repeated
   newlines or trim arbitrary whitespace to repair this problem.
3. Submit that file with `gh pr create ... --body-file <body-file>` or
   `gh pr edit <pr-url> --body-file <body-file>`, using the explicit target from
   the calling workflow. A structured API body argument containing the same
   normalized string is also safe. Never interpolate multiline Markdown into
   shell command text.
4. After **every** create or edit, read the saved GitHub body back and compare it
   with the intended file:

   ```powershell
   & <absolute-python> <absolute-create-pr>/scripts/pr_body.py verify `
     --expected <body-file> --pr <pr-url> --gh <absolute-gh>
   ```

   For a structured API response, `verify --expected <body-file> --saved-json
   <saved-response-file>` compares a freshly fetched JSON object containing
   `body`. The helper normalizes line-ending representation and removes at most
   one final LF from each side; all other whitespace must match exactly. An
   extra blank line, including between checkboxes, fails verification. On failure,
   inspect the saved response and intended file, diagnose and repair the discrepancy,
   submit the corrected body and verify again before reporting success. Retain
   temporary evidence until verification passes, then remove it.
