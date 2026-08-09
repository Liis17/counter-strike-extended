import { spawn, type ChildProcess } from "node:child_process";
import { existsSync } from "node:fs";
import * as path from "node:path";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import {
  BUILD_DIR,
  CLIENT_INSTALL,
  CLIENT_SRC,
  ENGINE_INSTALL,
  ENGINE_LOG,
  ENGINE_SRC,
  IS_WIN,
  PROJECT_ROOT,
  RUNTIME_DIR,
  STEAM_RP_EXE,
  XASH_EXE,
  copyTree,
  killPid,
  listFiles,
  listXashProcesses,
  run,
  tailFile,
  textResult,
  truncate,
  wafInvocation,
} from "./lib.js";

const server = new McpServer({
  name: "game",
  version: "0.1.0",
});

const trackedChildren = new Map<number, ChildProcess>();

const DEFAULT_PRESET = "win32-release-x86";
const DEFAULT_CLIENT_CONFIG = "Release";

server.tool(
  "build_engine",
  "Build the Xash3D FWGS engine via `waf build` (already-configured tree) and install artifacts into build/engine. Configure is NOT run automatically — it is a one-time manual step (needs --sdl2 path etc.).",
  {
    target: z
      .enum(["build", "clean", "rebuild"])
      .default("build")
      .describe("'build' (incremental), 'clean' (waf clean), 'rebuild' (clean+build)"),
    install: z.boolean().default(true).describe("Run `waf install --destdir=build/engine` after a successful build"),
    verbose: z.boolean().default(false).describe("Pass -v to waf"),
    jobs: z.number().int().positive().optional().describe("Parallel jobs, passed as -j N"),
  },
  async (args) => {
    const steps: string[] = [];
    const wafArgs: string[] = [];
    if (args.target === "clean" || args.target === "rebuild") wafArgs.push("clean");
    const needBuild = args.target !== "clean";
    if (needBuild) {
      wafArgs.push("build");
      if (args.verbose) wafArgs.push("-v");
      if (args.jobs) wafArgs.push("-j", String(args.jobs));
    }
    const lines: string[] = [];
    if (wafArgs.length > 0) {
      const inv = wafInvocation(wafArgs, ENGINE_SRC);
      steps.push(`waf ${wafArgs.join(" ")}`);
      const r = await run(inv.cmd, inv.args, {
        cwd: inv.cwd,
        onLine: (_s, l) => lines.push(l),
      }).catch((e: Error) => e);
      if (r instanceof Error) {
        return textResult(
          `waf failed to spawn: ${r.message}\n\ncwd: ${ENGINE_SRC}`,
          true,
        );
      }
      if (r.exitCode !== 0) {
        return textResult(
          `waf ${wafArgs.join(" ")} failed (exit ${r.exitCode}) in ${r.durationMs}ms\n\nLast output:\n${truncate(lines.slice(-60).join("\n"))}`,
          true,
        );
      }
    }
    if (args.install && needBuild) {
      const installInv = wafInvocation(["install", `--destdir=${ENGINE_INSTALL}`], ENGINE_SRC);
      steps.push("waf install");
      const r = await run(installInv.cmd, installInv.args, { cwd: installInv.cwd });
      if (r.exitCode !== 0) {
        return textResult(
          `waf install failed (exit ${r.exitCode})\n\n${truncate(r.stderr || r.stdout)}`,
          true,
        );
      }
    }
    const installed = await listFiles(ENGINE_INSTALL);
    return textResult(
      [
        `Engine ${args.target} OK in src/xash3d-fwgs.`,
        `Steps: ${steps.join(" → ")}`,
        `Install dir: ${ENGINE_INSTALL} (${installed.length} files)`,
        installed.length ? `\nLast output:\n${truncate(lines.slice(-20).join("\n"))}` : "",
      ].join("\n"),
    );
  },
);

