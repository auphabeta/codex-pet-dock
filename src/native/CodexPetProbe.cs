using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using System.Web.Script.Serialization;

namespace CodexPetDock.Native
{
    internal sealed class ChildProcessJob : IDisposable
    {
        private const uint KillOnJobClose = 0x00002000;
        private IntPtr handle;

        [StructLayout(LayoutKind.Sequential)]
        private struct IoCounters
        {
            public UInt64 ReadOperationCount;
            public UInt64 WriteOperationCount;
            public UInt64 OtherOperationCount;
            public UInt64 ReadTransferCount;
            public UInt64 WriteTransferCount;
            public UInt64 OtherTransferCount;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct BasicLimitInformation
        {
            public Int64 PerProcessUserTimeLimit;
            public Int64 PerJobUserTimeLimit;
            public UInt32 LimitFlags;
            public UIntPtr MinimumWorkingSetSize;
            public UIntPtr MaximumWorkingSetSize;
            public UInt32 ActiveProcessLimit;
            public Int64 Affinity;
            public UInt32 PriorityClass;
            public UInt32 SchedulingClass;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct ExtendedLimitInformation
        {
            public BasicLimitInformation BasicLimitInformation;
            public IoCounters IoInfo;
            public UIntPtr ProcessMemoryLimit;
            public UIntPtr JobMemoryLimit;
            public UIntPtr PeakProcessMemoryUsed;
            public UIntPtr PeakJobMemoryUsed;
        }

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
        private static extern IntPtr CreateJobObject(
            IntPtr securityAttributes,
            string name);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool SetInformationJobObject(
            IntPtr job,
            int informationClass,
            IntPtr information,
            uint informationLength);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool AssignProcessToJobObject(
            IntPtr job,
            IntPtr process);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool CloseHandle(IntPtr handle);

        public ChildProcessJob()
        {
            handle = CreateJobObject(IntPtr.Zero, null);
            if (handle == IntPtr.Zero)
            {
                return;
            }
            ExtendedLimitInformation information =
                new ExtendedLimitInformation();
            information.BasicLimitInformation.LimitFlags =
                KillOnJobClose;
            int size = Marshal.SizeOf(typeof(ExtendedLimitInformation));
            IntPtr buffer = Marshal.AllocHGlobal(size);
            try
            {
                Marshal.StructureToPtr(information, buffer, false);
                if (
                    !SetInformationJobObject(
                        handle,
                        9,
                        buffer,
                        (uint)size))
                {
                    CloseHandle(handle);
                    handle = IntPtr.Zero;
                }
            }
            finally
            {
                Marshal.FreeHGlobal(buffer);
            }
        }

        public void Add(Process process)
        {
            if (handle != IntPtr.Zero)
            {
                AssignProcessToJobObject(handle, process.Handle);
            }
        }

        public void Dispose()
        {
            if (handle != IntPtr.Zero)
            {
                CloseHandle(handle);
                handle = IntPtr.Zero;
            }
        }
    }

    internal sealed class BucketResult
    {
        public string key { get; set; }
        public double? usedPercent { get; set; }
        public double? remainingPercent { get; set; }
        public double? windowDurationMins { get; set; }
        public double? resetsAt { get; set; }
    }

    internal sealed class IndividualLimitResult
    {
        public object used { get; set; }
        public object limit { get; set; }
        public double? remainingPercent { get; set; }
        public double? resetAt { get; set; }
    }

    internal sealed class SessionUsage
    {
        public long inputTokens { get; set; }
        public long cachedInputTokens { get; set; }
        public long outputTokens { get; set; }
        public long reasoningOutputTokens { get; set; }
        public long totalTokens { get; set; }

        public void Add(SessionUsage other)
        {
            inputTokens += other.inputTokens;
            cachedInputTokens += other.cachedInputTokens;
            outputTokens += other.outputTokens;
            reasoningOutputTokens += other.reasoningOutputTokens;
            totalTokens += other.totalTokens;
        }

        public bool IsValid()
        {
            return
                inputTokens >= 0 &&
                cachedInputTokens >= 0 &&
                outputTokens >= 0 &&
                reasoningOutputTokens >= 0 &&
                totalTokens >= 0;
        }
    }

    internal sealed class SessionScanResult
    {
        public SessionUsage usage { get; set; }
        public bool hasTokens { get; set; }
        public int tokenEvents { get; set; }
        public int duplicateNotifications { get; set; }
    }

