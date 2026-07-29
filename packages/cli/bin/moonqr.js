#!/usr/bin/env node
import { run } from "../dist/cli.js";

const { stdout, stderr, code } = run(process.argv.slice(2), process.env);
if (stdout) process.stdout.write(stdout);
if (stderr) process.stderr.write(stderr);
process.exit(code);
