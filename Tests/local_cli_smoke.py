import pathlib, subprocess, sys, tempfile
exe = sys.argv[1]
def run(*args):
    return subprocess.run([exe, *args], capture_output=True, text=True)
help_result = run('--help')
assert help_result.returncode == 0
assert 'group-hints' in help_result.stdout
with tempfile.TemporaryDirectory() as tmp:
    root = pathlib.Path(tmp)
    output = root / 'hints.json'
    # Missing acknowledgement must fail before trying nonexistent paths or contacting runtime.
    args = ['group-hints', '--input', str(root/'one.png'), '--input', str(root/'two.png'),
            '--model', 'example-vision:local', '--output', str(output)]
    result = run(*args)
    assert result.returncode != 0 and 'acknowledgement' in result.stderr
    assert str(root) not in result.stderr and not output.exists()
    result = run(*(args + ['--acknowledge-runtime', 'user-confirmed', '--check-only', 'true']))
    assert result.returncode == 0, result.stderr
    assert not output.exists()
    for extra in [['--endpoint','https://example.org'], ['--acknowledge-runtime','false']]:
        assert run(*(args + extra)).returncode != 0
print('Local adapter CLI smoke passed (no runtime/image reads).')
