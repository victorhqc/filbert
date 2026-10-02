#!/usr/bin/env python3
import json
import os
import plistlib
import re
import signal
import subprocess
import sys
import tempfile
import time
import unittest
import uuid
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
BUILD_SCRIPT = ROOT / "scripts/build-dmg.sh"
LIBRARY_VALIDATION_EXCEPTION = "com.apple.security.cs.disable-library-validation"
SCRIPT_FUNCTIONS = BUILD_SCRIPT.read_text().rsplit('\nmain "$@"', 1)[0]

CODESIGN_STUB = """\
import json
import os
import plistlib
import signal
import sys
import time

args = sys.argv[1:]
entitlements = None
if "--entitlements" in args:
    with open(args[args.index("--entitlements") + 1], "rb") as source:
        entitlements = plistlib.load(source)
with open(os.environ["CODESIGN_LOG"], "a") as log:
    log.write(json.dumps({"args": args, "entitlements": entitlements}) + "\\n")
if args[-1] == os.environ.get("BLOCK_SIGN_TARGET"):
    for signum in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        signal.signal(signum, signal.SIG_IGN)
    with open(os.environ["SIGN_RECORD"], "w") as record:
        record.write(json.dumps({"pid": os.getpid(), "parent_pid": os.getppid()}))
    while True:
        time.sleep(0.05)
if args[-1] == os.environ.get("FAIL_SIGN_TARGET") and "--verify" not in args:
    sys.exit(1)
if "--verify" in args and os.environ.get("FAIL_VERIFY") == "yes":
    sys.exit(1)
if "-dvv" in args:
    print("TeamIdentifier=" + os.environ.get("STUB_TEAM", "TESTTEAM01"), file=sys.stderr)
"""

LAUNCH_FIXTURE = """\
import json
import os
import resource
import signal
import sys
import time
from pathlib import Path

resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
behavior = os.environ["FIXTURE_BEHAVIOR"]
if behavior == "ignore-term":
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
record = Path(os.environ["LAUNCH_RECORD"])
temporary = record.with_suffix(".tmp")
temporary.write_text(json.dumps({
    "args": sys.argv[1:], "pid": os.getpid(), "parent_pid": os.getppid(),
}))
temporary.replace(record)
if behavior == "exit":
    sys.exit(0)
if behavior == "abort":
    os.abort()
if behavior == "delayed-exit":
    time.sleep(1)
    sys.exit(7)
while True:
    time.sleep(0.05)
"""

FOUNDATION_FIXTURE = r"""
import Darwin
import Foundation

func require(_ condition: Bool, _ message: String) {
    if !condition {
        let path = ProcessInfo.processInfo.environment["LAUNCH_RECORD"]!
        try? Data(message.utf8).write(to: URL(fileURLWithPath: path))
        fputs(message + "\n", stderr)
        exit(1)
    }
}

let environment = ProcessInfo.processInfo.environment
let expectedBundleID = environment["FIXTURE_BUNDLE_ID"]!
let recordURL = URL(fileURLWithPath: environment["LAUNCH_RECORD"]!)
let sentinelURL = URL(fileURLWithPath: environment["PREFERENCE_SENTINEL"]!)
let sentinelData = try Data(contentsOf: sentinelURL)
let sentinel = try PropertyListSerialization.propertyList(from: sentinelData, format: nil) as! NSDictionary
require(Bundle.main.bundleURL.pathExtension == "app", "Fixture is not an app bundle")
require(Bundle.main.bundleIdentifier == expectedBundleID, "Unexpected defaults domain")
require(NSHomeDirectory() == environment["CFFIXED_USER_HOME"]!, "Foundation home is not isolated")

let defaults = UserDefaults.standard
let before = defaults.persistentDomain(forName: expectedBundleID)
require(before == nil, "Fixture defaults domain already exists")
defaults.register(defaults: sentinel as! [String: Any])
let registration = defaults.volatileDomain(forName: UserDefaults.registrationDomain)
let registeredProviders = registration["provider-enablement"] as! [String: Bool]
require(registeredProviders.values.allSatisfy { $0 }, "Conflicting baseline was not registered")
let argumentDomain = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
let providers = defaults.dictionary(forKey: "provider-enablement") as? [String: Bool]
require(providers != nil, "Provider map did not bridge to [String: Bool]")
let disabled = providers!
require(Set(disabled.keys) == Set(["first-provider", "second-provider"]), "Wrong provider IDs")
require(disabled.values.allSatisfy { !$0 }, "A provider was not disabled")
require((argumentDomain["provider-enablement"] as? [String: Bool]) == disabled, "Not an argument override")
require(!defaults.bool(forKey: "automatic-refresh-enabled"), "Automatic refresh is enabled")
require(!defaults.bool(forKey: "SUEnableAutomaticChecks"), "Sparkle automatic checks are enabled")
require(!defaults.bool(forKey: "SUAutomaticallyUpdate"), "Sparkle automatic downloads are enabled")
require(defaults.bool(forKey: "SUHasLaunchedBefore"), "Sparkle would write first-launch state")
let enabledProviders = disabled.filter { $0.value }
let automaticRefreshMap = defaults.bool(forKey: "automatic-refresh-enabled") ? enabledProviders : [:]
require(automaticRefreshMap.isEmpty, "Automatic refresh map is not empty")
defaults.synchronize()
let after = defaults.persistentDomain(forName: expectedBundleID)
require(after == nil, "Persistent preferences changed")
require(try Data(contentsOf: sentinelURL) == sentinelData, "Sentinel file changed")
let record: [String: Any] = [
    "pid": Int(getpid()),
    "parent_pid": Int(getppid()),
    "args": Array(CommandLine.arguments.dropFirst()),
    "disabledProviders": disabled,
    "automaticRefreshMap": automaticRefreshMap,
    "persistentUnchanged": true,
    "bundleIdentifier": Bundle.main.bundleIdentifier!,
]
try JSONSerialization.data(withJSONObject: record).write(to: recordURL, options: .atomic)
while true {
    Thread.sleep(forTimeInterval: 0.05)
}
"""


class ScriptTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory(prefix="filbert-script-tests-")
        self.addCleanup(directory.cleanup)
        self.directory = Path(directory.name)
        self.bin = self.directory / "bin"
        self.bin.mkdir()
        self.home = self.directory / "home"
        self.home.mkdir()
        self.home_sentinel = self.home / "preferences-sentinel"
        self.home_sentinel.write_text("Do not change preferences\n")
        self.temporary = self.directory / "temporary"
        self.temporary.mkdir()
        self.repo = self.directory / "repo"
        self.repo.mkdir()
        self.providers = self.repo / "Sources/Providers"
        self.providers.mkdir(parents=True)
        self.add_provider("First", "first-provider")
        self.add_provider("Second", "second-provider")
        packaging = self.repo / "packaging"
        packaging.mkdir()
        self.entitlements = packaging / "Filbert.entitlements"
        self.baseline = {
            "com.apple.security.network.client": True,
            "future-entitlement": {"values": ["preserve", "me"], "enabled": False},
        }
        self.entitlements.write_bytes(plistlib.dumps(self.baseline))
        self.baseline_bytes = self.entitlements.read_bytes()
        self.info_template = packaging / "Info.plist"
        self.info_template.write_bytes(plistlib.dumps({}))
        self.app = self.directory / "Filbert fixture.app"
        self.framework = self.app / "Contents/Frameworks/Sparkle.framework"
        self.nested = [
            self.framework / "Versions/B/XPCServices/Installer.xpc",
            self.framework / "Versions/B/XPCServices/Downloader.xpc",
            self.framework / "Versions/B/Autoupdate",
            self.framework / "Versions/B/Updater.app",
        ]
        for path in self.nested:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.touch()
        self.helper = self.app / "Contents/Resources/ClaudeCodeStatuslineHelper"
        self.helper.parent.mkdir(parents=True)
        self.helper.touch()
        self.executable = self.app / "Contents/MacOS/Filbert"
        self.executable.parent.mkdir(parents=True)
        self.write_executable(self.executable, LAUNCH_FIXTURE)
        self.write_executable(self.bin / "codesign", CODESIGN_STUB)
        (self.bin / "python3").symlink_to(sys.executable)
        self.codesign_log = self.directory / "codesign.jsonl"
        self.launch_record = self.directory / "launch.json"
        self.environment = {
            "PATH": str(self.bin) + os.pathsep + os.environ["PATH"],
            "HOME": str(self.home),
            "TMPDIR": str(self.temporary),
            "PYTHONDONTWRITEBYTECODE": "1",
            "FIXTURE_ROOT": str(self.repo),
            "FIXTURE_APP": str(self.app),
            "CODESIGN_LOG": str(self.codesign_log),
            "LAUNCH_RECORD": str(self.launch_record),
            "FIXTURE_BEHAVIOR": "stable",
        }
        self.harness = self.directory / "harness.sh"

    def write_executable(self, path, source):
        path.write_text(f"#!{sys.executable}\n" + source)
        path.chmod(0o755)

    def add_provider(self, module, provider_id):
        directory = self.providers / module
        directory.mkdir()
        source = directory / f"{module}Provider.swift"
        source.write_text(
            f"public struct {module}Provider: AIProvider {{\n"
            f'    public static let providerId = "{provider_id}"\n'
            "}\n"
        )
        return source

    def harness_command(self, commands):
        self.harness.write_text(
            SCRIPT_FUNCTIONS + """
REPO_ROOT="$FIXTURE_ROOT"
ENTITLEMENTS="$REPO_ROOT/packaging/Filbert.entitlements"
INFO_PLIST_TEMPLATE="$REPO_ROOT/packaging/Info.plist"
SIGN_IDENTITY="Developer ID Application: Test Fixture (TESTTEAM01)"
APPLE_DEVELOPER_ID_TEAM_ID="TESTTEAM01"
""" + commands + "\n"
        )
        return ["bash", str(self.harness)]

    def run_function(self, commands, **environment):
        return subprocess.run(
            self.harness_command(commands),
            env=dict(self.environment, **environment),
            cwd=self.directory,
            capture_output=True,
            text=True,
            timeout=15,
            check=False,
        )

    def signing_records(self):
        return [json.loads(line) for line in self.codesign_log.read_text().splitlines()]

    def assert_immutable_baseline(self):
        self.assertEqual(self.entitlements.read_bytes(), self.baseline_bytes)
        self.assertEqual(list(self.temporary.iterdir()), [])
        self.assertEqual(list(self.app.rglob("*entitlements*")), [])

    def assert_child_reaped(self):
        record = json.loads(self.launch_record.read_text())
        with self.assertRaises(ProcessLookupError):
            os.kill(record["pid"], 0)
        return record

    def assert_safe_arguments(self, record, expected_ids=None):
        args = record["args"]
        self.assertEqual(len(args), 10)
        overrides = dict(zip(args[::2], args[1::2]))
        providers = plistlib.loads(overrides["-provider-enablement"].encode())
        self.assertEqual(
            providers,
            dict.fromkeys(expected_ids or ["first-provider", "second-provider"], False),
        )
        self.assertTrue(all(type(value) is bool for value in providers.values()))
        self.assertIn("<false/>", overrides["-provider-enablement"])
        self.assertEqual(overrides["-automatic-refresh-enabled"], "NO")
        self.assertEqual(overrides["-SUEnableAutomaticChecks"], "NO")
        self.assertEqual(overrides["-SUAutomaticallyUpdate"], "NO")
        self.assertEqual(overrides["-SUHasLaunchedBefore"], "YES")
        self.assertEqual(self.home_sentinel.read_text(), "Do not change preferences\n")
        self.assertEqual(list(self.home.iterdir()), [self.home_sentinel])

    def stop_process(self, process):
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=2)
        if process.stdout:
            process.stdout.close()
        if process.stderr:
            process.stderr.close()

    def wait_for_record(self, path, process):
        deadline = time.monotonic() + 5
        while not path.exists() and time.monotonic() < deadline:
            self.assertIsNone(process.poll(), "Fixture exited before recording its PID")
            time.sleep(0.02)
        self.assertTrue(path.exists(), "Fixture did not record its PID")


