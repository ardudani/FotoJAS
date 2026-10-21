import 'dart:async';

import 'package:flutter/material.dart';

import '../app_state.dart';

/// Botón grande y redondeado para la interfaz del cliente.
class BigButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool filled;
  final double scale;

  const BigButton({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.filled = true,
    this.scale = 1,
  });

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final enabled = onTap != null;
    final bg = filled ? accent : Colors.white.withValues(alpha: 0.12);
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(40 * scale),
        elevation: filled ? 6 : 0,
        shadowColor: accent.withValues(alpha: 0.5),
        child: InkWell(
          borderRadius: BorderRadius.circular(40 * scale),
          onTap: onTap,
          child: Container(
            constraints: BoxConstraints(minWidth: 200 * scale, minHeight: 72 * scale),
            padding: EdgeInsets.symmetric(horizontal: 32 * scale, vertical: 18 * scale),
            decoration: filled
                ? null
                : BoxDecoration(
                    borderRadius: BorderRadius.circular(40 * scale),
                    border: Border.all(color: Colors.white54, width: 2),
                  ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Colors.white, size: 30 * scale),
                SizedBox(width: 14 * scale),
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22 * scale,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Vuelve a la pantalla inicial tras un tiempo sin tocar la pantalla.
class IdleGuard extends StatefulWidget {
  final Widget child;
  final int? seconds;
  const IdleGuard({super.key, required this.child, this.seconds});

  @override
  State<IdleGuard> createState() => _IdleGuardState();
}

class _IdleGuardState extends State<IdleGuard> {
  Timer? _t;

  void _reset() {
    _t?.cancel();
    final secs = widget.seconds ?? App.settings.idleTimeout;
    _t = Timer(Duration(seconds: secs), () {
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    });
  }

  @override
  void initState() {
    super.initState();
    _reset();
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _reset(),
        child: widget.child,
      );
}

/// Pide el PIN de administrador. Devuelve true si es correcto.
Future<bool> askPin(BuildContext context) async {
  final ctrl = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('PIN de administrador'),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        obscureText: true,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(hintText: 'PIN'),
        onSubmitted: (_) => Navigator.pop(ctx, ctrl.text == App.settings.pin),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, ctrl.text == App.settings.pin),
          child: const Text('Entrar'),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Fondo oscuro con degradado usado en las pantallas del cliente.
class DarkBackdrop extends StatelessWidget {
  final Widget child;
  const DarkBackdrop({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Container(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, -0.4),
          radius: 1.3,
          colors: [Color.lerp(accent, Colors.black, 0.75)!, const Color(0xFF0B0B10)],
        ),
      ),
      child: child,
    );
  }
}

/// Imagen con sombra suave, para mostrar la foto final.
class PhotoCard extends StatelessWidget {
  final ImageProvider image;
  const PhotoCard({super.key, required this.image});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 30, offset: Offset(0, 12))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image(image: image, fit: BoxFit.contain, gaplessPlayback: true),
      ),
    );
  }
}
