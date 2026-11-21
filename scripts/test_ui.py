#!/usr/bin/env python3
"""Import generated assets, then run the Godot regressions sequentially."""
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
TESTS = (
    'postmortem_smoke', 'log_smoke', 'widget_smoke', 'scroll_smoke', 'menu_smoke', 'camera_smoke',
    'character_smoke', 'death_smoke', 'ui_smoke',
)


def check(arguments, label):
    try:
        result = subprocess.run(
            ['godot', '--headless', '--path', str(ROOT / 'godot'), *arguments],
            capture_output=True, text=True, timeout=120,
        )
    except subprocess.TimeoutExpired as error:
        print(f'{label} timed out', file=sys.stderr)
        for output in (error.stdout, error.stderr):
            if output:
                print(output.decode(errors='replace') if isinstance(output, bytes) else output)
        raise SystemExit(1)
    print(result.stdout, end='', flush=True)
    print(result.stderr, end='', file=sys.stderr, flush=True)
    if result.returncode or 'ERROR:' in result.stderr or 'SCRIPT ERROR' in result.stderr:
        raise SystemExit(f'{label} failed')
    return result.stdout


if __name__ == '__main__':
    # prepare() replaces generated data, including texture import sidecars.
    check(['--editor', '--import'], 'Asset import')
    for name in TESTS:
        print(f'Running {name}', flush=True)
        if 'passed' not in check(['--script', f'tests/{name}.gd'], name):
            raise SystemExit(f'{name} did not report completion')
    print('All Godot UI regressions passed.', flush=True)