    internal sealed class TokenStatsResult
    {
        public string weekStart { get; set; }
        public long weeklyTokens { get; set; }
        public long inputTokens { get; set; }
        public long cachedInputTokens { get; set; }
        public long freshInputTokens { get; set; }
        public long outputTokens { get; set; }
        public long reasoningOutputTokens { get; set; }
        public double cachedPercent { get; set; }
        public int scannedSessions { get; set; }
        public int tokenEvents { get; set; }
        public int duplicateNotifications { get; set; }
        public int cacheHits { get; set; }
        public int filesParsed { get; set; }
    }

    internal sealed class TokenCacheEntry
    {
        public long size { get; set; }
        public long mtimeMs { get; set; }
        public SessionUsage usage { get; set; }
        public bool hasTokens { get; set; }
        public int tokenEvents { get; set; }
        public int duplicateNotifications { get; set; }

        public bool IsValid()
        {
            return
                size >= 0 &&
                mtimeMs >= 0 &&
                usage != null &&
                usage.IsValid() &&
                tokenEvents >= 0 &&
                duplicateNotifications >= 0;
        }
    }

    internal sealed class TokenCacheDocument
    {
        public int schemaVersion { get; set; }
        public string weekStart { get; set; }
        public Dictionary<string, TokenCacheEntry> files { get; set; }
    }

    internal sealed class ProbeResult
    {
        public string capturedAt { get; set; }
        public string planType { get; set; }
        public List<BucketResult> buckets { get; set; }
        public IndividualLimitResult individualLimit { get; set; }
        public object rateLimitReachedType { get; set; }
        public double resetCreditsAvailable { get; set; }
        public TokenStatsResult tokenStats { get; set; }
    }

    internal static class JsonValue
    {
        public static IDictionary<string, object> Dictionary(object value)
        {
            return value as IDictionary<string, object>;
        }

        public static object Get(
            IDictionary<string, object> dictionary,
            string key)
        {
            object value;
            if (dictionary == null || !dictionary.TryGetValue(key, out value))
            {
                return null;
            }
            return value;
        }

        public static IDictionary<string, object> GetDictionary(
            IDictionary<string, object> dictionary,
            string key)
        {
            return Dictionary(Get(dictionary, key));
        }

        public static string String(object value)
        {
            return value == null
                ? null
                : Convert.ToString(value, CultureInfo.InvariantCulture);
        }

        public static double? Number(object value)
        {
            if (value == null)
            {
                return null;
            }
            double result;
            return double.TryParse(
                Convert.ToString(value, CultureInfo.InvariantCulture),
                NumberStyles.Float,
                CultureInfo.InvariantCulture,
                out result)
                ? (double?)result
                : null;
        }

        public static long Integer(object value)
        {
            double? number = Number(value);
            return number.HasValue
                ? Convert.ToInt64(Math.Round(number.Value))
                : 0L;
        }
    }

    internal sealed class AppServerClient
    {
        private readonly JavaScriptSerializer serializer;

        public AppServerClient(JavaScriptSerializer serializer)
        {
            this.serializer = serializer;
        }

