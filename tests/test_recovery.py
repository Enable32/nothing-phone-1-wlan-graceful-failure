#!/usr/bin/env python3
"""Host-side behavioural tests; Android/Binder/hardware are replaced at IO boundaries.

These tests exercise the shipped shell control flow and actual text parsers.
They do not simulate the WLAN driver, prove a device boot or test real radio resets.
"""
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
MODULE = ROOT / 'module'
SELF = Path(__file__).resolve()


def fake_android(state_path, timeout_seconds, args):
    path = Path(state_path)
    state = json.loads(path.read_text())
    scenario = state['scenario']
    latency = 6 if scenario == 'slow' else 0
    state['clock'] += min(latency, timeout_seconds)
    state['calls'].append(args)
    code = 0
    output = ''
    command = args[2] if len(args) > 2 else ''
    if latency >= timeout_seconds:
        code, output = 124, 'timeout'
    elif args[:2] != ['cmd', 'wifi']:
        raise AssertionError(('unexpected command', args))
    elif command == 'help':
        output = '\n'.join('  ' + n for n in [
            'status', 'start-scan', 'list-scan-results', 'set-wifi-enabled enabled|disabled'
        ] + ([] if scenario == 'unsupported' else ['trigger-recovery']))
    elif command == 'status':
        if scenario == 'binder' or (scenario == 'binder_after' and state['attempts']):
            output = 'cmd: Failure calling service wifi: FAILED_TRANSACTION'
        elif scenario == 'unknown_status':
            output = 'Unrecognized status format'
        else:
            enabled = scenario != 'disabled' or state.get('enable_requested', False)
            output = 'Wifi is ' + ('enabled' if enabled else 'disabled')
            if scenario == 'connected' and state['attempts'] and state['clock'] >= state['trigger'] + 7:
                output += '\nWifi is connected to "Test AP"'
    elif command == 'set-wifi-enabled':
        assert args == ['cmd', 'wifi', 'set-wifi-enabled', 'enabled']
        state['enable_requested'] = True
    elif command == 'trigger-recovery':
        state['attempts'] += 1
        state['trigger'] = state['clock']
        if scenario == 'trigger_error':
            output = 'Error: recovery refused'
    elif command == 'start-scan':
        state['scan_requested'] = state['clock']
    elif command == 'list-scan-results':
        fresh = scenario == 'initial_fresh' or (
            scenario in ['after_two', 'disabled'] and state['attempts'] >= 2)
        timestamp = state.get('trigger', state['scan_requested']) + 7 if state['attempts'] else 1
        age = state['clock'] - timestamp if fresh else 100 + state['clock']
        output = ' BSSID Frequency RSSI Age(sec) SSID Flags\n'
        output += f' 02:11:22:33:44:55 2412 -55(0:-56/1:-54) {age:.3f} Test AP [ESS]'
    else:
        raise AssertionError(('unexpected command', args))
    path.write_text(json.dumps(state))
    print(output)
    return code


