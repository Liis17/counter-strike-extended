import { spawn, spawnSync, type ChildProcess } from "node:child_process";
import { existsSync, promises as fs, type Dirent } from "node:fs";
import * as path from "node:path";
import { fileURLToPath } from "node:url";

export const IS_WIN = process.platform === "win32";

export function findProjectRoot(start: string): string {
  let dir = start;
  for (;;) {
    if (existsSync(path.join(dir, ".git")) && existsSync(path.join(dir, "AGENTS.md"))) return dir;
    const parent = path.dirname(dir);
    if (parent === dir) throw new Error(`Project root not found from ${start}`);
    dir = parent;
  }
}

export const PROJECT_ROOT = findProjectRoot(path.dirname(fileURLToPath(import.meta.url)));
export const ENGINE_SRC = path.join(PROJECT_ROOT, "src", "xash3d-fwgs");
export const CLIENT_SRC = path.join(PROJECT_ROOT, "src", "cs16-client");
export const BUILD_DIR = path.join(PROJECT_ROOT, "build");
export const ENGINE_INSTALL = path.join(BUILD_DIR, "engine");
export const CLIENT_INSTALL = path.join(BUILD_DIR, "cs16-client");
export const RUNTIME_DIR = path.join(PROJECT_ROOT, "runtime");
export const ENGINE_LOG = path.join(RUNTIME_DIR, "engine.log");
export const XASH_EXE = path.join(RUNTIME_DIR, IS_WIN ? "xash3d.exe" : "xash3d");
export const STEAM_RP_EXE = path.join(RUNTIME_DIR, IS_WIN ? "cse_steamrp.exe" : "cse_steamrp");

export interface RunResult {
  exitCode: number;
  stdout: string;
  stderr: string;
  durationMs: number;
  cmd: string;
  args: string[];
}

export interface RunOpts {
  cwd: string;
  timeoutMs?: number;
  env?: Record<string, string | undefined>;
  onLine?: (stream: "stdout" | "stderr", line: string) => void;
}

export async function run(cmd: string, args: string[], opts: RunOpts): Promise<RunResult> {
  const { cwd, timeoutMs = 15 * 60 * 1000, env, onLine } = opts;
  return new Promise((resolve, reject) => {
    const child = spawn(cmd, args, {
      cwd,
      env: { ...process.env, ...env },
      stdio: ["ignore", "pipe", "pipe"],
      windowsHide: true,
    });
    let stdout = "";
    let stderr = "";
    let outBuf = "";
    let errBuf = "";
    const emitLine = (stream: "stdout" | "stderr", buf: string, chunk: string) => {
      buf += chunk;
      const lines = buf.split(/\r?\n/);
      buf = lines.pop() ?? "";
      for (const l of lines) onLine?.(stream, l);
      return buf;
    };
    child.stdout?.on("data", (d: Buffer) => {
      stdout += d.toString();
      if (onLine) outBuf = emitLine("stdout", outBuf, d.toString());
    });
    child.stderr?.on("data", (d: Buffer) => {
      stderr += d.toString();
      if (onLine) errBuf = emitLine("stderr", errBuf, d.toString());
    });
    const timer = setTimeout(() => {
      child.kill("SIGKILL");
      reject(new Error(`Command timed out after ${timeoutMs}ms: ${cmd} ${args.join(" ")}`));
    }, timeoutMs);
    const started = Date.now();
    child.on("error", (err) => {
      clearTimeout(timer);
      reject(err);
    });
    child.on("close", (code) => {
      clearTimeout(timer);
      if (outBuf) onLine?.("stdout", outBuf);
      if (errBuf) onLine?.("stderr", errBuf);
      resolve({
        exitCode: code ?? -1,
        stdout,
        stderr,
        durationMs: Date.now() - started,
        cmd,
        args,
      });
    });
  });
}

export function wafInvocation(args: string[], cwd: string): { cmd: string; args: string[]; cwd: string } {
  if (IS_WIN) {
    return { cmd: process.env.ComSpec ?? "cmd.exe", args: ["/c", "waf.bat", ...args], cwd };
  }
  return { cmd: "./waf", args, cwd };
}

export interface ProcessInfo {
  pid: number;
  name: string;
}

