// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

import 'package:test/test.dart';

import 'package:build/build.dart';
import 'package:build_runner_core/src/generate/phase.dart';
import 'package:build_runner_core/src/generate/performance_tracker.dart';
import 'package:build_runner_core/src/util/clock.dart';
import 'package:build_test/build_test.dart';

main() {
  group('PerformanceTracker', () {
    DateTime time;
    final startTime = DateTime(2017);
    DateTime fakeClock() => time;

    BuildPerformanceTracker tracker;

    setUp(() {
      time = startTime;
      tracker = scopeClock(
        fakeClock,
        () => BuildPerformanceTracker()..start(),
      );
    });

    test('can track start/stop times and total duration', () {
      time = startTime.add(const Duration(seconds: 5));
      scopeClock(fakeClock, tracker.stop);
      expect(tracker.startTime, startTime);
      expect(tracker.stopTime, time);
      expect(tracker.duration, const Duration(seconds: 5));
    });

    test('can track multiple phases', () async {
      await scopeClock(fakeClock, () async {
        var packages = ['a', 'b', 'c'];
        var builder = TestBuilder();
        var phases = packages.map((p) => InBuildPhase(builder, p)).toList();

        for (var phase in phases) {
          var package = phase.package;
          await tracker.trackBuildPhase(phase, () async {
            time = time.add(const Duration(seconds: 5));
            return [AssetId(package, 'lib/$package.txt')];
          });
        }

        tracker.stop();
        expect(
            tracker.phases.map((p) => p.builderKeys),
            orderedEquals(
                phases.map((phase) => orderedEquals([phase.builderLabel]))));

        var times = tracker.phases.map((t) => t.stopTime).toList();
        var expectedTimes = [5000, 10000, 15000].map((millis) =>
            DateTime.fromMillisecondsSinceEpoch(
                millis + startTime.millisecondsSinceEpoch));
        expect(times, orderedEquals(expectedTimes));

        var total = tracker.phases.fold(
            Duration(), (Duration total, phase) => phase.duration + total);
        expect(total, const Duration(seconds: 15));
      });
    });

    test(
        'can track multiple actions and phases within them, and '
        'serialize/deserialize it', () async {
      var inputs = [
        makeAssetId('a|web/a.txt'),
        makeAssetId('a|web/b.txt'),
        makeAssetId('a|web/c.txt'),
      ];

      void checkMatchesExpected(BuildPerformance performance) {
        var allActions = performance.actions.toList();
        for (var i = 0; i < inputs.length; i++) {
          var action = allActions[i];
          expect(action.startTime, startTime.add(Duration(seconds: i * 3)));
          expect(
              action.stopTime, startTime.add(Duration(seconds: (i + 1) * 3)));
          var allPhases = action.phases.toList();
          for (var p = 0; p < 3; p++) {
            var phase = allPhases[p];
            expect(phase.duration, Duration(seconds: 1));
            expect(
                phase.startTime,
                startTime
                    .add(Duration(seconds: i * 3))
                    .add(Duration(seconds: p)));
            expect(
                phase.stopTime,
                startTime
                    .add(Duration(seconds: i * 3))
                    .add(Duration(seconds: p + 1)));
          }
        }

        var total = performance.actions.fold(
            Duration(), (Duration total, action) => action.duration + total);
        expect(total, Duration(seconds: inputs.length * 3));
      }

      await scopeClock(fakeClock, () async {
        for (var input in inputs) {
          var actionTracker = tracker.startBuilderAction(input, 'test_builder');
          await actionTracker.track(() async {
            time = time.add(const Duration(seconds: 1));
          }, 'Setup');
          await actionTracker.track(() async {
            time = time.add(const Duration(seconds: 1));
          }, 'Build');
          await actionTracker.track(() async {
            time = time.add(const Duration(seconds: 1));
          }, 'Finalize');
          actionTracker.stop();
        }
        tracker.stop();
      });

      checkMatchesExpected(tracker);

      checkMatchesExpected(BuildPerformance.fromJson(
          jsonDecode(jsonEncode(tracker.toJson())) as Map<String, dynamic>));
    });
  });
}