server.tool(
  "build_client",
  "Build the CS16Client via CMake and install artifacts into build/cs16-client. If build/CMakeCache.txt exists, configure is skipped unless reconfigure=true.",
  {
    preset: z.string().default(DEFAULT_PRESET).describe(`CMake preset name (default ${DEFAULT_PRESET})`),
    reconfigure: z
      .boolean()
      .default(false)
      .describe("Force `cmake --preset` even if build/ is already configured"),
    config: z
      .enum(["Release", "Debug", "RelWithDebInfo"])
      .default(DEFAULT_CLIENT_CONFIG)
      .describe(`Build config (default: ${DEFAULT_CLIENT_CONFIG})`),
    skip_install: z.boolean().default(false).describe("Skip `cmake --install` step"),
  },
  async (args) => {
    const buildDir = path.join(CLIENT_SRC, "build");
    const cacheFile = path.join(buildDir, "CMakeCache.txt");
    const configureRan = !existsSync(cacheFile) || args.reconfigure;

    if (configureRan) {
      const r = await run("cmake", ["--preset", args.preset], { cwd: CLIENT_SRC });
      if (r.exitCode !== 0) {
        return textResult(
          `cmake --preset ${args.preset} failed (exit ${r.exitCode}).\n\nCommon cause: preset uses Ninja generator which may not be installed. Try running once manually:\n  cd src/cs16-client && cmake -A Win32 -S . -B build\n\n${truncate(r.stderr || r.stdout)}`,
          true,
        );
      }
    }

    const buildArgs = ["--build", "build", "--config", args.config];
    const br = await run("cmake", buildArgs, { cwd: CLIENT_SRC });
    if (br.exitCode !== 0) {
      return textResult(
        `cmake --build failed (exit ${br.exitCode})\n\n${truncate(br.stderr || br.stdout)}`,
        true,
        );
    }

    if (!args.skip_install) {
      const ir = await run(
        "cmake",
        ["--install", "build", "--config", args.config, "--prefix", CLIENT_INSTALL],
        { cwd: CLIENT_SRC },
      );
      if (ir.exitCode !== 0) {
        return textResult(
          `cmake --install failed (exit ${ir.exitCode})\n\n${truncate(ir.stderr || ir.stdout)}`,
          true,
        );
      }
    }

    const installed = await listFiles(CLIENT_INSTALL);
    return textResult(
      [
        `Client build OK${configureRan ? " (configured with " + args.preset + ")" : " (using existing build/)"}.`,
        `Build dir: ${buildDir}`,
        `Install dir: ${CLIENT_INSTALL} (${installed.length} files)`,
        installed.length ? `Installed:\n  - ${installed.slice(0, 30).join("\n  -")}${installed.length > 30 ? `\n  ... +${installed.length - 30} more` : ""}` : "",
      ].join("\n"),
    );
  },
);

server.tool(
  "deploy_runtime",
  "Copy build artifacts from build/engine and build/cs16-client into the runtime/ folder (where xash3d.exe lives). Engine files go to runtime root (+ valve/), client files go to runtime/cstrike/.",
  {
    target: z.enum(["all", "engine", "client"]).default("all").describe("Which artifacts to deploy"),
    include_pdb: z.boolean().default(true).describe("Copy *.pdb files (useful for debugging)"),
    dry_run: z.boolean().default(false).describe("Report what would be copied without writing"),
  },
  async (args) => {
    const wantPdb = args.include_pdb;
    const skipPdb = (rel: string) => !rel.toLowerCase().endsWith(".pdb");
    const skipLib = (rel: string) => !rel.toLowerCase().endsWith(".lib");

    const report: string[] = [];
    let totalCopied = 0;

    const doCopy = async (label: string, src: string, dst: string, keep: (rel: string) => boolean) => {
      if (!existsSync(src)) {
        report.push(`[${label}] source missing: ${src} — nothing to deploy (run build_${label} first).`);
        return;
      }
      if (args.dry_run) {
        const files = (await listFiles(src)).filter(keep);
        report.push(`[${label}] (dry-run) would copy ${files.length} files → ${dst}`);
        if (files.length) report.push(`  - ${files.slice(0, 15).join("\n  - ")}${files.length > 15 ? `\n  ... +${files.length - 15} more` : ""}`);
        totalCopied += files.length;
        return;
      }
      const filter = (rel: string, isDir: boolean) => (isDir ? true : keep(rel));
      const copied = await copyTree(src, dst, filter);
      report.push(`[${label}] copied ${copied.length} files → ${path.relative(PROJECT_ROOT, dst) || "<runtime>"}`);
      if (copied.length) report.push(`  - ${copied.slice(0, 15).join("\n  - ")}${copied.length > 15 ? `\n  ... +${copied.length - 15} more` : ""}`);
      totalCopied += copied.length;
    };

    const keepAll = () => true;
    const keepPdbAware = wantPdb ? keepAll : skipPdb;

    if (args.target === "all" || args.target === "engine") {
      await doCopy("engine", ENGINE_INSTALL, RUNTIME_DIR, keepPdbAware);
    }
    if (args.target === "all" || args.target === "client") {
      const src = path.join(CLIENT_INSTALL, "cstrike");
      const dst = path.join(RUNTIME_DIR, "cstrike");
      await doCopy(
        "client",
        src,
        dst,
        (rel: string) => keepPdbAware(rel) && skipLib(rel),
      );
    }

    return textResult(
      [
        args.dry_run ? `Dry run — nothing written.` : `Deploy complete.`,
        `${totalCopied} file(s) ${args.dry_run ? "would be " : ""}copied to runtime/.`,
        "",
        ...report,
      ].join("\n"),
    );
  },
);

