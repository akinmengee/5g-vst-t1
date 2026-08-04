import 'package:flutter/material.dart';

/// Kartların ekrana sıralı ve yumuşak girişi: küçük bir gecikmenin ardından
/// fade + hafif yukarı kayma. Ana ekran kartlarında ve AI sonucu bölümlerinde
/// kullanılır — liste her açılışta "canlanır" hissi verir.
class Entrance extends StatefulWidget {
  final Widget child;
  final int delayMs;

  const Entrance({super.key, required this.child, this.delayMs = 0});

  @override
  State<Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<Entrance> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  late final CurvedAnimation _curve =
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);

  @override
  void initState() {
    super.initState();
    if (widget.delayMs == 0) {
      _controller.forward();
    } else {
      Future.delayed(Duration(milliseconds: widget.delayMs), () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _curve,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.05), end: Offset.zero)
            .animate(_curve),
        child: widget.child,
      ),
    );
  }
}