        public ProbeResult Query(string codexExecutable)
        {
            ProcessStartInfo startInfo = new ProcessStartInfo();
            startInfo.FileName = codexExecutable;
            startInfo.Arguments = "app-server --listen stdio://";
            startInfo.UseShellExecute = false;
            startInfo.CreateNoWindow = true;
            startInfo.WindowStyle = ProcessWindowStyle.Hidden;
            startInfo.RedirectStandardInput = true;
            startInfo.RedirectStandardOutput = true;
            startInfo.RedirectStandardError = true;

            using (ChildProcessJob job = new ChildProcessJob())
            using (Process process = new Process())
            {
                process.StartInfo = startInfo;
                StringBuilder errors = new StringBuilder();
                process.ErrorDataReceived += delegate(object sender, DataReceivedEventArgs args)
                {
                    if (!String.IsNullOrWhiteSpace(args.Data))
                    {
                        errors.AppendLine(args.Data);
                        if (errors.Length > 8192)
                        {
                            errors.Remove(0, errors.Length - 8192);
                        }
                    }
                };
                if (!process.Start())
                {
                    throw new InvalidOperationException(
                        "Could not start Codex app-server.");
                }
                job.Add(process);
                process.BeginErrorReadLine();
                process.StandardInput.AutoFlush = true;

                Send(process, new Dictionary<string, object>
                {
                    { "method", "initialize" },
                    { "id", 0 },
                    {
                        "params",
                        new Dictionary<string, object>
                        {
                            {
                                "clientInfo",
                                new Dictionary<string, object>
                                {
                                    { "name", "codex_pet_dock" },
                                    { "title", "Codex Pet Dock" },
                                    { "version", "0.4.0" },
                                }
                            },
                            {
                                "capabilities",
                                new Dictionary<string, object>
                                {
                                    {
                                        "optOutNotificationMethods",
                                        new object[]
                                        {
                                            "account/rateLimits/updated",
                                        }
                                    },
                                }
                            },
                        }
                    },
                });

                IDictionary<string, object> rateLimitResult = null;
                IDictionary<string, object> accountResult = null;
                Stopwatch timeout = Stopwatch.StartNew();
                try
                {
                    while (timeout.ElapsedMilliseconds < 15000)
                    {
                        int remaining = Math.Max(
                            1,
                            15000 - (int)timeout.ElapsedMilliseconds);
                        Task<string> readTask =
                            process.StandardOutput.ReadLineAsync();
                        if (!readTask.Wait(remaining))
                        {
                            break;
                        }
                        string line = readTask.Result;
                        if (line == null)
                        {
                            break;
                        }

                        IDictionary<string, object> message;
                        try
                        {
                            message = JsonValue.Dictionary(
                                serializer.DeserializeObject(line));
                        }
                        catch
                        {
                            continue;
                        }
                        double? id = JsonValue.Number(
                            JsonValue.Get(message, "id"));
                        if (!id.HasValue)
                        {
                            continue;
                        }
                        IDictionary<string, object> error =
                            JsonValue.GetDictionary(message, "error");
                        if (error != null)
                        {
                            string detail = JsonValue.String(
                                JsonValue.Get(error, "message"));
                            throw new InvalidOperationException(
                                String.IsNullOrWhiteSpace(detail)
                                    ? "Codex app-server request failed."
                                    : detail);
                        }

                        if ((int)id.Value == 0)
                        {
                            Send(process, new Dictionary<string, object>
                            {
                                { "method", "initialized" },
                            });
                            Send(process, new Dictionary<string, object>
                            {
                                { "method", "account/rateLimits/read" },
                                { "id", 1 },
                            });
                            Send(process, new Dictionary<string, object>
                            {
                                { "method", "account/read" },
                                { "id", 2 },
                                {
                                    "params",
                                    new Dictionary<string, object>
                                    {
                                        { "refreshToken", false },
                                    }
                                },
                            });
                        }
                        else if ((int)id.Value == 1)
                        {
                            rateLimitResult = JsonValue.GetDictionary(
                                message,
                                "result");
                        }
                        else if ((int)id.Value == 2)
                        {
                            accountResult = JsonValue.GetDictionary(
                                message,
                                "result");
                        }

                        if (rateLimitResult != null && accountResult != null)
                        {
                            return Sanitize(rateLimitResult, accountResult);
                        }
                    }

                    string lastError = errors.ToString().Trim();
                    throw new TimeoutException(
                        String.IsNullOrWhiteSpace(lastError)
                            ? "Timed out waiting for Codex app-server."
                            : "Timed out waiting for Codex app-server: " +
                              LastLine(lastError));
                }
                finally
                {
                    if (!process.HasExited)
                    {
                        try
                        {
                            process.Kill();
                            process.WaitForExit(1000);
                        }
                        catch
                        {
                        }
                    }
                }
            }
        }

        private void Send(Process process, object message)
        {
            process.StandardInput.WriteLine(serializer.Serialize(message));
        }

        private static string LastLine(string value)
        {
            string[] lines = value.Split(
                new[] { "\r\n", "\n" },
                StringSplitOptions.RemoveEmptyEntries);
            return lines.Length == 0 ? value : lines[lines.Length - 1];
        }

        private static BucketResult Bucket(
            IDictionary<string, object> source,
            string key)
        {
            if (source == null)
            {
                return null;
            }
            double? used = JsonValue.Number(
                JsonValue.Get(source, "usedPercent"));
            double? remaining = used.HasValue
                ? Math.Max(0, Math.Min(100, 100 - used.Value))
                : (double?)null;
            return new BucketResult
            {
                key = key,
                usedPercent = used,
                remainingPercent = remaining,
                windowDurationMins = JsonValue.Number(
                    JsonValue.Get(source, "windowDurationMins")),
                resetsAt = JsonValue.Number(
                    JsonValue.Get(source, "resetsAt")),
            };
        }

