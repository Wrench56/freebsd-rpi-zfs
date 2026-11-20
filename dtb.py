#!/usr/bin/env python3
import re
import sys

NODE = re.compile(r"([^\s{};]+\s*\{)([^{}]*)(\};)")


def needs_patch(body):
    return '"fixed-clock"' in body and "clock-frequency" not in body


def fix(match):
    head, body, tail = match.groups()
    if not needs_patch(body):
        return match.group(0)
    prop_indent = re.search(r"\n([ \t]*)\S", body).group(1)
    close_indent = re.search(r"\n([ \t]*)$", body).group(1)
    return f"{head}{body.rstrip()}\n{prop_indent}clock-frequency = <0x0>;\n{close_indent}{tail}"


def main() -> None:
    text = open(sys.argv[1]).read()
    added = sum(needs_patch(body) for _, body, _ in NODE.findall(text))
    open(sys.argv[2], "w").write(NODE.sub(fix, text))
    print(added)


if __name__ == "__main__":
    main()
