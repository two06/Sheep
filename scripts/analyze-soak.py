#!/usr/bin/env python3
"""Validate local Sheep JSONL soak logs; no third-party packages or network."""
import json
import statistics
import sys
from pathlib import Path

failed = False
for name in sys.argv[1:]:
    path = Path(name)
    rows = [json.loads(line) for line in path.read_text().splitlines() if line.strip()]
    checks = {}
    checks['complete'] = bool(rows) and rows[-1]['elapsed'] >= 1835
    checks['no_runtime_errors'] = all(not r['error'] for r in rows)
    checks['stable_count'] = len({r['sheep'] for r in rows}) == 1
    checks['panels_match_entities'] = all(r['panels'] == r['sheep'] + r['effects'] for r in rows)
    checks['render_matches_simulation'] = all(r.get('maxPanelPositionError', float('inf')) <= 1 for r in rows)
    for phase, label in [(1, 'pause'), (2, 'hide')]:
        samples = [r for r in rows if r['soakPhase'] == phase]
        checks[f'{label}_stops_timers'] = len(samples) >= 2 and len({(r['ticks'], r['polls']) for r in samples}) == 1
        if phase == 2:
            checks['hide_removes_visible_panels'] = bool(samples) and all(r['visiblePanels'] == 0 for r in samples)
    warm = [r for r in rows if 60 <= r['elapsed'] < 360]
    tail = [r for r in rows if r['elapsed'] >= 1535]
    if warm and tail:
        growth = (statistics.median(r['residentBytes'] for r in tail) - statistics.median(r['residentBytes'] for r in warm)) / 2**20
        checks['memory_growth_below_20_MiB'] = growth < 20
    else:
        growth = None
        checks['memory_growth_below_20_MiB'] = False
    resumed = next((r for r in rows if r['soakPhase'] == 3), None)
    active_seconds = rows[-1]['elapsed'] - resumed['elapsed'] if resumed else 0
    checks['thirty_minutes_after_resume'] = active_seconds >= 1800
    active_samples = [r for r in rows if r['soakPhase'] == 3]
    checks['not_paused_after_resume'] = bool(active_samples) and all(not r['suspended'] for r in active_samples)
    checks['mostly_visible_after_resume'] = bool(active_samples) and sum(r['visiblePanels'] > 0 for r in active_samples) / len(active_samples) >= 0.95
    report = {
        'file': str(path), 'checks': checks,
        'elapsed_seconds': rows[-1]['elapsed'] if rows else 0,
        'median_memory_growth_MiB': growth,
        'peak_memory_MiB': max((r['residentBytes'] / 2**20 for r in rows), default=0),
        'peak_effects': max((r['effects'] for r in rows), default=0),
        'final_poll_mean_ms': rows[-1]['pollMeanMs'] if rows else None,
        'active_seconds_after_resume': active_seconds,
        'ticks_per_second_after_resume': (rows[-1]['ticks'] - resumed['ticks']) / active_seconds if active_seconds else None,
        'polls_per_second_after_resume': (rows[-1]['polls'] - resumed['polls']) / active_seconds if active_seconds else None,
    }
    print(json.dumps(report, indent=2))
    failed |= not all(checks.values())
if len(sys.argv) == 1:
    sys.exit('Usage: scripts/analyze-soak.py .build/validation/soak-*.jsonl')
sys.exit(1 if failed else 0)