        private static ProbeResult Sanitize(
            IDictionary<string, object> rateResult,
            IDictionary<string, object> accountResult)
        {
            IDictionary<string, object> limits =
                JsonValue.GetDictionary(rateResult, "rateLimits");
            List<BucketResult> buckets = new List<BucketResult>();
            BucketResult primary = Bucket(
                JsonValue.GetDictionary(limits, "primary"),
                "primary");
            BucketResult secondary = Bucket(
                JsonValue.GetDictionary(limits, "secondary"),
                "secondary");
            if (primary != null)
            {
                buckets.Add(primary);
            }
            if (secondary != null)
            {
                buckets.Add(secondary);
            }

            IDictionary<string, object> account =
                JsonValue.GetDictionary(accountResult, "account");
            IDictionary<string, object> individual =
                JsonValue.GetDictionary(limits, "individualLimit");
            IDictionary<string, object> credits =
                JsonValue.GetDictionary(
                    rateResult,
                    "rateLimitResetCredits");

            return new ProbeResult
            {
                capturedAt = DateTime.UtcNow.ToString("o"),
                planType = JsonValue.String(
                    JsonValue.Get(account, "planType")),
                buckets = buckets,
                individualLimit = individual == null
                    ? null
                    : new IndividualLimitResult
                    {
                        used = JsonValue.Get(individual, "used"),
                        limit = JsonValue.Get(individual, "limit"),
                        remainingPercent = JsonValue.Number(
                            JsonValue.Get(individual, "remainingPercent")),
                        resetAt = JsonValue.Number(
                            JsonValue.Get(individual, "resetAt")),
                    },
                rateLimitReachedType = JsonValue.Get(
                    limits,
                    "rateLimitReachedType"),
                resetCreditsAvailable =
                    JsonValue.Number(
                        JsonValue.Get(credits, "availableCount")) ?? 0,
            };
        }
    }

    internal sealed class TokenUsageIndex
    {
        private static readonly DateTime UnixEpochUtc =
            new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc);
        private static readonly Regex TimestampPattern = new Regex(
            "\"timestamp\"\\s*:\\s*\"(?<value>[^\"]+)\"",
            RegexOptions.Compiled | RegexOptions.CultureInvariant);
        private static readonly Regex TokenFieldPattern = new Regex(
            "\"(?<name>input_tokens|cached_input_tokens|output_tokens|" +
            "reasoning_output_tokens|total_tokens)\"\\s*:\\s*" +
            "(?<value>\\d+)",
            RegexOptions.Compiled | RegexOptions.CultureInvariant);
        private readonly JavaScriptSerializer serializer;

        public TokenUsageIndex(JavaScriptSerializer serializer)
        {
            this.serializer = serializer;
        }

