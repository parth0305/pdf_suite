import 'package:folio/domain/engine/pdf_types.dart';

/// What a field is, which decides both the control that edits it and the
/// appearance that gets drawn for it.
enum FormFieldKind {
  text,
  checkBox,
  radio,
  choice,

  /// Shown and left alone. A `/Sig` field promises a cryptographic signature,
  /// and half of one is worse than none.
  signature,

  /// Runs an action rather than holding a value. Nothing to fill.
  pushButton,
}

/// ISO 32000-1 Tables 221, 226, 228 and 230. Bit N is `1 << (N - 1)`, which is
/// the off-by-one every reading of this table has to survive.
const _readOnly = 1; // bit 1
const _required = 1 << 1; // bit 2
const _multiline = 1 << 12; // bit 13
const _password = 1 << 13; // bit 14
const _radio = 1 << 15; // bit 16
const _pushButton = 1 << 16; // bit 17
const _combo = 1 << 17; // bit 18

/// One drawn instance of a field.
///
/// A field and its widget are usually the same object and occasionally not: a
/// radio group is ONE field with one widget per button, and each widget has
/// its own rectangle and its own "on" state.
class FormWidget {
  const FormWidget({
    required this.objectNumber,
    required this.pageIndex,
    required this.rect,
    this.onState,
  });

  final int objectNumber;
  final int pageIndex;
  final TextRect rect;

  /// The `/AP /N` state that means "chosen", for buttons. The other state is
  /// always `/Off`.
  final String? onState;
}

/// A terminal field: one that holds a value rather than grouping others.
class FormField {
  const FormField({
    required this.name,
    required this.kind,
    required this.objectNumber,
    required this.widgets,
    this.value,
    this.options = const [],
    this.exports = const [],
    this.flags = 0,
    this.maxLength,
    this.defaultAppearance,
    this.ancestors = const [],
  });

  /// The fully qualified name: every ancestor's `/T` joined with full stops.
  /// This is what a form's own documentation calls the field.
  final String name;

  final FormFieldKind kind;

  /// The object that holds `/V`. For a radio group this is the PARENT, not
  /// any of the widgets - writing the value onto a widget leaves the group
  /// unset and the button unticked.
  final int objectNumber;

  final List<FormWidget> widgets;

  /// `/V`, as text. For buttons this is the chosen state's name.
  final String? value;

  /// `/Opt` for a choice field, or the available states for a radio group.
  ///
  /// These are the labels a person picks from.
  final List<String> options;

  /// What each of [options] is worth when written back.
  ///
  /// A choice field may pair an export value with a label - `[(IN) (India)]` -
  /// and the form's owner reads the export value. Writing the label back
  /// gives them `India` where their system expects `IN`.
  final List<String> exports;

  final int flags;

  /// `/MaxLen`, for text fields that declare one.
  final int? maxLength;

  /// `/DA`, the field's own default appearance string. Reused when drawing so
  /// a filled field matches the ones around it.
  final String? defaultAppearance;

  /// The field objects between this one and `/AcroForm /Fields`.
  ///
  /// `/Fields` lists the ROOTS of the tree, so deciding whether an entry there
  /// still has anything under it means knowing what is under it.
  final List<int> ancestors;

  bool get isReadOnly => flags & _readOnly != 0;
  bool get isRequired => flags & _required != 0;
  bool get isMultiline => kind == FormFieldKind.text && flags & _multiline != 0;
  bool get isPassword => kind == FormFieldKind.text && flags & _password != 0;
  bool get isCombo => kind == FormFieldKind.choice && flags & _combo != 0;

  /// Whether a value can be typed or chosen for this field at all.
  bool get isFillable =>
      !isReadOnly &&
      kind != FormFieldKind.signature &&
      kind != FormFieldKind.pushButton;
}

/// The kind a field of type [type] with flags [flags] actually is.
///
/// `/Btn` covers three unrelated controls. Treating them alike gives a
/// checkbox that cannot be ticked and a radio group where every button turns
/// on independently.
FormFieldKind kindOf(String? type, int flags) => switch (type) {
  'Btn' when flags & _pushButton != 0 => FormFieldKind.pushButton,
  'Btn' when flags & _radio != 0 => FormFieldKind.radio,
  'Btn' => FormFieldKind.checkBox,
  'Ch' => FormFieldKind.choice,
  'Sig' => FormFieldKind.signature,
  _ => FormFieldKind.text,
};