class RecoveryTests(unittest.TestCase):
    def run_recovery(self, scenario):
        with tempfile.TemporaryDirectory() as d:
            temp = Path(d)
            state = temp / 'state.json'
            state.write_text(json.dumps(dict(scenario=scenario, clock=0, attempts=0, calls=[])))
            private = temp / 'private'
            private.mkdir()
            if scenario == 'locked':
                (private / 'wifi_recovery.lock').mkdir()
                (private / 'wifi_recovery.lock/pid').write_text('12345\n')
            runner = f'''
MODDIR={shlex.quote(str(MODULE))}
LOGROOT={shlex.quote(str(private))}
RU=0
. "$MODDIR/lib/wifi_recovery.sh"
REC_LOGROOT={shlex.quote(str(temp / 'public'))}
STATE={shlex.quote(str(state))}
SELF={shlex.quote(str(SELF))}
id() {{ [ "$1" != -u ] || {{ [ {shlex.quote(scenario)} != no_root ] && echo 0 || echo 1000; }}; }}
getprop() {{
    case "$1" in
      ro.build.version.incremental) echo 2509261631 ;;
      ro.product.device|ro.product.vendor.device) echo Spacewar ;;
      sys.boot_completed) echo 1 ;;
    esac
}}
uname() {{ echo 5.4.274-qgki-g4670d6bdb795; }}
cat() {{
    case "$1" in
      /sys/bus/msm_subsys/devices/*/name) echo wpss ;;
      /sys/bus/msm_subsys/devices/*/restart_level)
        python3 -c 'import json,sys; s=json.load(open(sys.argv[1])); print("SYSTEM" if s["scenario"]=="bad_policy" or (s["scenario"]=="policy_changed" and s["attempts"]) else "RELATED")' "$STATE" ;;
      *) command cat "$@" ;;
    esac
}}
od() {{ [ {shlex.quote(scenario)} != bad_driver ] && echo 'e2 38 86 11 ed d9 fe 47' || echo '00 00'; }}
ip() {{ echo '<BROADCAST,UP,LOWER_UP>'; }}
rec_clock() {{
    REC_NOW=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["clock"])' "$STATE")
    REC_SECOND=${{REC_NOW%%.*}}
}}
sleep() {{
    python3 -c 'import json,sys; p=sys.argv[1]; s=json.load(open(p)); s["clock"]+=float(sys.argv[2]); open(p,"w").write(json.dumps(s))' "$STATE" "$1"
}}
keys_poll() {{
    KEY_EVENT=
    K=$(python3 -c 'import json,sys; s=json.load(open(sys.argv[1])); print("lost" if s["scenario"]=="keys_lost" else "cancel" if s["scenario"]=="cancel" and s["attempts"] else "none")' "$STATE")
    case "$K" in lost) return 2 ;; cancel) KEY_EVENT=DOWN; return 0 ;; *) return 1 ;; esac
}}
timeout() {{
    shift
    shift
    LIMIT=$1
    shift
    python3 "$SELF" --fake "$STATE" "$LIMIT" "$@"
}}
recover_wifi
RC=$?
echo "FINAL_OUTCOME=$REC_OUTCOME FINAL_RC=$RC"
exit 0
'''
            result = subprocess.run(['sh'], input=runner, text=True, capture_output=True, timeout=35)
            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            data = json.loads(state.read_text())
            data['stdout'] = result.stdout
            data['stderr'] = result.stderr
            data['logs'] = [p.read_text() for p in (temp / 'public').glob('*.txt')]
            if scenario != 'locked':
                self.assertFalse((private / 'wifi_recovery.lock').exists(), result.stdout)
            else:
                self.assertEqual((private / 'wifi_recovery.lock/pid').read_text(), '12345\n')
            self.assertFalse(list(private.glob('wifi_recovery.*.*')))
            for call in data['calls']:
                self.assertEqual(call[:2], ['cmd', 'wifi'])
                self.assertIn(call[2], ['help', 'status', 'set-wifi-enabled',
                                        'start-scan', 'list-scan-results', 'trigger-recovery'])
            return data

    def test_initial_fresh_scan_needs_no_restart(self):
        s = self.run_recovery('initial_fresh')
        self.assertEqual(s['attempts'], 0)
        self.assertIn('FINAL_OUTCOME=fresh_networks FINAL_RC=0', s['stdout'])

    def test_stop_after_second_attempt(self):
        s = self.run_recovery('after_two')
        self.assertEqual(s['attempts'], 2)
        self.assertIn('FINAL_OUTCOME=fresh_networks FINAL_RC=0', s['stdout'])

    def test_connected_stops_first_attempt(self):
        s = self.run_recovery('connected')
        self.assertEqual(s['attempts'], 1)
        self.assertIn('FINAL_OUTCOME=connected FINAL_RC=0', s['stdout'])

    def test_cached_scan_and_enabled_switch_do_not_succeed(self):
        s = self.run_recovery('stale')
        self.assertEqual(s['attempts'], 3)
        self.assertIn('FINAL_OUTCOME=attempt_limit FINAL_RC=1', s['stdout'])
        self.assertLessEqual(s['clock'], 180)

    def test_disabled_wifi_is_only_enabled_never_disabled(self):
        s = self.run_recovery('disabled')
        self.assertIn(['cmd', 'wifi', 'set-wifi-enabled', 'enabled'], s['calls'])
        self.assertEqual(s['attempts'], 2)
        self.assertIn('FINAL_RC=0', s['stdout'])

    def test_volume_down_cancels_further_restarts(self):
        s = self.run_recovery('cancel')
        self.assertEqual(s['attempts'], 1)
        self.assertIn('FINAL_OUTCOME=cancelled FINAL_RC=1', s['stdout'])

    def test_unsupported_api_has_no_restart(self):
        s = self.run_recovery('unsupported')
        self.assertEqual(s['attempts'], 0)
        self.assertIn('unsupported_wifi_commands', s['stdout'])

    def test_zero_exit_binder_error_is_failure(self):
        s = self.run_recovery('binder')
        self.assertEqual(s['attempts'], 0)
        self.assertIn('command_failed', s['stdout'])

    def test_binder_failure_during_retry_stops(self):
        s = self.run_recovery('binder_after')
        self.assertEqual(s['attempts'], 1)
        self.assertIn('command_failed', s['stdout'])

    def test_zero_exit_recovery_error_stops(self):
        s = self.run_recovery('trigger_error')
        self.assertEqual(s['attempts'], 1)
        self.assertIn('command_failed', s['stdout'])

    def test_policy_change_stops_retry(self):
        s = self.run_recovery('policy_changed')
        self.assertEqual(s['attempts'], 1)
        self.assertIn('policy_not_related', s['stdout'])

    def test_preflight_and_status_rejections(self):
        for scenario, outcome in [('no_root', 'root_required'), ('bad_policy', 'policy_not_related'),
                                  ('bad_driver', 'early_v13_required'), ('unknown_status', 'unsupported_status_format'),
                                  ('keys_lost', 'key_reader_lost')]:
            with self.subTest(scenario=scenario):
                s = self.run_recovery(scenario)
                self.assertEqual(s['attempts'], 0)
                self.assertIn(outcome, s['stdout'])

    def test_total_time_and_command_timeout_bound_slow_calls(self):
        s = self.run_recovery('slow')
        self.assertLessEqual(s['clock'], 180)
        self.assertLessEqual(s['attempts'], 3)
        self.assertIn('FINAL_RC=1', s['stdout'])

    def test_parallel_run_does_not_steal_lock(self):
        s = self.run_recovery('locked')
        self.assertEqual(s['attempts'], 0)
        self.assertFalse(s['calls'])
        self.assertIn('second run was cancelled', s['stdout'])


