import { spawn } from "node:child_process";
import { createReadStream } from "node:fs";
import { access, opendir, stat } from "node:fs/promises";
import { constants } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { createInterface } from "node:readline";

const TIMEOUT_MS = 15_000;

function parseArgs(argv) {
  const result = {};
  for (let index = 0; index < argv.length; index += 1) {
    const value = argv[index];
    if (value === "--codex") {
      result.codex = argv[index + 1];
      index += 1;
    }
  }
  return result;
}

function finiteNumber(value) {
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

function sanitizeBucket(bucket, key) {
  if (!bucket || typeof bucket !== "object") {
    return null;
  }

  const usedPercent = finiteNumber(bucket.usedPercent);
  const windowDurationMins = finiteNumber(bucket.windowDurationMins);
  const resetsAt = finiteNumber(bucket.resetsAt);

  return {
    key,
    usedPercent,
    remainingPercent:
      usedPercent === null
        ? null
        : Math.max(0, Math.min(100, 100 - usedPercent)),
    windowDurationMins,
    resetsAt,
  };
}

function sanitizeIndividualLimit(limit) {
  if (!limit || typeof limit !== "object") {
    return null;
  }

  return {
    used: limit.used ?? null,
    limit: limit.limit ?? null,
    remainingPercent: finiteNumber(limit.remainingPercent),
    resetAt: finiteNumber(limit.resetAt),
  };
}

async function* sessionFiles(directory) {
  let entries;
  try {
    entries = await opendir(directory);
  } catch (error) {
    if (error?.code === "ENOENT") {
      return;
    }
    throw error;
  }

  for await (const entry of entries) {
    const entryPath = join(directory, entry.name);
    if (entry.isDirectory()) {
      yield* sessionFiles(entryPath);
    } else if (entry.isFile() && entry.name.endsWith(".jsonl")) {
      yield entryPath;
    }
  }
}

function startOfLocalWeek(now = new Date()) {
  const start = new Date(now);
  start.setHours(0, 0, 0, 0);
  const daysSinceMonday = (start.getDay() + 6) % 7;
  start.setDate(start.getDate() - daysSinceMonday);
  return start;
}

async function readWeeklyTokenUsage(now = new Date()) {
  const weekStart = startOfLocalWeek(now);
  const cutoff = weekStart.getTime();
  const codexHome =
    process.env.CODEX_HOME?.trim() || join(homedir(), ".codex");
  const sessionsDirectory = join(codexHome, "sessions");
  const weeklyUsage = {
    inputTokens: 0,
    cachedInputTokens: 0,
    outputTokens: 0,
    reasoningOutputTokens: 0,
    totalTokens: 0,
  };
  let scannedSessions = 0;
  let tokenEvents = 0;
  let duplicateNotifications = 0;

  for await (const filePath of sessionFiles(sessionsDirectory)) {
    const fileStat = await stat(filePath);
    if (fileStat.mtimeMs < cutoff) {
      continue;
    }

    let previousUsage = null;
    let sessionTokens = 0;
    const lines = createInterface({
      input: createReadStream(filePath, { encoding: "utf8" }),
      crlfDelay: Infinity,
    });

    for await (const line of lines) {
      let event;
      try {
        event = JSON.parse(line);
      } catch {
        continue;
      }
      if (
        event?.type !== "event_msg" ||
        event?.payload?.type !== "token_count"
      ) {
        continue;
      }

      const currentUsage = event.payload?.info?.total_token_usage;
      const currentTotal = finiteNumber(currentUsage?.total_tokens);
      if (currentTotal === null) {
        continue;
      }

      const timestamp = Date.parse(event.timestamp);
      if (!Number.isFinite(timestamp) || timestamp < cutoff) {
        previousUsage = currentUsage;
        continue;
      }

      tokenEvents += 1;
      const fields = [
        ["input_tokens", "inputTokens"],
        ["cached_input_tokens", "cachedInputTokens"],
        ["output_tokens", "outputTokens"],
        ["reasoning_output_tokens", "reasoningOutputTokens"],
        ["total_tokens", "totalTokens"],
      ];
      let totalDelta = 0;
      for (const [sourceField, targetField] of fields) {
        const currentValue = finiteNumber(currentUsage?.[sourceField]) ?? 0;
        const previousValue =
          finiteNumber(previousUsage?.[sourceField]) ?? 0;
        const delta =
          previousUsage === null || currentValue < previousValue
            ? currentValue
            : currentValue - previousValue;
        weeklyUsage[targetField] += delta;
        if (sourceField === "total_tokens") {
          totalDelta = delta;
          sessionTokens += delta;
        }
      }
      if (previousUsage !== null && totalDelta === 0) {
        duplicateNotifications += 1;
      }
      previousUsage = currentUsage;
    }

    if (sessionTokens > 0) {
      scannedSessions += 1;
    }
  }

  const freshInputTokens = Math.max(
    0,
    weeklyUsage.inputTokens - weeklyUsage.cachedInputTokens,
  );
  const cachedPercent =
    weeklyUsage.inputTokens > 0
      ? (weeklyUsage.cachedInputTokens / weeklyUsage.inputTokens) * 100
      : 0;

  return {
    weekStart: weekStart.toISOString(),
    weeklyTokens: Math.round(weeklyUsage.totalTokens),
    inputTokens: Math.round(weeklyUsage.inputTokens),
    cachedInputTokens: Math.round(weeklyUsage.cachedInputTokens),
    freshInputTokens: Math.round(freshInputTokens),
    outputTokens: Math.round(weeklyUsage.outputTokens),
    reasoningOutputTokens: Math.round(weeklyUsage.reasoningOutputTokens),
    cachedPercent: Math.round(cachedPercent * 10) / 10,
    scannedSessions,
    tokenEvents,
    duplicateNotifications,
  };
}

export function sanitizeResult(
  result,
  accountResult = null,
  tokenStats = null,
) {
  const rateLimits = result?.rateLimits ?? {};
  const buckets = [
    sanitizeBucket(rateLimits.primary, "primary"),
    sanitizeBucket(rateLimits.secondary, "secondary"),
  ].filter(Boolean);

  return {
    capturedAt: new Date().toISOString(),
    planType: accountResult?.account?.planType ?? null,
    buckets,
    individualLimit: sanitizeIndividualLimit(rateLimits.individualLimit),
    rateLimitReachedType: rateLimits.rateLimitReachedType ?? null,
    resetCreditsAvailable:
      finiteNumber(result?.rateLimitResetCredits?.availableCount) ?? 0,
    tokenStats,
  };
}

function queryRateLimits(codexExecutable) {
  return new Promise((resolve, reject) => {
    const child = spawn(
      codexExecutable,
      ["app-server", "--listen", "stdio://"],
      {
        windowsHide: true,
        stdio: ["pipe", "pipe", "pipe"],
      },
    );

    let stdout = "";
    let stderr = "";
    let settled = false;
    let rateLimitResult = null;
    let accountResult = null;

    const finish = (error, result) => {
      if (settled) {
        return;
      }
      settled = true;
      clearTimeout(timeout);
      child.kill();
      if (error) {
        reject(error);
      } else {
        resolve(result);
      }
    };

    const send = (message) => {
      child.stdin.write(`${JSON.stringify(message)}\n`);
    };

    const timeout = setTimeout(() => {
      const detail = stderr.trim().split(/\r?\n/u).at(-1);
      finish(
        new Error(
          detail
            ? `Timed out waiting for app-server: ${detail}`
            : "Timed out waiting for app-server",
        ),
      );
    }, TIMEOUT_MS);

    child.on("error", (error) => finish(error));
    child.stderr.on("data", (chunk) => {
      stderr += chunk.toString("utf8");
      if (stderr.length > 8_192) {
        stderr = stderr.slice(-8_192);
      }
    });
    child.stdout.on("data", (chunk) => {
      stdout += chunk.toString("utf8");

      let newlineIndex;
      while ((newlineIndex = stdout.indexOf("\n")) >= 0) {
        const line = stdout.slice(0, newlineIndex).trim();
        stdout = stdout.slice(newlineIndex + 1);
        if (!line) {
          continue;
        }

        let message;
        try {
          message = JSON.parse(line);
        } catch {
          continue;
        }

        if (message.id === 0) {
          if (message.error) {
            finish(new Error(message.error.message ?? "Initialization failed"));
            return;
          }
          send({ method: "initialized" });
          send({ method: "account/rateLimits/read", id: 1 });
          send({
            method: "account/read",
            id: 2,
            params: { refreshToken: false },
          });
          continue;
        }

        if (message.id === 1) {
          if (message.error) {
            finish(new Error(message.error.message ?? "Quota query failed"));
            return;
          }
          rateLimitResult = message.result;
        }

        if (message.id === 2) {
          if (message.error) {
            finish(new Error(message.error.message ?? "Account query failed"));
            return;
          }
          accountResult = message.result;
        }

        if (rateLimitResult !== null && accountResult !== null) {
          finish(null, sanitizeResult(rateLimitResult, accountResult));
          return;
        }
      }
    });

    send({
      method: "initialize",
      id: 0,
      params: {
        clientInfo: {
          name: "codex_pet_quota",
          title: "Codex Pet Quota",
          version: "0.1.0",
        },
        capabilities: {
          optOutNotificationMethods: ["account/rateLimits/updated"],
        },
      },
    });
  });
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (!args.codex) {
    throw new Error("Usage: node quota-probe.mjs --codex <codex.exe>");
  }

  await access(args.codex, constants.X_OK);
  const [result, tokenStats] = await Promise.all([
    queryRateLimits(args.codex),
    readWeeklyTokenUsage(),
  ]);
  result.tokenStats = tokenStats;
  process.stdout.write(`${JSON.stringify(result)}\n`);
}

main().catch((error) => {
  const message =
    error instanceof Error ? error.message : "Unknown quota probe error";
  process.stderr.write(`${message}\n`);
  process.exitCode = 1;
});
