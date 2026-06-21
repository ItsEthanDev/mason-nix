#!/usr/bin/env python3
"""Render and send a formatted HTML status report for a snapraid-btrfs run.

Triggered by systemd OnSuccess=/OnFailure= on snapraid-btrfs-sync.service. The
run's own log is pulled from the journal (by the triggering unit's invocation
id, exposed by systemd as MONITOR_INVOCATION_ID), parsed into a summary, and
emailed as a multipart text+HTML message. Non-secret SMTP settings come from
SR_* environment variables; the password comes from SR_PASSWORD_FILE (preferred)
or the SMTP_PASSWORD environment variable.

Designed to degrade gracefully: any failure (journal unreadable, SMTP down) is
logged to stderr and exits 0 so a notification problem never cascades. With no
SMTP host configured it prints the rendered HTML to stdout, which doubles as a
dry-run/preview mode.
"""
import os
import re
import ssl
import sys
import socket
import smtplib
import subprocess
from datetime import datetime
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText


def env(key, default=""):
    return os.environ.get(key, default)


def esc(text):
    return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


status = (sys.argv[1] if len(sys.argv) > 1 else env("SR_STATUS", "failure")).lower()
success = status == "success"
host = env("SR_HOST") or socket.gethostname()
unit = env("SR_UNIT", "snapraid-btrfs-sync.service")
invocation = env("MONITOR_INVOCATION_ID", "")


def read_journal():
    cmd = ["journalctl", "--no-pager", "-o", "cat"]
    if invocation:
        cmd.append("_SYSTEMD_INVOCATION_ID=" + invocation)
    else:
        cmd += ["-u", unit, "-n", "800"]
    try:
        return subprocess.run(
            cmd, capture_output=True, text=True, timeout=30
        ).stdout
    except Exception as exc:
        return "(could not read journal: " + str(exc) + ")"


lines = [ln for ln in read_journal().splitlines() if ln.strip()]


def first_match(pattern):
    rx = re.compile(pattern)
    for ln in lines:
        found = rx.search(ln)
        if found:
            return found
    return None


def has(text):
    return any(text in ln for ln in lines)


diff = first_match(
    r"Diff results:\s*(\d+) added,\s*(\d+) removed,\s*(\d+) moved,\s*(\d+) modified"
)
added, removed, moved, modified = diff.groups() if diff else ("-", "-", "-", "-")

if has("No changes detected"):
    sync_state = "no changes (parity already current)"
elif has("Running sync..."):
    sync_state = "synced"
else:
    sync_state = "-"
scrub_state = "ran" if has("Running scrub...") else "skipped"

errors = [ln for ln in lines if ("[ERROR" in ln) or ("Run failed" in ln)]

ts_rx = re.compile(r"(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})")
stamps = [m.group(1) for ln in lines for m in [ts_rx.search(ln)] if m]
started = stamps[0] if stamps else "-"
finished = stamps[-1] if stamps else "-"


def parse(text):
    try:
        return datetime.strptime(text, "%Y-%m-%d %H:%M:%S")
    except ValueError:
        return None


duration = "-"
if parse(started) and parse(finished):
    duration = str(parse(finished) - parse(started))

accent = "#16a34a" if success else "#dc2626"
result_text = "SUCCESS" if success else "FAILED"
tail = "\n".join(lines[-120:])


def row(label, value):
    return (
        '<tr>'
        '<td style="padding:6px 14px;color:#6b7280;white-space:nowrap;'
        'border-top:1px solid #f0f1f3">' + esc(label) + '</td>'
        '<td style="padding:6px 14px;color:#111827;font-weight:600;'
        'border-top:1px solid #f0f1f3">' + esc(str(value)) + '</td>'
        '</tr>'
    )


summary = "".join([
    row("Host", host),
    row("Result", result_text),
    row("Started", started),
    row("Finished", finished),
    row("Duration", duration),
    row("Files added", added),
    row("Files removed", removed),
    row("Files moved", moved),
    row("Files modified", modified),
    row("Sync", sync_state),
    row("Scrub", scrub_state),
])

