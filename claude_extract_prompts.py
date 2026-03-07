"""
Extract user prompts from Claude Code conversation history for the current directory.

Usage:
    python claude_extract_prompts.py [output_file]

Reads JSONL conversation files from ~/.claude/projects/ for the current working
directory and writes a markdown file with all user prompts organized by conversation.

Default output: claude_prompt_history.md
"""

import json
import os
import re
import sys
from datetime import datetime
from pathlib import Path


def get_project_dir():
    """Get the Claude Code project directory for the current working directory."""
    cwd = os.getcwd()
    # Claude Code encodes the path by replacing non-alphanumeric chars with -
    encoded = re.sub(r"[^a-zA-Z0-9]", "-", cwd)
    project_dir = Path.home() / ".claude" / "projects" / encoded
    if not project_dir.exists():
        print(f"No Claude Code history found for {cwd}")
        print(f"  (looked in {project_dir})")
        sys.exit(1)
    return project_dir


def extract_prompts_from_file(fpath):
    """Extract user text prompts from a JSONL conversation file."""
    prompts = []
    with open(fpath) as fh:
        for line in fh:
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue

            if obj.get("type") != "user":
                continue

            msg = obj.get("message", {})
            if not isinstance(msg, dict):
                continue

            content = msg.get("content", "")
            texts = []

            if isinstance(content, str):
                text = clean_text(content)
                if text:
                    texts.append(text)
            elif isinstance(content, list):
                for part in content:
                    if isinstance(part, dict) and part.get("type") == "text":
                        text = clean_text(part.get("text", ""))
                        if text:
                            texts.append(text)

            combined = "\n".join(texts).strip()
            if combined:
                prompts.append(combined)
    return prompts


def clean_text(text):
    """Remove system-injected tags and content from user text."""
    text = text.strip()
    if not text:
        return ""

    # Skip entries that are entirely system-injected
    skip_prefixes = (
        "<ide_opened_file>",
        "<ide_selection>",
        "<system-reminder>",
        "<available-deferred-tools>",
    )
    if text.startswith(skip_prefixes):
        # Check if there's real content after the tag
        cleaned = text
        for tag in ["ide_opened_file", "ide_selection", "system-reminder", "available-deferred-tools"]:
            cleaned = re.sub(rf"<{tag}>.*?</{tag}>", "", cleaned, flags=re.DOTALL)
            cleaned = re.sub(rf"<{tag}>.*", "", cleaned, flags=re.DOTALL)  # unclosed tags
        cleaned = cleaned.strip()
        if not cleaned:
            return ""
        text = cleaned

    # Remove embedded system tags
    for tag in ["system-reminder", "ide_opened_file", "ide_selection", "available-deferred-tools"]:
        text = re.sub(rf"<{tag}>.*?</{tag}>", "", text, flags=re.DOTALL)
        text = re.sub(rf"<{tag}>.*", "", text, flags=re.DOTALL)

    # Remove command metadata tags
    for tag in ["command-message", "command-name"]:
        text = re.sub(rf"<{tag}>.*?</{tag}>", "", text, flags=re.DOTALL)

    return text.strip()


def format_prompt(text):
    """Format a prompt for markdown output."""
    if "\n" in text or len(text) > 200:
        return f"```\n{text}\n```\n"
    return f"{text}\n"


def main():
    output_file = sys.argv[1] if len(sys.argv) > 1 else "claude_prompt_history.md"
    project_dir = get_project_dir()

    # Get conversation files sorted by modification time (oldest first)
    jsonl_files = sorted(
        project_dir.glob("*.jsonl"),
        key=lambda f: f.stat().st_mtime,
    )

    if not jsonl_files:
        print("No conversation files found.")
        sys.exit(1)

    lines = []
    lines.append("# Claude Code Conversation Prompts\n")
    lines.append(f"Project: `{os.getcwd()}`")
    lines.append(f"Exported: {datetime.now().strftime('%Y-%m-%d %H:%M')}\n")

    conv_num = 0
    for fpath in jsonl_files:
        prompts = extract_prompts_from_file(fpath)
        if not prompts:
            continue

        conv_num += 1
        session_id = fpath.stem[:8]
        lines.append("---\n")
        lines.append(f"## Conversation {conv_num} (`{session_id}...`)\n")

        for pi, prompt in enumerate(prompts, 1):
            lines.append(f"### Prompt {pi}\n")
            lines.append(format_prompt(prompt))

    output = "\n".join(lines)

    with open(output_file, "w") as f:
        f.write(output)

    print(f"Exported {conv_num} conversations to {output_file}")


if __name__ == "__main__":
    main()