class ParserAndMenuTests(unittest.TestCase):
    def parse_scan(self, rows, window):
        r = subprocess.run(['awk', '-v', f'window={window}', '-f', str(MODULE/'lib/fresh_scans.awk')],
                           input=rows, text=True, capture_output=True, check=True)
        return int(r.stdout)

    def test_scan_age_format_radio_chains_and_cache(self):
        rows = ''' BSSID Frequency RSSI Age(sec) SSID Flags
02:11:22:33:44:55 2412 -51 0.500 AP [ESS]
02:11:22:33:44:56 2412 -9(0: -9/1: -8) 0,900 AP [ESS]
02:11:22:33:44:57 2412 -55 12.100 Old [ESS]
02:11:22:33:44:58 2412 -55 ___?___ 0.000 [ESS]
02:11:22:33:44:59 2412 -55 >1000.0 0.000 [ESS]
invalid 2412 -55 0.000 Broken [ESS]
'''
        self.assertEqual(self.parse_scan(rows, 2), 2)
        self.assertEqual(self.parse_scan(rows, 0.1), 0)
        self.assertEqual(self.parse_scan('No scan results\n', 10), 0)
        self.assertEqual(self.parse_scan('02:11:22:33:44:55 2412 -50 6.000 Cached [ESS]', 20), 0)

    def test_key_parser_only_counts_press_events(self):
        rows = '''/dev/input/event3: EV_KEY KEY_VOLUMEUP DOWN
/dev/input/event3: EV_KEY KEY_VOLUMEUP REPEAT
/dev/input/event3: EV_KEY KEY_VOLUMEUP UP
/dev/input/event3: EV_KEY KEY_VOLUMEDOWN DOWN
/dev/input/event3: 0001 0073 00000001
/dev/input/event3: 0001 0072 00000002
/dev/input/event3: 0001 0072 00000000
/dev/input/event3: 0001 0072 00000001
/dev/input/event3: EV_KEY KEY_POWER DOWN
'''
        r = subprocess.run(['sh',str(MODULE/'lib/volume_filter.sh')], input=rows,
                           text=True, capture_output=True, check=True)
        self.assertEqual(r.stdout.splitlines(), ['UP','DOWN','UP','DOWN'])

    def test_number_navigation_wrap_exit_and_timeout(self):
        for sequence, selected, code in [('UP UP DOWN', 3, 0), ('UP UP UP UP DOWN',5,0),
                                          ('UP UP UP UP UP DOWN',1,0), ('',1,3)]:
            with self.subTest(sequence=sequence):
                script=f'''
RU=0
. {shlex.quote(str(MODULE/'lib/action_menu.sh'))}
set -- {sequence}
N=0
key_clock() {{ N=$((N+1)); KEY_CLOCK=$N; }}
keys_poll() {{ KEY_EVENT=${{1:-}}; [ "$#" -gt 0 ] || return 1; return 0; }}
# Preserve the queue outside function positional arguments.
QUEUE="{sequence}"
keys_poll() {{
    set -- $QUEUE
    KEY_EVENT=${{1:-}}
    [ "$#" -gt 0 ] || return 1
    shift
    QUEUE="$*"
    return 0
}}
sleep() {{ :; }}
choose_action
RC=$?
echo "SELECTION=$ACTION_SELECTED CODE=$RC"
'''
                r=subprocess.run(['sh'],input=script,text=True,capture_output=True,timeout=4,check=True)
                self.assertIn(f'SELECTION={selected} CODE={code}',r.stdout)

    def test_key_reader_cleanup(self):
        with tempfile.TemporaryDirectory() as d:
            temp=Path(d)
            binary=temp/'getevent'
            binary.write_text('#!/bin/sh\necho "event: EV_KEY KEY_VOLUMEUP DOWN"\nexec sleep 20\n')
            binary.chmod(0o755)
            script=f'''
MODDIR={shlex.quote(str(MODULE))}
LOGROOT={shlex.quote(str(temp/'private'))}
. "$MODDIR/lib/volume_keys.sh"
keys_start || exit 3
READER=$KEY_READER_PID
FILTER=$KEY_FILTER_PID
N=0
while [ "$N" -lt 25 ]; do
    keys_poll && break
    sleep 0.02
    N=$((N+1))
done
[ "$KEY_EVENT" = UP ] || exit 4
keys_stop
kill -0 "$READER" 2>/dev/null && exit 5
kill -0 "$FILTER" 2>/dev/null && exit 6
exit 0
'''
            env=dict(os.environ,PATH=str(temp)+':'+os.environ['PATH'])
            r=subprocess.run(['sh'],input=script,text=True,capture_output=True,timeout=5,env=env)
            self.assertEqual(r.returncode,0,r.stderr)
            self.assertFalse(list((temp/'private').iterdir()))


if __name__=='__main__':
    if len(sys.argv)>1 and sys.argv[1]=='--fake':
        raise SystemExit(fake_android(sys.argv[2],int(sys.argv[3]),sys.argv[4:]))
    unittest.main(verbosity=2)
