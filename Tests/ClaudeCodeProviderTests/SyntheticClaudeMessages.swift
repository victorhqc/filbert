import Foundation

/// Synthetic `--output-format json` messages shaped like the documented Claude
/// Code SDK messages. None of them is recovered user output.
enum SyntheticClaudeMessages {
    static func usageText(session: Int?, week: Int?) -> String {
        var lines: [String] = []
        if let session {
            lines.append("Current session: \(session)% used · resets Jul 21 at 12:59am (Europe/Berlin)")
        }
        if let week {
            lines.append("Current week (all models): \(week)% used · resets Jul 24 at 5:59am (Europe/Berlin)")
        }
        return lines.joined(separator: "\n")
    }

    /// The trimmed report a user supplied (providers 16), with every field
    /// they kept.
    static func suppliedReport() -> [String: Any] {
        [
            "session": [
                "total_cost_usd": 0, "total_api_duration_ms": 0, "total_duration_ms": 2672,
                "total_lines_added": 0, "total_lines_removed": 0, "model_usage": [String: Any](),
            ],
            "rate_limits": [
                "limits": [
                    [
                        "kind": "session", "group": "session", "percent": 54,
                        "resets_at": "2026-10-05T13:50:00.473061+00:00", "scope": NSNull(),
                        "severity": "normal", "is_active": true,
                    ],
                    [
                        "kind": "weekly_all", "group": "weekly", "percent": 18,
                        "resets_at": "2026-10-09T06:00:00.473081+00:00", "scope": NSNull(),
                        "severity": "normal", "is_active": false,
                    ],
                    [
                        "kind": "weekly_scoped", "group": "weekly", "percent": 20,
                        "resets_at": "2026-10-09T06:00:00.473239+00:00",
                        "scope": ["model": ["display_name": "Fable"], "surface": NSNull()],
                        "severity": "normal", "is_active": false,
                    ],
                ],
                "extra_usage": [
                    "is_enabled": true, "monthly_limit": NSNull(), "used_credits": 0,
                    "utilization": NSNull(), "currency": "EUR",
                ],
            ],
        ]
    }

    static func report(rows: [[String: Any]]) -> [String: Any] {
        ["rate_limits": ["limits": rows]]
    }

    static func report(session: Any? = nil, week: Any? = nil) -> [String: Any] {
        var rows: [[String: Any]] = []
        if let session {
            rows.append(["kind": "session", "percent": session])
        }
        if let week {
            rows.append(["kind": "weekly_all", "percent": week])
        }
        return report(rows: rows)
    }

    static func initMessage(report: Any? = nil, inventory: [String] = ["Read"]) -> [String: Any] {
        var message: [String: Any] = [
            "type": "system", "subtype": "init", "claude_code_version": "2.1.280",
            "model": "claude-haiku", "cwd": "/tmp/synthetic", "tools": inventory,
            "mcp_servers": [["name": "synthetic", "status": "connected"]],
            "plugins": [["name": "synthetic", "path": "/tmp/synthetic"]],
            "slash_commands": ["usage"],
        ]
        message["usage_report"] = report
        return message
    }

    static func rateLimitEvent() -> [String: Any] {
        ["type": "rate_limit_event", "rate_limit_info": ["status": "allowed", "utilization": 0.54]]
    }

    static func assistant(text: String) -> [String: Any] {
        ["type": "assistant", "message": ["role": "assistant", "content": [["type": "text", "text": text]]]]
    }

    static func toolResultError() -> [String: Any] {
        ["type": "user", "message": ["content": [["type": "tool_result", "is_error": true, "content": "denied"]]]]
    }

    static func result(text: Any? = nil, isError: Any? = false, report: Any? = nil) -> [String: Any] {
        var message: [String: Any] = ["type": "result", "subtype": "success"]
        message["result"] = text
        message["is_error"] = isError
        message["usage_report"] = report
        return message
    }

    static func data(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])
    }
}
