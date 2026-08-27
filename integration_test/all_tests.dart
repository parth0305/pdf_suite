// Integration tests run against a real device, and the aggregate entrypoint
// keeps one app process alive across every suite. The runner's default 30s per
// test is a benchmark, not a pathology bound: a loop over six presets on a
// loaded emulator legitimately exceeds it. Five minutes means "something is
// genuinely wrong", which is the only thing a timeout should assert.
@Timeout(Duration(minutes: 5))
library;

// One entrypoint for every integration suite.
//
// `flutter test integration_test` treats each file as a separate Dart
// entrypoint, so it rebuilds, reinstalls and relaunches the app once per file.
// Running them through a single entrypoint installs once and keeps the app
// alive for the whole run.
//
// Each suite still gets its own group, so a failure names the file it came
// from. Run one file directly when you want it in isolation.
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'annotation_edit_flow_test.dart' as annotation_edit_flow;
import 'compression_flow_test.dart' as compression_flow;
import 'drawing_flow_test.dart' as drawing_flow;
import 'export_flow_test.dart' as export_flow;
import 'image_signature_flow_test.dart' as image_signature_flow;
import 'library_flow_test.dart' as library_flow;
import 'markup_flow_test.dart' as markup_flow;
import 'move_resize_flow_test.dart' as move_resize_flow;
import 'notes_stamps_flow_test.dart' as notes_stamps_flow;
import 'object_layer_flow_test.dart' as object_layer_flow;
import 'ocr_flow_test.dart' as ocr_flow;
import 'page_editor_test.dart' as page_editor;
import 'page_operations_flow_test.dart' as page_operations_flow;
import 'pages_mode_test.dart' as pages_mode;
import 'redaction_flow_test.dart' as redaction_flow;
import 'scanner_flow_test.dart' as scanner_flow;
import 'signature_flow_test.dart' as signature_flow;
import 'pdfrx_engine_test.dart' as pdfrx_engine;
import 'platform_handles_test.dart' as platform_handles;
import 'viewer_flow_test.dart' as viewer_flow;
import 'watermark_flow_test.dart' as watermark_flow;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('library_flow', library_flow.main);
  group('viewer_flow', viewer_flow.main);
  group('pdfrx_engine', pdfrx_engine.main);
  group('platform_handles', platform_handles.main);
  group('page_editor', page_editor.main);
  group('page_operations_flow', page_operations_flow.main);
  group('pages_mode', pages_mode.main);
  group('markup_flow', markup_flow.main);
  group('drawing_flow', drawing_flow.main);
  group('annotation_edit_flow', annotation_edit_flow.main);
  group('signature_flow', signature_flow.main);
  group('image_signature_flow', image_signature_flow.main);
  group('notes_stamps_flow', notes_stamps_flow.main);
  group('move_resize_flow', move_resize_flow.main);
  group('watermark_flow', watermark_flow.main);
  group('object_layer_flow', object_layer_flow.main);
  group('redaction_flow', redaction_flow.main);
  group('scanner_flow', scanner_flow.main);
  group('ocr_flow', ocr_flow.main);
  group('compression_flow', compression_flow.main);
  group('export_flow', export_flow.main);
}