export function listXashProcesses(): ProcessInfo[] {
  if (!IS_WIN) {
    const r = spawnSync("pgrep", ["-f", "xash"], { encoding: "utf8" });
    if (r.status !== 0 || !r.stdout) return [];
    return r.stdout
      .split("\n")
      .map((s) => s.trim())
      .filter(Boolean)
      .map((pid) => ({ pid: Number(pid), name: "xash" }));
  }
  const r = spawnSync("tasklist", ["/FI", "IMAGENAME eq xash3d.exe", "/FO", "CSV", "/NH"], {
    encoding: "utf8",
    windowsHide: true,
  });
  if (r.status !== 0 || !r.stdout) return [];
  const out: ProcessInfo[] = [];
  for (const line of r.stdout.split(/\r?\n/)) {
    const m = line.match(/^"xash3d\.exe","(\d+)"/i);
    if (m) out.push({ pid: Number(m[1]), name: "xash3d.exe" });
  }
  // Also pick up the Steam Rich Presence helper so stop_game kills it too.
  const r2 = spawnSync("tasklist", ["/FI", "IMAGENAME eq cse_steamrp.exe", "/FO", "CSV", "/NH"], {
    encoding: "utf8",
    windowsHide: true,
  });
  if (r2.status === 0 && r2.stdout) {
    for (const line of r2.stdout.split(/\r?\n/)) {
      const m = line.match(/^"cse_steamrp\.exe","(\d+)"/i);
      if (m) out.push({ pid: Number(m[1]), name: "cse_steamrp.exe" });
    }
  }
  return out;
}

export function killPid(pid: number, force: boolean): boolean {
  void force;
  if (IS_WIN) {
    const r = spawnSync("taskkill", ["/F", "/PID", String(pid)], { windowsHide: true });
    return r.status === 0;
  }
  const r = spawnSync("kill", ["-9", String(pid)]);
  return r.status === 0;
}

async function walkFiles(dir: string, base: string, acc: string[]): Promise<void> {
  let entries: Dirent[];
  try {
    entries = await fs.readdir(dir, { withFileTypes: true });
  } catch {
    return;
  }
  for (const e of entries) {
    const full = path.join(dir, e.name);
    if (e.isDirectory()) await walkFiles(full, base, acc);
    else acc.push(path.relative(base, full).replace(/\\/g, "/"));
  }
}

export async function listFiles(dir: string): Promise<string[]> {
  if (!existsSync(dir)) return [];
  const acc: string[] = [];
  await walkFiles(dir, dir, acc);
  return acc.sort();
}

export interface CopyFilter {
  (relPath: string, isDir: boolean): boolean;
}

export async function copyTree(src: string, dst: string, filter?: CopyFilter): Promise<string[]> {
  const copied: string[] = [];
  await fs.mkdir(dst, { recursive: true });
  const entries = await fs.readdir(src, { withFileTypes: true });
  for (const e of entries) {
    const s = path.join(src, e.name);
    const d = path.join(dst, e.name);
    const rel = e.name;
    if (filter && !filter(rel, e.isDirectory())) continue;
    if (e.isDirectory()) {
      const sub = await copyTreeRecursive(s, d, filter, rel);
      copied.push(...sub);
    } else {
      await fs.copyFile(s, d);
      copied.push(rel);
    }
  }
  return copied.sort();
}

async function copyTreeRecursive(
  src: string,
  dst: string,
  filter: CopyFilter | undefined,
  prefix: string,
): Promise<string[]> {
  const copied: string[] = [];
  await fs.mkdir(dst, { recursive: true });
  const entries = await fs.readdir(src, { withFileTypes: true });
  for (const e of entries) {
    const s = path.join(src, e.name);
    const d = path.join(dst, e.name);
    const rel = `${prefix}/${e.name}`;
    if (filter && !filter(rel, e.isDirectory())) continue;
    if (e.isDirectory()) {
      const sub = await copyTreeRecursive(s, d, filter, rel);
      copied.push(...sub);
    } else {
      await fs.copyFile(s, d);
      copied.push(rel);
    }
  }
  return copied;
}

export function tailFile(file: string, lines: number): string {
  if (!existsSync(file)) return "";
  const text = spawnSync("powershell", ["-NoProfile", "-Command", `Get-Content -Tail ${lines} -Path '${file}'`], {
    encoding: "utf8",
    windowsHide: true,
  });
  if (text.status === 0) return text.stdout ?? "";
  return "";
}

export function textResult(text: string, isError = false) {
  return { content: [{ type: "text" as const, text }], isError };
}

export function truncate(text: string, max = 4000): string {
  if (text.length <= max) return text;
  const head = text.slice(0, Math.floor(max / 2));
  const tail = text.slice(-Math.floor(max / 2));
  return `${head}\n\n... [truncated ${text.length - max} chars] ...\n\n${tail}`;
}

export { ChildProcess };