class SigningPolicyTests(ScriptTests):
    def test_adhoc_exception_is_host_only_and_preserves_future_baseline_keys(self):
        result = self.run_function('sign_adhoc "$FIXTURE_APP"')
        self.assertEqual(result.returncode, 0, result.stderr)
        records = self.signing_records()
        self.assertEqual(
            [record["args"][-1] for record in records],
            list(map(str, self.nested + [self.framework, self.helper, self.app])),
        )
        for record in records:
            args = record["args"]
            self.assertEqual(args[args.index("--options") + 1], "runtime")
            self.assertEqual(args[args.index("-s") + 1], "-")
            self.assertNotIn("--timestamp", args)
        for record in records[:-1]:
            self.assertNotIn("--entitlements", record["args"])
            self.assertIsNone(record["entitlements"])
        self.assertIn("--preserve-metadata=entitlements", records[1]["args"])
        host = records[-1]
        self.assertEqual(
            host["entitlements"],
            dict(self.baseline, **{LIBRARY_VALIDATION_EXCEPTION: True}),
        )
        path = Path(host["args"][host["args"].index("--entitlements") + 1])
        self.assertNotEqual(path, self.entitlements)
        self.assertFalse(path.exists())
        self.assert_immutable_baseline()

    def test_adhoc_temp_entitlements_are_removed_on_signing_failure(self):
        for target in (self.nested[0], self.helper, self.app):
            with self.subTest(target=target):
                result = self.run_function(
                    'sign_adhoc "$FIXTURE_APP"', FAIL_SIGN_TARGET=str(target)
                )
                self.assertNotEqual(result.returncode, 0)
                self.assert_immutable_baseline()

    def test_adhoc_invalid_baseline_fails_before_signing_and_removes_temp_file(self):
        self.entitlements.write_text("not a plist")
        result = self.run_function('sign_adhoc "$FIXTURE_APP"')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.codesign_log.exists())
        self.assertEqual(list(self.temporary.iterdir()), [])
        self.assertEqual(self.entitlements.read_text(), "not a plist")

    def test_outer_script_cancellation_reaps_blocking_signer_and_removes_entitlements(self):
        for signum in (signal.SIGTERM, signal.SIGHUP, signal.SIGINT):
            with self.subTest(signal=signum):
                sign_record = self.directory / f"sign-{signum}.json"
                harness = subprocess.Popen(
                    self.harness_command('sign_adhoc "$FIXTURE_APP"'),
                    env=dict(
                        self.environment,
                        BLOCK_SIGN_TARGET=str(self.app),
                        SIGN_RECORD=str(sign_record),
                    ),
                    cwd=self.directory,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                )
                self.addCleanup(self.stop_process, harness)
                self.wait_for_record(sign_record, harness)
                record = json.loads(sign_record.read_text())
                self.assertEqual(len(list(self.temporary.iterdir())), 1)
                start = time.monotonic()
                harness.send_signal(signum)
                harness.communicate(timeout=8)
                self.assertEqual(harness.returncode, 128 + signum)
                self.assertLess(time.monotonic() - start, 8)
                for pid in (record["pid"], record["parent_pid"]):
                    with self.assertRaises(ProcessLookupError):
                        os.kill(pid, 0)
                self.assert_immutable_baseline()

    def test_developer_id_keeps_baseline_identity_runtime_timestamp_and_verification(self):
        result = self.run_function('sign_devid "$FIXTURE_APP"')
        self.assertEqual(result.returncode, 0, result.stderr)
        records = self.signing_records()
        signed = records[:7]
        self.assertEqual(
            [record["args"][-1] for record in signed],
            list(map(str, self.nested + [self.framework, self.helper, self.app])),
        )
        for record in signed:
            args = record["args"]
            self.assertEqual(args[args.index("--options") + 1], "runtime")
            self.assertEqual(
                args[args.index("-s") + 1],
                "Developer ID Application: Test Fixture (TESTTEAM01)",
            )
        for record in signed[:-1]:
            self.assertIsNone(record["entitlements"])
            self.assertNotIn("--entitlements", record["args"])
        self.assertIn("--preserve-metadata=entitlements", signed[1]["args"])
        self.assertIn("--timestamp", signed[-2]["args"])
        host = signed[-1]
        self.assertIn("--timestamp", host["args"])
        self.assertEqual(host["entitlements"], self.baseline)
        self.assertNotIn(LIBRARY_VALIDATION_EXCEPTION, host["entitlements"])
        self.assertEqual(
            host["args"][host["args"].index("--entitlements") + 1],
            str(self.entitlements),
        )
        self.assertEqual(
            records[7]["args"],
            ["--verify", "--deep", "--strict", "--verbose=4", str(self.app)],
        )
        self.assertEqual(records[8]["args"], ["-dvv", str(self.app)])
        self.assert_immutable_baseline()

    def test_developer_id_rejects_wrong_signature_team(self):
        result = self.run_function('sign_devid "$FIXTURE_APP"', STUB_TEAM="OTHERTEAM")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Signature carries TeamIdentifier=OTHERTEAM", result.stderr)
        self.assert_immutable_baseline()

    def test_local_entitlements_do_not_leak_into_later_developer_id_signing(self):
        result = self.run_function(
            'sign_adhoc "$FIXTURE_APP"\nsign_devid "$FIXTURE_APP"'
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        hosts = [
            record for record in self.signing_records()
            if record["args"][-1] == str(self.app) and "--entitlements" in record["args"]
        ]
        self.assertEqual(len(hosts), 2)
        self.assertTrue(hosts[0]["entitlements"][LIBRARY_VALIDATION_EXCEPTION])
        self.assertEqual(hosts[1]["entitlements"], self.baseline)
        self.assert_immutable_baseline()

    def test_developer_id_rejects_failed_strict_signature_verification(self):
        result = self.run_function('sign_devid "$FIXTURE_APP"', FAIL_VERIFY="yes")
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("Developer ID signed and verified", result.stderr)
        self.assert_immutable_baseline()


class LaunchCheckTests(ScriptTests):
    def test_immediate_exit_and_abort_fail(self):
        for behavior in ("exit", "abort"):
            with self.subTest(behavior=behavior):
                result = self.run_function(
                    'launch_smoke_test "$FIXTURE_APP"', FIXTURE_BEHAVIOR=behavior
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("exited during startup", result.stderr)
                self.assert_safe_arguments(self.assert_child_reaped())

    def test_exit_during_startup_interval_fails(self):
        start = time.monotonic()
        result = self.run_function(
            'launch_smoke_test "$FIXTURE_APP"', FIXTURE_BEHAVIOR="delayed-exit"
        )
        elapsed = time.monotonic() - start
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("status 7", result.stderr)
        self.assertGreaterEqual(elapsed, 1)
        self.assertLess(elapsed, 10)
        self.assert_safe_arguments(self.assert_child_reaped())

    def test_stable_process_passes_full_interval_and_is_reaped(self):
        start = time.monotonic()
        result = self.run_function('launch_smoke_test "$FIXTURE_APP"')
        elapsed = time.monotonic() - start
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertGreaterEqual(elapsed, 5)
        self.assertLess(elapsed, 12)
        self.assert_safe_arguments(self.assert_child_reaped())
        self.assertEqual(list(self.temporary.iterdir()), [])

    def test_termination_escalates_for_child_that_ignores_sigterm(self):
        start = time.monotonic()
        result = self.run_function(
            'launch_smoke_test "$FIXTURE_APP"', FIXTURE_BEHAVIOR="ignore-term"
        )
        elapsed = time.monotonic() - start
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertGreaterEqual(elapsed, 7)
        self.assertLess(elapsed, 12)
        self.assert_child_reaped()

    def test_matching_unrelated_process_neither_passes_crash_nor_gets_killed(self):
        unrelated_record = self.directory / "unrelated.json"
        unrelated = subprocess.Popen(
            [str(self.executable)],
            env=dict(self.environment, LAUNCH_RECORD=str(unrelated_record)),
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        self.addCleanup(self.stop_process, unrelated)
        self.wait_for_record(unrelated_record, unrelated)
        for behavior, expected_status in (("exit", 1), ("stable", 0)):
            with self.subTest(behavior=behavior):
                result = self.run_function(
                    'launch_smoke_test "$FIXTURE_APP"', FIXTURE_BEHAVIOR=behavior
                )
                self.assertEqual(result.returncode, expected_status, result.stderr)
                self.assertIsNone(unrelated.poll())
                self.assert_child_reaped()

    def test_interrupted_supervisor_fails_and_reaps_exact_child(self):
        harness = subprocess.Popen(
            self.harness_command('launch_smoke_test "$FIXTURE_APP"'),
            env=dict(self.environment, FIXTURE_BEHAVIOR="ignore-term"),
            cwd=self.directory,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        self.addCleanup(self.stop_process, harness)
        self.wait_for_record(self.launch_record, harness)
        supervisor = json.loads(self.launch_record.read_text())["parent_pid"]
        start = time.monotonic()
        os.kill(supervisor, signal.SIGTERM)
        _, stderr = harness.communicate(timeout=8)
        self.assertNotEqual(harness.returncode, 0, stderr)
        self.assertIn("interrupted by signal", stderr)
        self.assertLess(time.monotonic() - start, 8)
        self.assert_child_reaped()

    def test_terminated_build_script_reaps_supervisor_and_exact_child(self):
        harness = subprocess.Popen(
            self.harness_command('launch_smoke_test "$FIXTURE_APP"'),
            env=dict(self.environment, FIXTURE_BEHAVIOR="ignore-term"),
            cwd=self.directory,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        self.addCleanup(self.stop_process, harness)
        self.wait_for_record(self.launch_record, harness)
        supervisor = json.loads(self.launch_record.read_text())["parent_pid"]
        harness.terminate()
        harness.communicate(timeout=8)
        self.assertNotEqual(harness.returncode, 0)
        self.assert_child_reaped()
        with self.assertRaises(ProcessLookupError):
            os.kill(supervisor, 0)

    def test_new_provider_gets_disabled_without_hardcoded_id_list(self):
        self.add_provider("Future", "future-provider")
        result = self.run_function(
            'launch_smoke_test "$FIXTURE_APP"', FIXTURE_BEHAVIOR="exit"
        )
        self.assertIn("exited during startup", result.stderr)
        self.assert_safe_arguments(
            self.assert_child_reaped(),
            ["first-provider", "second-provider", "future-provider"],
        )

    def test_comments_escaped_identifiers_and_unrelated_metadata_cannot_select_wrong_id(self):
        sources = [
            '/* public static let providerId = "obsolete" */\n'
            'public struct FutureProvider: AIProvider {\n'
            '    public static let `providerId` = "future-provider"\n'
            '}\n',
            '/* outer /* public struct Obsolete: AIProvider {\n'
            'public static let providerId = "obsolete" } */ still a comment */\n'
            'public enum Metadata { public static let providerId = "unrelated" }\n'
            'struct FutureProvider: AIProvider {\n'
            '    static let `providerId`: String = "future-provider" // obsolete\n'
            '}\n',
            'public enum Metadata { public static let providerId = "unrelated" }\n'
            'public struct FutureProvider: AIProvider {\n'
            '    public static let providerId /* nested /* comment */ */ = "future-provider"\n'
            '    let text = #"public struct Fake: AIProvider { let providerId = "fake" }"#\n'
            '    let nestedText = "\\(String(describing: "public struct Fake: AIProvider { }"))"\n'
            '}\n',
        ]
        future = self.providers / "Future"
        future.mkdir()
        source = future / "Provider.swift"
        for text in sources:
            with self.subTest(source=text):
                source.write_text(text)
                result = self.run_function(
                    'launch_smoke_test "$FIXTURE_APP"', FIXTURE_BEHAVIOR="exit"
                )
                self.assertIn("exited during startup", result.stderr)
                self.assert_safe_arguments(
                    self.assert_child_reaped(),
                    ["first-provider", "second-provider", "future-provider"],
                )

    def test_ambiguous_computed_and_escaped_provider_literals_fail_before_launch(self):
        sources = [
            'public static var `providerId`: String { "future-provider" }',
            r'public static let providerId = "future\u{2d}provider"',
            'public static let providerId = #"future-provider"#',
            'public static let providerId = "\\(prefix)-provider"',
            'public static let providerId = "future-provider"\n + suffix',
            'public static let providerId = "future-provider"\n .lowercased()',
            'public static let providerId = "future-provider"\n'
            'public static let `providerId` = "other"',
            'enum Nested { static let providerId = "nested" }',
        ]
        future = self.providers / "Future"
        future.mkdir()
        source = future / "Provider.swift"
        for declaration in sources:
            with self.subTest(declaration=declaration):
                source.write_text(
                    'public enum Metadata { public static let providerId = "unrelated" }\n'
                    f"public struct FutureProvider: AIProvider {{\n{declaration}\n}}\n"
                )
                result = self.run_function('launch_smoke_test "$FIXTURE_APP"')
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Cannot obtain a safe disabled-provider map", result.stderr)
                self.assertFalse(self.launch_record.exists())

    def test_unsupported_conformances_and_lexical_ambiguity_fail_before_launch(self):
        sources = [
            'public struct FutureProvider {}\n'
            'extension FutureProvider: AIProvider { static let providerId = "future" }',
            'protocol FutureProtocol: AIProvider {}\n'
            'struct FutureProvider: FutureProtocol { static let providerId = "future" }',
            'typealias FutureProtocol = AIProvider\n'
            'struct FutureProvider: FutureProtocol { static let providerId = "future" }',
            '#if DEBUG\n'
            'struct FutureProvider: AIProvider { static let providerId = "future" }\n'
            '#endif',
            'struct FutureProvider: AIProvider { static let providerId = "future" }\n'
            'struct OtherProvider: AIProvider { static let providerId = "other" }',
            'struct FutureProvider: AIProvider { static let providerId = "future" }\n'
            'let pattern = /public struct Fake: AIProvider { }/',
            '/* unterminated /* nested */\n'
            'struct FutureProvider: AIProvider { static let providerId = "future" }',
        ]
        future = self.providers / "Future"
        future.mkdir()
        source = future / "Provider.swift"
        for text in sources:
            with self.subTest(source=text):
                source.write_text(text)
                result = self.run_function('launch_smoke_test "$FIXTURE_APP"')
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Cannot obtain a safe disabled-provider map", result.stderr)
                self.assertFalse(self.launch_record.exists())

    @unittest.skipUnless(sys.platform == "darwin", "Requires native macOS Foundation")
    def test_native_foundation_argument_bridge_preserves_temporary_persistent_domain(self):
        bundle_id = "com.filbert.smoke-test." + uuid.uuid4().hex
        info = {
            "CFBundleIdentifier": bundle_id,
            "CFBundleExecutable": "Filbert",
            "CFBundleName": "Filbert fixture",
            "CFBundlePackageType": "APPL",
            "CFBundleVersion": "1.2.3",
            "CFBundleShortVersionString": "1.2.3",
        }
        (self.app / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
        preferences = self.home / "Library/Preferences"
        preferences.mkdir(parents=True)
        sentinel = preferences / f"{bundle_id}.plist"
        persistent = {
            "provider-enablement": {"first-provider": True, "second-provider": True},
            "automatic-refresh-enabled": True,
            "SUEnableAutomaticChecks": True,
            "SUAutomaticallyUpdate": True,
            "SUHasLaunchedBefore": False,
            "untouched-sentinel": uuid.uuid4().hex,
        }
        sentinel.write_bytes(plistlib.dumps(persistent))
        source = self.directory / "FoundationFixture.swift"
        source.write_text(FOUNDATION_FIXTURE)
        native_environment = dict(
            self.environment,
            CFFIXED_USER_HOME=str(self.home),
            FIXTURE_BUNDLE_ID=bundle_id,
            PREFERENCE_SENTINEL=str(sentinel),
            CLANG_MODULE_CACHE_PATH=str(self.directory / "module-cache"),
        )
        compiled = subprocess.run(
            [
                "/usr/bin/swiftc", str(source),
                "-module-cache-path", str(self.directory / "module-cache"),
                "-o", str(self.executable),
            ],
            env=native_environment,
            cwd=self.directory,
            capture_output=True,
            text=True,
            timeout=120,
            check=False,
        )
        self.assertEqual(compiled.returncode, 0, compiled.stderr)
        before = {path.name: path.read_bytes() for path in preferences.iterdir() if path.is_file()}
        result = self.run_function(
            'launch_smoke_test "$FIXTURE_APP"',
            CFFIXED_USER_HOME=str(self.home),
            FIXTURE_BUNDLE_ID=bundle_id,
            PREFERENCE_SENTINEL=str(sentinel),
        )
        diagnostic = self.launch_record.read_text() if self.launch_record.exists() else ""
        self.assertEqual(result.returncode, 0, result.stderr + diagnostic)
        record = self.assert_child_reaped()
        self.assertEqual(record["disabledProviders"], dict.fromkeys(
            ["first-provider", "second-provider"], False
        ))
        self.assertEqual(record["automaticRefreshMap"], {})
        self.assertTrue(record["persistentUnchanged"])
        self.assertEqual(record["bundleIdentifier"], bundle_id)
        after = {path.name: path.read_bytes() for path in preferences.iterdir() if path.is_file()}
        self.assertEqual(after, before)
        self.assertEqual(self.home_sentinel.read_text(), "Do not change preferences\n")

    def test_unsafe_provider_metadata_fails_before_launch(self):
        for declaration in (
            'public static var providerId = "future-provider"',
            'public static let providerId = computeId()',
            'public static let providerId = "first-provider"',
            'public static let providerId = "future-provider" + suffix',
            '',
        ):
            with self.subTest(declaration=declaration):
                future = self.providers / "Future"
                future.mkdir(exist_ok=True)
                (future / "Provider.swift").write_text(
                    f"public struct FutureProvider: AIProvider {{\n{declaration}\n}}\n"
                )
                result = self.run_function('launch_smoke_test "$FIXTURE_APP"')
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Cannot obtain a safe disabled-provider map", result.stderr)
                self.assertFalse(self.launch_record.exists())

    def test_empty_provider_metadata_fails_before_launch(self):
        for source in self.providers.glob("*/*.swift"):
            source.unlink()
            source.parent.rmdir()
        result = self.run_function('launch_smoke_test "$FIXTURE_APP"')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("no provider modules", result.stderr)
        self.assertFalse(self.launch_record.exists())

    def test_missing_or_unscoped_provider_metadata_fails_before_launch(self):
        unscoped = self.providers / "UnscopedProvider.swift"
        unscoped.write_text(
            "public struct UnscopedProvider: AIProvider {\n"
            '    public static let providerId = "unscoped"\n'
            "}\n"
        )
        result = self.run_function('launch_smoke_test "$FIXTURE_APP"')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unsupported provider layout", result.stderr)
        self.assertFalse(self.launch_record.exists())
        result = self.run_function(
            'launch_smoke_test "$FIXTURE_APP"',
            FIXTURE_ROOT=str(self.directory / "missing-repo"),
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unsupported provider layout", result.stderr)
        self.assertFalse(self.launch_record.exists())

    def test_repository_provider_metadata_is_supported(self):
        result = self.run_function(
            'launch_smoke_test "$FIXTURE_APP"',
            FIXTURE_ROOT=str(ROOT),
            FIXTURE_BEHAVIOR="exit",
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("exited during startup", result.stderr)
        expected_ids = []
        for source in (ROOT / "Sources/Providers").rglob("*.swift"):
            expected_ids.extend(re.findall(
                r'public static let providerId = "([^"]+)"', source.read_text()
            ))
        self.assertTrue(expected_ids)
        self.assert_safe_arguments(self.assert_child_reaped(), expected_ids)

    def test_skip_launch_flag_remains_available_and_gates_the_launch_call(self):
        result = self.run_function(
            'parse_args --version 1.2.3 --skip-launch-check\n'
            '[[ "$SKIP_LAUNCH_CHECK" == "true" ]]'
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertRegex(
            SCRIPT_FUNCTIONS,
            r'if \[\[ "\$SKIP_LAUNCH_CHECK" == "true" \]\]; then\n'
            r'        info "[^"]*"\n'
            r'    else\n'
            r'        launch_smoke_test "\$verify_app"\n'
            r'    fi',
        )
        self.assertFalse(self.launch_record.exists())

    def test_verification_copy_retains_app_bundle_suffix(self):
        self.assertIn('local verify_app="/tmp/filbert-verify-$$.app"', SCRIPT_FUNCTIONS)

    @unittest.skipUnless(sys.platform == "darwin", "Requires Apple's string catalog compiler")
    def test_string_catalogs_compile_inside_module_resource_bundle(self):
        resources = self.app / "Contents/Resources/filbert_App.bundle"
        resources.mkdir()
        catalog = resources / "Localizable.xcstrings"
        source = ROOT / "Sources/App/Resources/Localizable.xcstrings"
        catalog.write_bytes(source.read_bytes())

        result = self.run_function('compile_string_catalogs "$FIXTURE_APP/Contents/Resources"')

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(catalog.exists())
        entries = json.loads(source.read_text())["strings"]
        for locale in ("en", "de-DE", "es-ES", "es-MX"):
            table = resources / f"{locale}.lproj/Localizable.strings"
            converted = subprocess.run(
                ["plutil", "-convert", "json", "-o", "-", str(table)],
                capture_output=True,
                text=True,
                check=True,
            )
            translations = json.loads(converted.stdout)
            for key in ("General", "Launch at login", "Could not enable launch at login. Try again."):
                self.assertEqual(
                    translations[key],
                    entries[key]["localizations"][locale]["stringUnit"]["value"],
                )
        self.assertIn('compile_string_catalogs "$app_dir/Contents/Resources"', SCRIPT_FUNCTIONS)

    @unittest.skipUnless(sys.platform == "darwin", "Requires Apple's string catalog compiler")
    def test_invalid_string_catalog_stops_packaging(self):
        resources = self.app / "Contents/Resources/filbert_App.bundle"
        resources.mkdir()
        catalog = resources / "Localizable.xcstrings"
        catalog.write_text("invalid catalog")

        result = self.run_function('compile_string_catalogs "$FIXTURE_APP/Contents/Resources"')

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Could not compile string catalog", result.stderr)
        self.assertTrue(catalog.exists())


if __name__ == "__main__":
    unittest.main()