server.tool(
  "run_game",
  "Launch xash3d.exe from runtime/ (detached, non-blocking). Returns PID. If a previous tracked launch is still alive, it is left running — call stop_game first to replace it.",
  {
    game: z.string().default("cstrike").describe("Value passed to -game (default cstrike)"),
    map: z.string().optional().describe("Map to load, passed as +map <name>"),
    extra_args: z
      .array(z.string())
      .optional()
      .describe("Extra raw command-line args appended after the constructed ones"),
    windowed: z.boolean().default(true).describe("Add -window"),
    width: z.number().int().positive().optional(),
    height: z.number().int().positive().optional(),
    dev: z.boolean().default(false).describe("Enable developer mode (-dev 3)"),
    log_file: z.string().optional().describe("Override -log <file> (default engine.log under runtime/)"),
    rich_presence: z
      .boolean()
      .default(true)
      .describe(
        "Launch through the Steam Rich Presence helper (cse_steamrp.exe) when it exists in runtime/. Set false to launch xash3d.exe directly. If the helper is missing, falls back to direct launch silently.",
      ),
  },
  async (args) => {
    const useRp = args.rich_presence && existsSync(STEAM_RP_EXE);
    if (!useRp && !existsSync(XASH_EXE)) {
      return textResult(`xash3d executable not found at ${XASH_EXE}. Deploy the engine first.`, true);
    }
    const launcher = useRp ? STEAM_RP_EXE : XASH_EXE;
    const argv: string[] = ["-game", args.game];
    if (args.windowed) argv.push("-window");
    if (args.width && args.height) argv.push("-w", String(args.width), "-h", String(args.height));
    if (args.dev) argv.push("-dev", "3");
    if (args.map) argv.push("+map", args.map);
    if (args.log_file) argv.push("-log", args.log_file);
    if (args.extra_args) argv.push(...args.extra_args);

    const child = spawn(launcher, argv, {
      cwd: RUNTIME_DIR,
      detached: true,
      stdio: "ignore",
      windowsHide: false,
    });
    child.on("error", (err) => {
      trackedChildren.delete(child.pid ?? -1);
    });
    if (child.pid) {
      trackedChildren.set(child.pid, child);
      child.unref();
    }
    return textResult(
      [
        `Launched ${path.basename(launcher)} (pid ${child.pid ?? "unknown"}) detached from runtime/.`,
        useRp
          ? `Steam Rich Presence: ON (wraps xash3d.exe, appid from runtime/steam_appid.txt).`
          : args.rich_presence
            ? `Steam Rich Presence: helper missing at ${STEAM_RP_EXE} — launched xash3d.exe directly.`
            : `Steam Rich Presence: OFF (direct launch).`,
        `Args: ${argv.join(" ")}`,
        `Working dir: ${RUNTIME_DIR}`,
        child.pid ? `Use stop_game or game_status to control it.` : `WARNING: no pid captured.`,
      ]
        .filter(Boolean)
        .join("\n"),
    );
  },
);

