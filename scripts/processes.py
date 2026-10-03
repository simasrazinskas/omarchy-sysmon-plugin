#!/usr/bin/env python3
"""One read-only procfs snapshot. Invoked only while the Processes view is open."""
import json
import os
from pathlib import Path
import pwd
import time


def parse_stat(raw, page_size):
    # comm may contain whitespace and parentheses; the final ')' terminates it.
    end = raw.rfind(')')
    if end < 0:
        raise ValueError('Invalid stat record')
    fields = raw[end + 2:].split()
    return {'pid': int(raw[:raw.index('(')].strip()),
            'name': raw[raw.index('(') + 1:end], 'state': fields[0],
            'ticks': int(fields[11]) + int(fields[12]),
            'start': fields[19], 'rss': max(0, int(fields[21])) * page_size}


def snapshot(proc=Path('/proc')):
    users = {}
    rows = []
    page_size = os.sysconf('SC_PAGE_SIZE')
    for entry in proc.iterdir():
        if not entry.name.isdigit():
            continue
        try:
            row = parse_stat((entry / 'stat').read_text(), page_size)
            uid = entry.stat().st_uid
            if uid not in users:
                try:
                    users[uid] = pwd.getpwuid(uid).pw_name
                except KeyError:
                    users[uid] = str(uid)
            row['user'] = users[uid]
            rows.append(row)
        except (OSError, ValueError, IndexError):
            # Process exit / hidepid / permission races are expected.
            continue
    return {'time': time.monotonic(), 'hz': os.sysconf('SC_CLK_TCK'), 'processes': rows}


if __name__ == '__main__':
    print(json.dumps(snapshot(), ensure_ascii=True, separators=(',', ':')))
