/**
 * Single-file TypeScript/JavaScript parser using oxc-parser.
 *
 * Usage: bun run ts_parse.js <file_path> [source_on_stdin]
 *
 * If the second argument is "stdin", reads source from stdin instead of the file.
 * Outputs ESTree-compatible JSON AST to stdout.
 */
import { parseSync } from "oxc-parser";
import { readFileSync } from "fs";

const filePath = process.argv[2];
if (!filePath) {
  process.stderr.write("Usage: bun run ts_parse.js <file_path> [stdin]\n");
  process.exit(1);
}

let source;
if (process.argv[3] === "stdin") {
  // Read source from stdin (for when caller already has the source string)
  const chunks = [];
  for await (const chunk of Bun.stdin.stream()) {
    chunks.push(chunk);
  }
  source = Buffer.concat(chunks).toString("utf8");
} else {
  source = readFileSync(filePath, "utf8");
}

const result = parseSync(filePath, source, {
  astType: "ts",
  range: true,
});

process.stdout.write(
  JSON.stringify({
    program: result.program,
    errors: result.errors,
    comments: result.comments,
  })
);
