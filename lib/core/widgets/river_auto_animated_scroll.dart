import 'package:auto_animated/auto_animated.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

typedef RiverAutoAnimatedItemTransitionBuilder =
    Widget Function(
      BuildContext context,
      int index,
      Animation<double> animation,
      Widget child,
    );

class RiverAutoAnimatedDefaults {
  RiverAutoAnimatedDefaults._();

  // Prevent long lists from appearing too slowly due to per-item stagger.
  static const int maxAnimatedItems = 32;
  static const int maxStaggeredItems = 8;

  static const LiveOptions options = LiveOptions(
    delay: Duration.zero,
    showItemInterval: Duration(milliseconds: 8),
    showItemDuration: Duration(milliseconds: 150),
    visibleFraction: 0.025,
    reAnimateOnVisibility: false,
  );

  static Widget transition(
    BuildContext context,
    int index,
    Animation<double> animation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
    );
    return FadeTransition(
      opacity: Tween<double>(begin: 0, end: 1).animate(curved),
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.02),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}

enum _RiverAnimatedListMode { children, builder, separated }

class RiverAutoAnimatedListView extends StatefulWidget {
  RiverAutoAnimatedListView({
    super.key,
    this.scrollDirection = Axis.vertical,
    this.reverse = false,
    this.controller,
    this.primary,
    this.physics,
    this.shrinkWrap = false,
    this.padding,
    this.itemExtent,
    this.prototypeItem,
    this.cacheExtent,
    this.semanticChildCount,
    this.dragStartBehavior = DragStartBehavior.start,
    this.keyboardDismissBehavior = ScrollViewKeyboardDismissBehavior.manual,
    this.restorationId,
    this.clipBehavior = Clip.hardEdge,
    this.hitTestBehavior = HitTestBehavior.opaque,
    this.options = RiverAutoAnimatedDefaults.options,
    this.transitionBuilder = RiverAutoAnimatedDefaults.transition,
    List<Widget> children = const <Widget>[],
  }) : _mode = _RiverAnimatedListMode.children,
       _children = children,
       _itemBuilder = null,
       _separatorBuilder = null,
       _itemCount = null,
       _addAutomaticKeepAlives = true,
       _addRepaintBoundaries = true,
       _addSemanticIndexes = true,
       _findChildIndexCallback = null;

  RiverAutoAnimatedListView.builder({
    super.key,
    this.scrollDirection = Axis.vertical,
    this.reverse = false,
    this.controller,
    this.primary,
    this.physics,
    this.shrinkWrap = false,
    this.padding,
    this.itemExtent,
    this.prototypeItem,
    this.cacheExtent,
    this.semanticChildCount,
    this.dragStartBehavior = DragStartBehavior.start,
    this.keyboardDismissBehavior = ScrollViewKeyboardDismissBehavior.manual,
    this.restorationId,
    this.clipBehavior = Clip.hardEdge,
    this.hitTestBehavior = HitTestBehavior.opaque,
    this.options = RiverAutoAnimatedDefaults.options,
    this.transitionBuilder = RiverAutoAnimatedDefaults.transition,
    required IndexedWidgetBuilder itemBuilder,
    int? itemCount,
    bool addAutomaticKeepAlives = true,
    bool addRepaintBoundaries = true,
    bool addSemanticIndexes = true,
    ChildIndexGetter? findChildIndexCallback,
  }) : _mode = _RiverAnimatedListMode.builder,
       _children = const <Widget>[],
       _itemBuilder = itemBuilder,
       _separatorBuilder = null,
       _itemCount = itemCount,
       _addAutomaticKeepAlives = addAutomaticKeepAlives,
       _addRepaintBoundaries = addRepaintBoundaries,
       _addSemanticIndexes = addSemanticIndexes,
       _findChildIndexCallback = findChildIndexCallback;

  RiverAutoAnimatedListView.separated({
    super.key,
    this.scrollDirection = Axis.vertical,
    this.reverse = false,
    this.controller,
    this.primary,
    this.physics,
    this.shrinkWrap = false,
    this.padding,
    this.itemExtent,
    this.prototypeItem,
    this.cacheExtent,
    required int itemCount,
    this.dragStartBehavior = DragStartBehavior.start,
    this.keyboardDismissBehavior = ScrollViewKeyboardDismissBehavior.manual,
    this.restorationId,
    this.clipBehavior = Clip.hardEdge,
    this.hitTestBehavior = HitTestBehavior.opaque,
    this.options = RiverAutoAnimatedDefaults.options,
    this.transitionBuilder = RiverAutoAnimatedDefaults.transition,
    required IndexedWidgetBuilder itemBuilder,
    required IndexedWidgetBuilder separatorBuilder,
    bool addAutomaticKeepAlives = true,
    bool addRepaintBoundaries = true,
    bool addSemanticIndexes = true,
  }) : _mode = _RiverAnimatedListMode.separated,
       _children = const <Widget>[],
       _itemBuilder = itemBuilder,
       _separatorBuilder = separatorBuilder,
       _itemCount = itemCount,
       _addAutomaticKeepAlives = addAutomaticKeepAlives,
       _addRepaintBoundaries = addRepaintBoundaries,
       _addSemanticIndexes = addSemanticIndexes,
       _findChildIndexCallback = null,
       semanticChildCount = itemCount;

