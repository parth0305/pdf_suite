/// Layout width classes (spec section 7).
///
/// Layout decisions branch on these, never on `Platform.isX`. A Windows window
/// dragged narrow must behave like a phone.
enum WidthClass { compact, medium, expanded }

const double kMediumBreakpoint = 600;
const double kExpandedBreakpoint = 1024;

WidthClass widthClassFor(double width) {
  if (width < kMediumBreakpoint) return WidthClass.compact;
  if (width <= kExpandedBreakpoint) return WidthClass.medium;
  return WidthClass.expanded;
}
