import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories.dart';

class RunnerScreen extends ConsumerStatefulWidget {
  final String planId;
  const RunnerScreen({super.key, required this.planId});

  @override
  ConsumerState<RunnerScreen> createState() => _RunnerScreenState();
}

class _RunnerScreenState extends ConsumerState<RunnerScreen> {
  Timer? _timer;
  int _index = 0;
  int _remainingSeconds = 0;
  bool _running = false;

  void _start(int seconds) {
    _timer?.cancel();
    setState(() {
      _running = true;
      _remainingSeconds = seconds;
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _remainingSeconds -= 1;
      });
      if (_remainingSeconds <= 0) {
        _timer?.cancel();
        setState(() => _running = false);
      }
    });
  }

  void _stop() {
    _timer?.cancel();
    setState(() => _running = false);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final plan = ref.read(plansRepoProvider).getById(widget.planId);
    if (plan == null || plan.items.isEmpty) {
      return const Scaffold(body: Center(child: Text('Plan not found or empty')));
    }

    final currentItem = plan.items[_index];
    final currentDrill = ref.read(drillsRepoProvider).getById(currentItem.drillId);
    final nextDrill = (_index + 1 < plan.items.length)
        ? ref.read(drillsRepoProvider).getById(plan.items[_index + 1].drillId)
        : null;

    final defaultSeconds = currentItem.minutes * 60;
    final remaining = _running ? _remainingSeconds : defaultSeconds;

    String mmss(int s) {
      final m = (s ~/ 60).toString().padLeft(2, '0');
      final r = (s % 60).toString().padLeft(2, '0');
      return '$m:$r';
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(plan.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.skip_next),
            onPressed: _index + 1 >= plan.items.length
                ? null
                : () {
                    _stop();
                    setState(() => _index += 1);
                  },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              currentDrill?.title ?? 'Unknown drill',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(currentDrill?.category ?? ''),
            const SizedBox(height: 16),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text(
                      mmss(remaining),
                      style: Theme.of(context).textTheme.displayMedium,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      children: [
                        FilledButton(
                          onPressed: _running ? null : () => _start(defaultSeconds),
                          child: const Text('Start'),
                        ),
                        FilledButton.tonal(
                          onPressed: !_running ? null : _stop,
                          child: const Text('Pause'),
                        ),
                        OutlinedButton(
                          onPressed: () {
                            if (!_running) return;
                            setState(() => _remainingSeconds += 120);
                          },
                          child: const Text('+2 min'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                children: [
                  _InfoCard(title: 'Setup', body: currentDrill?.setup ?? ''),
                  _InfoCard(title: 'Steps', body: currentDrill?.steps ?? ''),
                  _InfoCard(title: 'Coaching points', body: currentDrill?.coachingPoints ?? ''),
                ],
              ),
            ),

            if (nextDrill != null) ...[
              const SizedBox(height: 8),
              Text('Up next: ${nextDrill.title}', style: Theme.of(context).textTheme.titleMedium),
            ],

            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      // Skip
                      if (_index + 1 >= plan.items.length) {
                        Navigator.pop(context);
                        return;
                      }
                      _stop();
                      setState(() => _index += 1);
                    },
                    child: const Text('Skip'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      // Complete -> next or finish
                      if (_index + 1 >= plan.items.length) {
                        Navigator.pop(context);
                        return;
                      }
                      _stop();
                      setState(() => _index += 1);
                    },
                    child: Text(_index + 1 >= plan.items.length ? 'Finish' : 'Complete'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final String body;
  const _InfoCard({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(body.isEmpty ? '—' : body),
          ],
        ),
      ),
    );
  }
}
