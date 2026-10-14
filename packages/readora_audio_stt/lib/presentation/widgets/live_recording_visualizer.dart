import 'package:flutter/material.dart';

class LiveRecordingVisualizer extends StatefulWidget {
  final bool isRecording;
  final Color waveColor;

  const LiveRecordingVisualizer({
    Key? key,
    required this.isRecording,
    this.waveColor = const Color(0xFFEF4444), // Pulse red
  }) : super(key: key);

  @override
  State<LiveRecordingVisualizer> createState() => _LiveRecordingVisualizerState();
}

class _LiveRecordingVisualizerState extends State<LiveRecordingVisualizer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    if (widget.isRecording) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant LiveRecordingVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isRecording && !oldWidget.isRecording) {
      _controller.repeat();
    } else if (!widget.isRecording && oldWidget.isRecording) {
      _controller.stop();
      _controller.reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isRecording) {
      return const SizedBox.shrink();
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(5, (index) {
            final shift = (index * 0.2);
            final wave = (1.0 + (0.8 * ((_controller.value + shift) % 1.0 - 0.5).abs() * 2));
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 2.5),
              width: 4,
              height: 24 * wave,
              decoration: BoxDecoration(
                color: widget.waveColor,
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }),
        );
      },
    );
  }
}