  final _RiverAnimatedListMode _mode;
  final List<Widget> _children;
  final IndexedWidgetBuilder? _itemBuilder;
  final IndexedWidgetBuilder? _separatorBuilder;
  final int? _itemCount;
  final bool _addAutomaticKeepAlives;
  final bool _addRepaintBoundaries;
  final bool _addSemanticIndexes;
  final ChildIndexGetter? _findChildIndexCallback;

  final Axis scrollDirection;
  final bool reverse;
  final ScrollController? controller;
  final bool? primary;
  final ScrollPhysics? physics;
  final bool shrinkWrap;
  final EdgeInsetsGeometry? padding;
  final double? itemExtent;
  final Widget? prototypeItem;
  final double? cacheExtent;
  final int? semanticChildCount;
  final DragStartBehavior dragStartBehavior;
  final ScrollViewKeyboardDismissBehavior? keyboardDismissBehavior;
  final String? restorationId;
  final Clip clipBehavior;
  final HitTestBehavior hitTestBehavior;
  final LiveOptions options;
  final RiverAutoAnimatedItemTransitionBuilder transitionBuilder;

  @override
  State<RiverAutoAnimatedListView> createState() =>
      _RiverAutoAnimatedListViewState();
}

class _RiverAutoAnimatedListViewState extends State<RiverAutoAnimatedListView> {
  late final String _keyPrefix =
      'river_auto_list_${identityHashCode(this)}_${DateTime.now().microsecondsSinceEpoch}';

  Widget _wrapAnimatedItem({required int index, required Widget child}) {
    if (index >= RiverAutoAnimatedDefaults.maxAnimatedItems) {
      return child;
    }
    final staggerIndex = index > RiverAutoAnimatedDefaults.maxStaggeredItems
        ? RiverAutoAnimatedDefaults.maxStaggeredItems
        : index;
    final delay = Duration(
      microseconds:
          widget.options.delay.inMicroseconds +
          widget.options.showItemInterval.inMicroseconds * staggerIndex,
    );
    return AnimateIfVisible(
      key: ValueKey<String>('$_keyPrefix.$index'),
      delay: delay,
      duration: widget.options.showItemDuration,
      visibleFraction: widget.options.visibleFraction,
      reAnimateOnVisibility: widget.options.reAnimateOnVisibility,
      builder: (context, animation) =>
          widget.transitionBuilder(context, index, animation, child),
    );
  }