        public TokenStatsResult Read(string cachePath)
        {
            DateTime weekStart = StartOfLocalWeek();
            DateTime cutoffUtc = weekStart.ToUniversalTime();
            string codexHome = Environment.GetEnvironmentVariable("CODEX_HOME");
            if (String.IsNullOrWhiteSpace(codexHome))
            {
                codexHome = Path.Combine(
                    Environment.GetFolderPath(
                        Environment.SpecialFolder.UserProfile),
                    ".codex");
            }
            string sessionsDirectory = Path.Combine(codexHome, "sessions");
            string weekStartText = weekStart
                .ToUniversalTime()
                .ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'");
            TokenCacheDocument cache = LoadCache(cachePath, weekStartText);
            Dictionary<string, TokenCacheEntry> previousFiles =
                cache == null || cache.files == null
                    ? new Dictionary<string, TokenCacheEntry>()
                    : cache.files;
            Dictionary<string, TokenCacheEntry> nextFiles =
                new Dictionary<string, TokenCacheEntry>();

            SessionUsage weekly = new SessionUsage();
            int scannedSessions = 0;
            int tokenEvents = 0;
            int duplicateNotifications = 0;
            int cacheHits = 0;
            int filesParsed = 0;

            if (Directory.Exists(sessionsDirectory))
            {
                foreach (
                    string filePath in Directory.EnumerateFiles(
                        sessionsDirectory,
                        "*.jsonl",
                        SearchOption.AllDirectories))
                {
                    FileInfo info = new FileInfo(filePath);
                    if (info.LastWriteTimeUtc < cutoffUtc)
                    {
                        continue;
                    }
                    string key = HashRelativePath(
                        sessionsDirectory,
                        filePath);
                    long modifiedMilliseconds = Convert.ToInt64(
                        Math.Floor(
                            (info.LastWriteTimeUtc - UnixEpochUtc)
                            .TotalMilliseconds));
                    TokenCacheEntry entry;
                    if (
                        previousFiles.TryGetValue(key, out entry) &&
                        entry != null &&
                        entry.IsValid() &&
                        entry.size == info.Length &&
                        entry.mtimeMs == modifiedMilliseconds)
                    {
                        cacheHits += 1;
                    }
                    else
                    {
                        SessionScanResult scan = ScanSession(
                            filePath,
                            cutoffUtc);
                        entry = new TokenCacheEntry
                        {
                            size = info.Length,
                            mtimeMs = modifiedMilliseconds,
                            usage = scan.usage,
                            hasTokens = scan.hasTokens,
                            tokenEvents = scan.tokenEvents,
                            duplicateNotifications =
                                scan.duplicateNotifications,
                        };
                        filesParsed += 1;
                    }
                    nextFiles[key] = entry;
                    weekly.Add(entry.usage);
                    if (entry.hasTokens)
                    {
                        scannedSessions += 1;
                    }
                    tokenEvents += entry.tokenEvents;
                    duplicateNotifications +=
                        entry.duplicateNotifications;
                }
            }

            SaveCache(
                cachePath,
                new TokenCacheDocument
                {
                    schemaVersion = 1,
                    weekStart = weekStartText,
                    files = nextFiles,
                });

            long fresh = Math.Max(
                0,
                weekly.inputTokens - weekly.cachedInputTokens);
            double cachedPercent = weekly.inputTokens > 0
                ? (double)weekly.cachedInputTokens /
                  (double)weekly.inputTokens * 100.0
                : 0;
            return new TokenStatsResult
            {
                weekStart = weekStartText,
                weeklyTokens = weekly.totalTokens,
                inputTokens = weekly.inputTokens,
                cachedInputTokens = weekly.cachedInputTokens,
                freshInputTokens = fresh,
                outputTokens = weekly.outputTokens,
                reasoningOutputTokens = weekly.reasoningOutputTokens,
                cachedPercent = Math.Round(cachedPercent, 1),
                scannedSessions = scannedSessions,
                tokenEvents = tokenEvents,
                duplicateNotifications = duplicateNotifications,
                cacheHits = cacheHits,
                filesParsed = filesParsed,
            };
        }

        private SessionScanResult ScanSession(
            string filePath,
            DateTime cutoffUtc)
        {
            SessionUsage contribution = new SessionUsage();
            SessionUsage previousUsage = null;
            long sessionTokens = 0;
            int tokenEvents = 0;
            int duplicateNotifications = 0;

            using (
                FileStream stream = new FileStream(
                    filePath,
                    FileMode.Open,
                    FileAccess.Read,
                    FileShare.ReadWrite | FileShare.Delete))
            using (
                StreamReader reader = new StreamReader(
                    stream,
                    Encoding.UTF8,
                    true,
                    65536))
            {
                string line;
                while ((line = reader.ReadLine()) != null)
                {
                    DateTimeOffset timestamp;
                    SessionUsage currentUsage;
                    if (
                        !TryParseTokenEvent(
                            line,
                            out timestamp,
                            out currentUsage))
                    {
                        continue;
                    }

                    if (
                        timestamp.UtcDateTime < cutoffUtc)
                    {
                        previousUsage = currentUsage;
                        continue;
                    }

                    tokenEvents += 1;
                    AddDelta(
                        currentUsage,
                        previousUsage,
                        currentUsage.inputTokens,
                        previousUsage == null
                            ? 0
                            : previousUsage.inputTokens,
                        delegate(long value)
                        {
                            contribution.inputTokens += value;
                        });
                    AddDelta(
                        currentUsage,
                        previousUsage,
                        currentUsage.cachedInputTokens,
                        previousUsage == null
                            ? 0
                            : previousUsage.cachedInputTokens,
                        delegate(long value)
                        {
                            contribution.cachedInputTokens += value;
                        });
                    AddDelta(
                        currentUsage,
                        previousUsage,
                        currentUsage.outputTokens,
                        previousUsage == null
                            ? 0
                            : previousUsage.outputTokens,
                        delegate(long value)
                        {
                            contribution.outputTokens += value;
                        });
                    AddDelta(
                        currentUsage,
                        previousUsage,
                        currentUsage.reasoningOutputTokens,
                        previousUsage == null
                            ? 0
                            : previousUsage.reasoningOutputTokens,
                        delegate(long value)
                        {
                            contribution.reasoningOutputTokens += value;
                        });
                    long totalDelta = CalculateDelta(
                        previousUsage,
                        currentUsage.totalTokens,
                        previousUsage == null
                            ? 0
                            : previousUsage.totalTokens);
                    contribution.totalTokens += totalDelta;
                    sessionTokens += totalDelta;
                    if (previousUsage != null && totalDelta == 0)
                    {
                        duplicateNotifications += 1;
                    }
                    previousUsage = currentUsage;
                }
            }

            return new SessionScanResult
            {
                usage = contribution,
                hasTokens = sessionTokens > 0,
                tokenEvents = tokenEvents,
                duplicateNotifications = duplicateNotifications,
            };
        }

