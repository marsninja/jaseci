/**
 * Persistent TypeScript/JavaScript parse server using oxc-parser.
 *
 * Communicates via newline-delimited JSON on stdin/stdout.
 *
 * Request format:  { "id": number, "file": string, "source"?: string }
 * Response format: { "id": number, "program": ESTree, "errors": [], "comments": [] }
 *
 * If "source" is provided, uses it directly; otherwise reads from "file" path.
 */
import { parseSync } from "oxc-parser";
import { readFileSync } from "fs";

// Signal readiness
console.log(JSON.stringify({ ready: true }));

for await (const line of console) {
  const trimmed = line.trim();
  if (!trimmed) continue;

  try {
    const request = JSON.parse(trimmed);
    const { id, file, source } = request;

    const code = source != null ? source : readFileSync(file, "utf8");
    const fileName = file || "input.ts";

    const result = parseSync(fileName, code, {
      astType: "ts",
      range: true,
    });

    console.log(
      JSON.stringify({
        id,
        program: result.program,
        errors: result.errors,
        comments: result.comments,
      })
    );
  } catch (e) {
    console.log(JSON.stringify({ error: e.message }));
  }
}