server.tool(
  "stop_game",
  "Stop running xash3d process(es). Without pid, stops ALL xash3d.exe instances found on the system.",
  {
    pid: z.number().int().positive().optional().describe("Stop a specific pid; if omitted, stop all xash3d instances"),
  },
  async (args) => {
    if (args.pid) {
      const ok = killPid(args.pid, true);
      trackedChildren.delete(args.pid);
      return textResult(ok ? `Killed pid ${args.pid}.` : `Failed to kill pid ${args.pid} (not running?).`, !ok);
    }
    const procs = listXashProcesses();
    if (procs.length === 0) return textResult("No xash3d process running.");
    const killed: number[] = [];
    const failed: number[] = [];
    for (const p of procs) {
      if (killPid(p.pid, true)) killed.push(p.pid);
      else failed.push(p.pid);
      trackedChildren.delete(p.pid);
    }
    return textResult(
      [
        `Stopped ${killed.length}/${procs.length} xash3d instance(s).`,
        killed.length ? `Killed: ${killed.join(", ")}` : "",
        failed.length ? `Failed: ${failed.join(", ")}` : "",
      ]
        .filter(Boolean)
        .join("\n"),
      failed.length > 0,
    );
  },
);

server.tool(
  "game_status",
  "Report whether xash3d is currently running and list its pid(s). Also reports tracked launches from this MCP session.",
  {},
  async () => {
    const procs = listXashProcesses();
    const tracked = [...trackedChildren.keys()].filter((pid) =>
      procs.some((p) => p.pid === pid),
    );
    return textResult(
      [
        procs.length === 0
          ? "xash3d is NOT running."
          : `xash3d is RUNNING — ${procs.length} instance(s): ${procs.map((p) => p.pid).join(", ")}`,
        tracked.length ? `Tracked from this session: ${tracked.join(", ")}` : `Not tracked from this session.`,
        `Engine log: ${ENGINE_LOG} ${existsSync(ENGINE_LOG) ? "(exists)" : "(not yet created)"}`,
      ].join("\n"),
    );
  },
);

server.tool(
  "tail_log",
  "Read the tail of runtime/engine.log (or another log under runtime/) to inspect engine output without leaving the chat.",
  {
    lines: z.number().int().positive().max(2000).default(80),
    log: z.string().default("engine.log").describe("Filename inside runtime/ (default engine.log)"),
  },
  async (args) => {
    const file = path.isAbsolute(args.log) ? args.log : path.join(RUNTIME_DIR, args.log);
    if (!existsSync(file)) {
      return textResult(`Log not found: ${file}`, true);
    }
    const tail = tailFile(file, args.lines);
    return textResult(
      [
        `Last ${args.lines} lines of ${path.relative(PROJECT_ROOT, file)}:`,
        "----------------------------------------",
        tail || "(empty)",
      ].join("\n"),
    );
  },
);

server.tool(
  "project_paths",
  "Return the absolute paths this MCP server uses (engine source, client source, build dirs, install dirs, runtime dir). Useful to verify the server resolved the project root correctly.",
  {},
  async () => {
    return textResult(
      [
        `Project root:  ${PROJECT_ROOT}`,
        `Engine src:    ${ENGINE_SRC}`,
        `Client src:    ${CLIENT_SRC}`,
        `Build dir:     ${BUILD_DIR}`,
        `Engine install:${ENGINE_INSTALL}`,
        `Client install:${CLIENT_INSTALL}`,
        `Runtime:       ${RUNTIME_DIR}`,
        `xash3d exe:    ${XASH_EXE}`,
        `Engine log:    ${ENGINE_LOG}`,
        `Platform:      ${process.platform} (${IS_WIN ? "windows" : "unix"})`,
      ].join("\n"),
    );
  },
);

async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  process.stderr.write(`[game-mcp] ready. project root = ${PROJECT_ROOT}\n`);
}

main().catch((err) => {
  process.stderr.write(`[game-mcp] fatal: ${err?.stack ?? err}\n`);
  process.exit(1);
});
