#!/usr/bin/env python3
"""DMD instrumentation diagnostics; never performance-acceptance evidence."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
DRIVER_MAIN = '''void main(string[] args)
{
    enforce(args.length == 3);
    size_t iterations = args[2].to!size_t;
    auto cases = corpus!double();
    foreach (ref c; cases)
    {
        if (c.name != args[1]) continue;
        preflight(c);
        ulong sink;
        foreach (i; 0 .. iterations) sink = sink * 1_000_033UL + clipping(c, i);
        benchmarkSink = sink;
        writefln("profile_case,%s,%s,%s", c.name, iterations, benchmarkSink);
        return;
    }
    enforce(false, "unknown profile case");
}
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', default='dmd')
    parser.add_argument('--cpu', type=int, default=0)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    compiler = shutil.which(args.compiler)
    if not compiler:
        parser.error('DMD compiler not found')
    if not hasattr(os, 'sched_getaffinity') or args.cpu not in os.sched_getaffinity(0):
        parser.error('--cpu must be an allowed Linux CPU')
    os.sched_setaffinity(0, {args.cpu})
    def capture(command):
        return subprocess.check_output(command, cwd=ROOT, text=True)
    version = capture([compiler, '--version'])
    if 'DMD' not in version:
        parser.error('this instrumentation runner requires DMD')
    out = (args.output or ROOT / 'build' / ('clipping-profile-' +
        datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ'))).resolve()
    out.mkdir(parents=True, exist_ok=False)
    source = (ROOT / 'benchmarks/segment_polygon_bench.d').read_text()
    marker = 'void main(string[] args)'
    if source.count(marker) != 1:
        raise RuntimeError('benchmark main changed; inspect driver derivation')
    driver = out / 'segment_polygon_bench.d'
    driver.write_text(source[:source.index(marker)] + DRIVER_MAIN)
    (out / 'original_segment_polygon_bench.d').write_text(source)
    imports = capture(['python3', str(ROOT / 'tools/dub-import-paths.py'),
                       '--compiler=' + compiler]).splitlines()
    record = {'purpose': 'instrumentation-diagnostic', 'status': 'incomplete',
        'commit': capture(['git', 'rev-parse', 'HEAD']).strip(),
        'dirty': bool(capture(['git', 'status', '--porcelain', '--', 'source', 'benchmarks', 'tools'])),
        'compiler_version': version, 'cpu': args.cpu, 'commands': [],
        'original_benchmark_sha256': hashlib.sha256(source.encode()).hexdigest(),
        'driver_sha256': hashlib.sha256(driver.read_bytes()).hexdigest(),
        'limitations': ['Instrumentation changes code generation and runtime cost.',
            'Setup and two-direction semantic preflight are included in traces.',
            'Do not treat profiler ticks as nanoseconds or compare to GEOS latency.',
            'No power, turbo, frequency or background controls are imposed.']}
    def save():
        (out / 'metadata.json').write_text(json.dumps(record, indent=2) + '\n')
    def run(command, cwd, name):
        record['commands'].append(command)
        save()
        with (cwd / (name + '.stdout')).open('w') as stdout, (cwd / (name + '.stderr')).open('w') as stderr:
            subprocess.run(command, cwd=cwd, stdout=stdout, stderr=stderr, check=True)
    save()
    try:
        binary = out / 'profile'
        run([compiler, '-O', '-inline', '-release', '-boundscheck=safeonly', '-profile',
            '-i', *['-I' + p for p in imports], '-of=' + str(binary), str(driver)], out, 'build')
        for name, iterations in [('crossing', 1000), ('sparse-64', 1000), ('dense-64', 100)]:
            case = out / name
            case.mkdir()
            run([str(binary), name, str(iterations)], case, 'run')
            if not (case / 'trace.log').is_file():
                raise RuntimeError('DMD did not emit trace.log')
        record['status'] = 'passed'
    finally:
        save()
    print('Instrumentation record:', out)


if __name__ == '__main__':
    main()
