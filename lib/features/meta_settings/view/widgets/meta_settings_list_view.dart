import 'package:aves/theme/durations.dart';
import 'package:aves/widgets/common/extensions/media_query.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// Fork-owned copy of the upstream settings list container (dense subtitle font
/// plus the staggered entrance animation), so the v2 surface matches v1.
class MetaSettingsListView extends StatelessWidget {
  final List<Widget> children;

  const new({
    super.key,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        textTheme: theme.textTheme.copyWith(
          // dense style font for tile subtitles, without modifying title font
          bodyMedium: const TextStyle(fontSize: 12),
        ),
      ),
      child: Selector<MediaQueryData, double>(
        selector: (context, mq) => mq.safeBottomPadding,
        builder: (context, safeBottomPadding, child) {
          final durations = context.watch<DurationsData>();
          return ListView(
            padding: const EdgeInsets.all(8) + EdgeInsets.only(bottom: safeBottomPadding),
            children: AnimationConfiguration.toStaggeredList(
              duration: durations.staggeredAnimation,
              delay: durations.staggeredAnimationDelay * timeDilation,
              childAnimationBuilder: (child) => SlideAnimation(
                verticalOffset: 50.0,
                child: FadeInAnimation(
                  child: child,
                ),
              ),
              children: children,
            ),
          );
        },
      ),
    );
  }
}
