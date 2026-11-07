import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// 宽屏（桌面、平板）上内容区的最大宽度，超出部分左右留白居中。
const maxContentWidth = 960.0;

/// 内容居中所需的左右边距：窄时是 [min]，宽时让内容不超过 [maxContentWidth]。
double sideInset(double width, [double min = 16]) =>
    math.max(min, (width - maxContentWidth) / 2);

/// 把可用宽度换算成左右边距交给 [builder]。用在 ListView 的 padding 上，
/// 这样内容居中，滚动条仍在窗口边缘。
class ContentInsets extends StatelessWidget {
  const ContentInsets({super.key, required this.builder, this.min = 16});

  final Widget Function(BuildContext context, double side) builder;
  final double min;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => builder(context, sideInset(box.maxWidth, min)),
  );
}

/// 内容宽度受限、居中的 ListView（页面主体用）。
class ContentListView extends StatelessWidget {
  const ContentListView({
    super.key,
    required this.children,
    this.top = 16,
    this.bottom = 16,
  });

  final List<Widget> children;
  final double top;
  final double bottom;

  @override
  Widget build(BuildContext context) => ContentInsets(
    builder: (context, side) => ListView(
      padding: EdgeInsets.fromLTRB(side, top, side, bottom),
      children: children,
    ),
  );
}