        private static void AddDelta(
            SessionUsage current,
            SessionUsage previous,
            long currentValue,
            long previousValue,
            Action<long> apply)
        {
            apply(CalculateDelta(previous, currentValue, previousValue));
        }

        private static long CalculateDelta(
            SessionUsage previous,
            long currentValue,
            long previousValue)
        {
            return
                previous == null || currentValue < previousValue
                    ? currentValue
                    : currentValue - previousValue;
        }

        private static bool TryParseTokenEvent(
            string line,
            out DateTimeOffset timestamp,
            out SessionUsage usage)
        {
            timestamp = default(DateTimeOffset);
            usage = null;
            if (
                line.IndexOf(
                    "\"event_msg\"",
                    StringComparison.Ordinal) < 0 ||
                line.IndexOf(
                    "\"token_count\"",
                    StringComparison.Ordinal) < 0)
            {
                return false;
            }

            Match timestampMatch = TimestampPattern.Match(line);
            if (
                !timestampMatch.Success ||
                !DateTimeOffset.TryParse(
                    timestampMatch.Groups["value"].Value,
                    CultureInfo.InvariantCulture,
                    DateTimeStyles.AssumeUniversal,
                    out timestamp))
            {
                return false;
            }

            int marker = line.IndexOf(
                "\"total_token_usage\"",
                StringComparison.Ordinal);
            if (marker < 0)
            {
                return false;
            }
            int objectStart = line.IndexOf('{', marker);
            int objectEnd = objectStart < 0
                ? -1
                : line.IndexOf('}', objectStart + 1);
            if (objectStart < 0 || objectEnd <= objectStart)
            {
                return false;
            }

            SessionUsage parsed = new SessionUsage();
            bool hasTotal = false;
            string tokenObject = line.Substring(
                objectStart,
                objectEnd - objectStart + 1);
            foreach (Match field in TokenFieldPattern.Matches(tokenObject))
            {
                long value;
                if (
                    !Int64.TryParse(
                        field.Groups["value"].Value,
                        NumberStyles.None,
                        CultureInfo.InvariantCulture,
                        out value))
                {
                    continue;
                }
                switch (field.Groups["name"].Value)
                {
                    case "input_tokens":
                        parsed.inputTokens = value;
                        break;
                    case "cached_input_tokens":
                        parsed.cachedInputTokens = value;
                        break;
                    case "output_tokens":
                        parsed.outputTokens = value;
                        break;
                    case "reasoning_output_tokens":
                        parsed.reasoningOutputTokens = value;
                        break;
                    case "total_tokens":
                        parsed.totalTokens = value;
                        hasTotal = true;
                        break;
                }
            }
            usage = parsed;
            return hasTotal;
        }

        private TokenCacheDocument LoadCache(
            string cachePath,
            string weekStart)
        {
            if (
                String.IsNullOrWhiteSpace(cachePath) ||
                !File.Exists(cachePath))
            {
                return null;
            }
            try
            {
                FileInfo cacheInfo = new FileInfo(cachePath);
                if (cacheInfo.Length > 5 * 1024 * 1024)
                {
                    return null;
                }
                TokenCacheDocument cache =
                    serializer.Deserialize<TokenCacheDocument>(
                        File.ReadAllText(cachePath, Encoding.UTF8));
                return
                    cache != null &&
                    cache.schemaVersion == 1 &&
                    cache.weekStart == weekStart
                        ? cache
                        : null;
            }
            catch
            {
                return null;
            }
        }