errors_html = ""
if errors:
    errors_html = (
        '<div style="margin:16px 14px 0;padding:12px 14px;background:#fef2f2;'
        'border-left:4px solid #dc2626;border-radius:4px;color:#991b1b;'
        'font-family:monospace;font-size:13px;white-space:pre-wrap">'
        + esc("\n".join(errors[-12:])) + '</div>'
    )

html = (
    '<div style="font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,'
    'sans-serif;max-width:660px;margin:0 auto;color:#111827">'
    '<div style="background:' + accent + ';color:#ffffff;padding:18px 22px;'
    'border-radius:8px 8px 0 0">'
    '<div style="font-size:19px;font-weight:700">SnapRAID ' + result_text + '</div>'
    '<div style="font-size:13px;opacity:0.9">' + esc(host)
    + ' &middot; snapraid-btrfs sync</div>'
    '</div>'
    '<div style="border:1px solid #e5e7eb;border-top:none;'
    'border-radius:0 0 8px 8px;padding:6px 8px 18px">'
    '<table style="border-collapse:collapse;width:100%;font-size:14px">'
    + summary + '</table>'
    + errors_html
    + '<div style="margin:18px 14px 6px;color:#6b7280;font-size:12px;'
    'font-weight:600;text-transform:uppercase;letter-spacing:0.04em">'
    'Run log (tail)</div>'
    '<pre style="margin:0 14px;padding:12px 14px;background:#0b1020;'
    'color:#d1d5db;border-radius:6px;font-size:12px;line-height:1.45;'
    'overflow-x:auto;white-space:pre-wrap">' + esc(tail) + '</pre>'
    '</div></div>'
)

plain = "\n".join([
    "SnapRAID " + result_text + " on " + host,
    "",
    "Started:  " + started,
    "Finished: " + finished,
    "Duration: " + duration,
    "",
    "Files: " + str(added) + " added, " + str(removed) + " removed, "
    + str(moved) + " moved, " + str(modified) + " modified",
    "Sync:  " + sync_state,
    "Scrub: " + scrub_state,
    "",
    "--- run log (tail) ---",
    tail,
])

smtp_host = env("SR_SMTP_HOST")
mail_from = env("SR_EMAIL_FROM")
mail_to = env("SR_EMAIL_TO")
subject = env("SR_EMAIL_SUBJECT", "[SnapRAID] Status Report:") + (
    " SUCCESS" if success else " ERROR"
)

if not smtp_host or not mail_to:
    sys.stdout.write(html + "\n")
    sys.exit(0)


def get_password():
    path = env("SR_PASSWORD_FILE")
    if path and os.path.isfile(path):
        try:
            with open(path, encoding="utf-8") as handle:
                return handle.read().strip()
        except OSError:
            pass
    return env("SMTP_PASSWORD", "")


message = MIMEMultipart("alternative")
message["Subject"] = subject
message["From"] = mail_from
message["To"] = mail_to
message.attach(MIMEText(plain, "plain", "utf-8"))
message.attach(MIMEText(html, "html", "utf-8"))

port = int(env("SR_SMTP_PORT", "587") or "587")
use_ssl = env("SR_SMTP_SSL", "false").lower() == "true"
use_tls = env("SR_SMTP_TLS", "true").lower() == "true"
user = env("SR_SMTP_USER")

try:
    context = ssl.create_default_context()
    if use_ssl:
        server = smtplib.SMTP_SSL(smtp_host, port, timeout=30, context=context)
    else:
        server = smtplib.SMTP(smtp_host, port, timeout=30)
        if use_tls:
            server.starttls(context=context)
    if user:
        server.login(user, get_password())
    server.sendmail(mail_from, [mail_to], message.as_string())
    server.quit()
except Exception as exc:
    sys.stderr.write("snapraid-btrfs email report: send failed: " + str(exc) + "\n")
    sys.exit(0)