  Widget _buildListView() {
    switch (widget._mode) {
      case _RiverAnimatedListMode.children:
        final children = <Widget>[];
        for (var i = 0; i < widget._children.length; i++) {
          children.add(_wrapAnimatedItem(index: i, child: widget._children[i]));
        }
        return ListView(
          scrollDirection: widget.scrollDirection,
          reverse: widget.reverse,
          controller: widget.controller,
          primary: widget.primary,
          physics: widget.physics,
          shrinkWrap: widget.shrinkWrap,
          padding: widget.padding,
          itemExtent: widget.itemExtent,
          prototypeItem: widget.prototypeItem,
          cacheExtent: widget.cacheExtent,
          semanticChildCount: widget.semanticChildCount,
          dragStartBehavior: widget.dragStartBehavior,
          keyboardDismissBehavior:
              widget.keyboardDismissBehavior ??
              ScrollViewKeyboardDismissBehavior.manual,
          restorationId: widget.restorationId,
          clipBehavior: widget.clipBehavior,
          hitTestBehavior: widget.hitTestBehavior,
          children: children,
        );
      case _RiverAnimatedListMode.builder:
        return ListView.builder(
          scrollDirection: widget.scrollDirection,
          reverse: widget.reverse,
          controller: widget.controller,
          primary: widget.primary,
          physics: widget.physics,
          shrinkWrap: widget.shrinkWrap,
          padding: widget.padding,
          itemExtent: widget.itemExtent,
          prototypeItem: widget.prototypeItem,
          cacheExtent: widget.cacheExtent,
          semanticChildCount: widget.semanticChildCount,
          dragStartBehavior: widget.dragStartBehavior,
          keyboardDismissBehavior:
              widget.keyboardDismissBehavior ??
              ScrollViewKeyboardDismissBehavior.manual,
          restorationId: widget.restorationId,
          clipBehavior: widget.clipBehavior,
          hitTestBehavior: widget.hitTestBehavior,
          itemCount: widget._itemCount,
          findChildIndexCallback: widget._findChildIndexCallback,
          addAutomaticKeepAlives: widget._addAutomaticKeepAlives,
          addRepaintBoundaries: widget._addRepaintBoundaries,
          addSemanticIndexes: widget._addSemanticIndexes,
          itemBuilder: (context, index) {
            final child = widget._itemBuilder!(context, index);
            return _wrapAnimatedItem(index: index, child: child);
          },
        );
      case _RiverAnimatedListMode.separated:
        return ListView.separated(
          scrollDirection: widget.scrollDirection,
          reverse: widget.reverse,
          controller: widget.controller,
          primary: widget.primary,
          physics: widget.physics,
          shrinkWrap: widget.shrinkWrap,
          padding: widget.padding,
          cacheExtent: widget.cacheExtent,
          dragStartBehavior: widget.dragStartBehavior,
          keyboardDismissBehavior:
              widget.keyboardDismissBehavior ??
              ScrollViewKeyboardDismissBehavior.manual,
          restorationId: widget.restorationId,
          clipBehavior: widget.clipBehavior,
          hitTestBehavior: widget.hitTestBehavior,
          itemCount: widget._itemCount ?? 0,
          addAutomaticKeepAlives: widget._addAutomaticKeepAlives,
          addRepaintBoundaries: widget._addRepaintBoundaries,
          addSemanticIndexes: widget._addSemanticIndexes,
          itemBuilder: (context, index) {
            final child = widget._itemBuilder!(context, index);
            return _wrapAnimatedItem(index: index, child: child);
          },
          separatorBuilder: widget._separatorBuilder!,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimateIfVisibleWrapper(
      delay: widget.options.delay,
      showItemInterval: widget.options.showItemInterval,
      controller: widget.controller,
      child: _buildListView(),
    );
  }
}

enum _RiverAnimatedGridMode { builder, count }

class RiverAutoAnimatedGridView extends StatefulWidget {
  RiverAutoAnimatedGridView.builder({
    super.key,
    this.scrollDirection = Axis.vertical,
    this.reverse = false,
    this.controller,
    this.primary,
    this.physics,
    this.shrinkWrap = false,
    this.padding,
    this.cacheExtent,
    this.dragStartBehavior = DragStartBehavior.start,
    this.keyboardDismissBehavior = ScrollViewKeyboardDismissBehavior.manual,
    this.restorationId,
    this.clipBehavior = Clip.hardEdge,
    this.hitTestBehavior = HitTestBehavior.opaque,
    this.options = RiverAutoAnimatedDefaults.options,
    this.transitionBuilder = RiverAutoAnimatedDefaults.transition,
    required this.gridDelegate,
    required this.itemBuilder,
    this.itemCount,
  }) : _mode = _RiverAnimatedGridMode.builder,
       _children = const <Widget>[];

  RiverAutoAnimatedGridView.count({
    super.key,
    this.scrollDirection = Axis.vertical,
    this.reverse = false,
    this.controller,
    this.primary,
    this.physics,
    this.shrinkWrap = false,
    this.padding,
    this.cacheExtent,
    this.dragStartBehavior = DragStartBehavior.start,
    this.keyboardDismissBehavior = ScrollViewKeyboardDismissBehavior.manual,
    this.restorationId,
    this.clipBehavior = Clip.hardEdge,
    this.hitTestBehavior = HitTestBehavior.opaque,
    this.options = RiverAutoAnimatedDefaults.options,
    this.transitionBuilder = RiverAutoAnimatedDefaults.transition,
    required int crossAxisCount,
    double mainAxisSpacing = 0,
    double crossAxisSpacing = 0,
    double childAspectRatio = 1,
    double? mainAxisExtent,
    List<Widget> children = const <Widget>[],
  }) : _mode = _RiverAnimatedGridMode.count,
       _children = children,
       gridDelegate = SliverGridDelegateWithFixedCrossAxisCount(
         crossAxisCount: crossAxisCount,
         mainAxisSpacing: mainAxisSpacing,
         crossAxisSpacing: crossAxisSpacing,
         childAspectRatio: childAspectRatio,
         mainAxisExtent: mainAxisExtent,
       ),
       itemBuilder = _unusedBuilder,
       itemCount = children.length;

  static Widget _unusedBuilder(BuildContext context, int index) =>
      const SizedBox.shrink();

  final _RiverAnimatedGridMode _mode;
  final List<Widget> _children;
  final Axis scrollDirection;
  final bool reverse;
  final ScrollController? controller;
  final bool? primary;
  final ScrollPhysics? physics;
  final bool shrinkWrap;
  final EdgeInsetsGeometry? padding;
  final double? cacheExtent;
  final DragStartBehavior dragStartBehavior;
  final ScrollViewKeyboardDismissBehavior? keyboardDismissBehavior;
  final String? restorationId;
  final Clip clipBehavior;
  final HitTestBehavior hitTestBehavior;
  final LiveOptions options;
  final RiverAutoAnimatedItemTransitionBuilder transitionBuilder;
  final SliverGridDelegate gridDelegate;
  final IndexedWidgetBuilder itemBuilder;
  final int? itemCount;

  @override
  State<RiverAutoAnimatedGridView> createState() =>
      _RiverAutoAnimatedGridViewState();
}

class _RiverAutoAnimatedGridViewState extends State<RiverAutoAnimatedGridView> {
  late final String _keyPrefix =
      'river_auto_grid_${identityHashCode(this)}_${DateTime.now().microsecondsSinceEpoch}';

  Widget _wrapAnimatedItem({required int index, required Widget child}) {
    if (index >= RiverAutoAnimatedDefaults.maxAnimatedItems) {
      return child;
    }
    final staggerIndex = index > RiverAutoAnimatedDefaults.maxStaggeredItems
        ? RiverAutoAnimatedDefaults.maxStaggeredItems
        : index;
    final delay = Duration(
      microseconds:
          widget.options.delay.inMicroseconds +
          widget.options.showItemInterval.inMicroseconds * staggerIndex,
    );
    return AnimateIfVisible(
      key: ValueKey<String>('$_keyPrefix.$index'),
      delay: delay,
      duration: widget.options.showItemDuration,
      visibleFraction: widget.options.visibleFraction,
      reAnimateOnVisibility: widget.options.reAnimateOnVisibility,
      builder: (context, animation) =>
          widget.transitionBuilder(context, index, animation, child),
    );
  }

  Widget _buildGridView() {
    switch (widget._mode) {
      case _RiverAnimatedGridMode.builder:
        return GridView.builder(
          scrollDirection: widget.scrollDirection,
          reverse: widget.reverse,
          controller: widget.controller,
          primary: widget.primary,
          physics: widget.physics,
          shrinkWrap: widget.shrinkWrap,
          padding: widget.padding,
          cacheExtent: widget.cacheExtent,
          dragStartBehavior: widget.dragStartBehavior,
          keyboardDismissBehavior:
              widget.keyboardDismissBehavior ??
              ScrollViewKeyboardDismissBehavior.manual,
          restorationId: widget.restorationId,
          clipBehavior: widget.clipBehavior,
          hitTestBehavior: widget.hitTestBehavior,
          gridDelegate: widget.gridDelegate,
          itemCount: widget.itemCount,
          itemBuilder: (context, index) {
            final child = widget.itemBuilder(context, index);
            return _wrapAnimatedItem(index: index, child: child);
          },
        );
      case _RiverAnimatedGridMode.count:
        final children = <Widget>[];
        for (var i = 0; i < widget._children.length; i++) {
          children.add(_wrapAnimatedItem(index: i, child: widget._children[i]));
        }
        return GridView(
          scrollDirection: widget.scrollDirection,
          reverse: widget.reverse,
          controller: widget.controller,
          primary: widget.primary,
          physics: widget.physics,
          shrinkWrap: widget.shrinkWrap,
          padding: widget.padding,
          cacheExtent: widget.cacheExtent,
          dragStartBehavior: widget.dragStartBehavior,
          keyboardDismissBehavior:
              widget.keyboardDismissBehavior ??
              ScrollViewKeyboardDismissBehavior.manual,
          restorationId: widget.restorationId,
          clipBehavior: widget.clipBehavior,
          hitTestBehavior: widget.hitTestBehavior,
          gridDelegate: widget.gridDelegate,
          children: children,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimateIfVisibleWrapper(
      delay: widget.options.delay,
      showItemInterval: widget.options.showItemInterval,
      controller: widget.controller,
      child: _buildGridView(),
    );
  }
}

class RiverAutoAnimatedCustomScrollView extends StatelessWidget {
  const RiverAutoAnimatedCustomScrollView({
    super.key,
    this.scrollDirection = Axis.vertical,
    this.reverse = false,
    this.controller,
    this.primary,
    this.physics,
    this.shrinkWrap = false,
    this.center,
    this.anchor = 0.0,
    this.cacheExtent,
    this.semanticChildCount,
    this.dragStartBehavior = DragStartBehavior.start,
    this.keyboardDismissBehavior = ScrollViewKeyboardDismissBehavior.manual,
    this.restorationId,
    this.clipBehavior = Clip.hardEdge,
    this.hitTestBehavior = HitTestBehavior.opaque,
    this.options = RiverAutoAnimatedDefaults.options,
    this.slivers = const <Widget>[],
  });

  final Axis scrollDirection;
  final bool reverse;
  final ScrollController? controller;
  final bool? primary;
  final ScrollPhysics? physics;
  final bool shrinkWrap;
  final Key? center;
  final double anchor;
  final double? cacheExtent;
  final int? semanticChildCount;
  final DragStartBehavior dragStartBehavior;
  final ScrollViewKeyboardDismissBehavior? keyboardDismissBehavior;
  final String? restorationId;
  final Clip clipBehavior;
  final HitTestBehavior hitTestBehavior;
  final LiveOptions options;
  final List<Widget> slivers;

  @override
  Widget build(BuildContext context) {
    return AnimateIfVisibleWrapper(
      delay: options.delay,
      showItemInterval: options.showItemInterval,
      controller: controller,
      child: CustomScrollView(
        scrollDirection: scrollDirection,
        reverse: reverse,
        controller: controller,
        primary: primary,
        physics: physics,
        shrinkWrap: shrinkWrap,
        center: center,
        anchor: anchor,
        cacheExtent: cacheExtent,
        semanticChildCount: semanticChildCount,
        dragStartBehavior: dragStartBehavior,
        keyboardDismissBehavior:
            keyboardDismissBehavior ?? ScrollViewKeyboardDismissBehavior.manual,
        restorationId: restorationId,
        clipBehavior: clipBehavior,
        hitTestBehavior: hitTestBehavior,
        slivers: slivers,
      ),
    );
  }
}

class RiverAutoAnimatedSingleChildScrollView extends StatelessWidget {
  const RiverAutoAnimatedSingleChildScrollView({
    super.key,
    this.scrollDirection = Axis.vertical,
    this.reverse = false,
    this.padding,
    this.primary,
    this.physics,
    this.controller,
    this.dragStartBehavior = DragStartBehavior.start,
    this.clipBehavior = Clip.hardEdge,
    this.keyboardDismissBehavior = ScrollViewKeyboardDismissBehavior.manual,
    this.restorationId,
    this.options = RiverAutoAnimatedDefaults.options,
    this.transitionBuilder = RiverAutoAnimatedDefaults.transition,
    this.child,
  });

  final Axis scrollDirection;
  final bool reverse;
  final EdgeInsetsGeometry? padding;
  final bool? primary;
  final ScrollPhysics? physics;
  final ScrollController? controller;
  final DragStartBehavior dragStartBehavior;
  final Clip clipBehavior;
  final ScrollViewKeyboardDismissBehavior? keyboardDismissBehavior;
  final String? restorationId;
  final LiveOptions options;
  final RiverAutoAnimatedItemTransitionBuilder transitionBuilder;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final content = child == null
        ? const SizedBox.shrink()
        : AnimateIfVisible(
            key: ValueKey<String>(
              'river_auto_single_${identityHashCode(this)}',
            ),
            delay: options.delay,
            duration: options.showItemDuration,
            visibleFraction: options.visibleFraction,
            reAnimateOnVisibility: options.reAnimateOnVisibility,
            builder: (context, animation) =>
                transitionBuilder(context, 0, animation, child!),
          );
    return AnimateIfVisibleWrapper(
      delay: options.delay,
      showItemInterval: options.showItemInterval,
      controller: controller,
      child: SingleChildScrollView(
        scrollDirection: scrollDirection,
        reverse: reverse,
        padding: padding,
        primary: primary,
        physics: physics,
        controller: controller,
        dragStartBehavior: dragStartBehavior,
        clipBehavior: clipBehavior,
        keyboardDismissBehavior:
            keyboardDismissBehavior ?? ScrollViewKeyboardDismissBehavior.manual,
        restorationId: restorationId,
        child: content,
      ),
    );
  }
}