        private void SaveCache(
            string cachePath,
            TokenCacheDocument cache)
        {
            if (String.IsNullOrWhiteSpace(cachePath))
            {
                return;
            }
            string directory = Path.GetDirectoryName(cachePath);
            string temporaryPath =
                cachePath + "." + Process.GetCurrentProcess().Id + ".tmp";
            try
            {
                Directory.CreateDirectory(directory);
                File.WriteAllText(
                    temporaryPath,
                    serializer.Serialize(cache),
                    new UTF8Encoding(false));
                if (File.Exists(cachePath))
                {
                    File.Replace(temporaryPath, cachePath, null);
                }
                else
                {
                    File.Move(temporaryPath, cachePath);
                }
            }
            catch
            {
                try
                {
                    if (File.Exists(temporaryPath))
                    {
                        File.Delete(temporaryPath);
                    }
                }
                catch
                {
                }
            }
        }

        private static string HashRelativePath(
            string root,
            string filePath)
        {
            string relativePath = filePath.Substring(root.Length)
                .TrimStart(Path.DirectorySeparatorChar)
                .Replace(Path.DirectorySeparatorChar, '/');
            using (SHA256 sha256 = SHA256.Create())
            {
                byte[] hash = sha256.ComputeHash(
                    Encoding.UTF8.GetBytes(relativePath));
                StringBuilder result = new StringBuilder(hash.Length * 2);
                foreach (byte value in hash)
                {
                    result.Append(value.ToString("x2"));
                }
                return result.ToString();
            }
        }

        private static DateTime StartOfLocalWeek()
        {
            DateTime today = DateTime.Now.Date;
            int daysSinceMonday =
                ((int)today.DayOfWeek + 6) % 7;
            return today.AddDays(-daysSinceMonday);
        }
    }

    internal static class Program
    {
        private static int Main(string[] args)
        {
            try
            {
                Dictionary<string, string> parsed = ParseArguments(args);
                string codexExecutable;
                string tokenCachePath;
                if (
                    !parsed.TryGetValue("codex", out codexExecutable) ||
                    String.IsNullOrWhiteSpace(codexExecutable) ||
                    !parsed.TryGetValue(
                        "token-cache",
                        out tokenCachePath) ||
                    String.IsNullOrWhiteSpace(tokenCachePath))
                {
                    throw new ArgumentException(
                        "Usage: CodexPetProbe.exe --codex <codex.exe> " +
                        "--token-cache <cache.json>");
                }
                if (!File.Exists(codexExecutable))
                {
                    throw new FileNotFoundException(
                        "Codex executable was not found.",
                        codexExecutable);
                }

                JavaScriptSerializer serializer =
                    new JavaScriptSerializer();
                serializer.MaxJsonLength = 8 * 1024 * 1024;
                AppServerClient appServer = new AppServerClient(serializer);
                TokenUsageIndex tokenIndex =
                    new TokenUsageIndex(serializer);

                Task<ProbeResult> quotaTask = Task.Run(
                    delegate
                    {
                        return appServer.Query(codexExecutable);
                    });
                Task<TokenStatsResult> tokenTask = Task.Run(
                    delegate
                    {
                        return tokenIndex.Read(tokenCachePath);
                    });
                Task.WaitAll(quotaTask, tokenTask);
                ProbeResult result = quotaTask.Result;
                result.tokenStats = tokenTask.Result;
                Console.Out.WriteLine(serializer.Serialize(result));
                return 0;
            }
            catch (AggregateException aggregate)
            {
                Exception error = aggregate.Flatten().InnerException;
                Console.Error.WriteLine(
                    error == null ? aggregate.Message : error.Message);
                return 1;
            }
            catch (Exception error)
            {
                Console.Error.WriteLine(error.Message);
                return 1;
            }
        }

        private static Dictionary<string, string> ParseArguments(
            string[] args)
        {
            Dictionary<string, string> result =
                new Dictionary<string, string>(
                    StringComparer.OrdinalIgnoreCase);
            for (int index = 0; index < args.Length; index += 1)
            {
                if (
                    args[index].StartsWith(
                        "--",
                        StringComparison.Ordinal) &&
                    index + 1 < args.Length)
                {
                    result[args[index].Substring(2)] = args[index + 1];
                    index += 1;
                }
            }
            return result;
        }
    }
}
