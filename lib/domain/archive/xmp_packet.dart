import 'package:folio/domain/editing/pdf_metadata.dart';

/// The XMP packet a PDF/A document carries in its catalogue `/Metadata`.
///
/// PDF/A identifies itself here and nowhere else: a file with every other
/// requirement met and no `pdfaid:part` is simply not PDF/A.
///
/// The packet must AGREE with `/Info`. A validator compares them field by
/// field, and a title in one place and not the other fails the document -
/// which is why this is built from the same metadata the writer writes.
String buildXmpPacket({
  required int part,
  required String conformance,
  PdfMetadata? metadata,
  String? producer,
  DateTime? at,
}) {
  final buffer = StringBuffer()
    ..writeln('<?xpacket begin="\u{FEFF}" id="W5M0MpCehiHzreSzNTczkc9d"?>')
    ..writeln('<x:xmpmeta xmlns:x="adobe:ns:meta/">')
    ..writeln(
      '  <rdf:RDF '
      'xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">',
    )
    ..writeln(
      '    <rdf:Description rdf:about="" '
      'xmlns:pdfaid="http://www.aiim.org/pdfa/ns/id/">',
    )
    ..writeln('      <pdfaid:part>$part</pdfaid:part>')
    ..writeln('      <pdfaid:conformance>$conformance</pdfaid:conformance>')
    ..writeln('    </rdf:Description>');

  final title = metadata?.title;
  final author = metadata?.author;
  final subject = metadata?.subject;

  if (title != null || author != null || subject != null) {
    buffer
      ..writeln(
        '    <rdf:Description rdf:about="" '
        'xmlns:dc="http://purl.org/dc/elements/1.1/">',
      )
      // dc:title and dc:description are language alternatives, dc:creator is
      // an ordered list. Writing any of them as a plain string is the most
      // common way a hand-built packet fails validation.
      ..write(
        title == null
            ? ''
            : '      <dc:title><rdf:Alt><rdf:li xml:lang="x-default">'
                  '${_escape(title)}</rdf:li></rdf:Alt></dc:title>\n',
      )
      ..write(
        author == null
            ? ''
            : '      <dc:creator><rdf:Seq><rdf:li>${_escape(author)}'
                  '</rdf:li></rdf:Seq></dc:creator>\n',
      )
      ..write(
        subject == null
            ? ''
            : '      <dc:description><rdf:Alt>'
                  '<rdf:li xml:lang="x-default">${_escape(subject)}'
                  '</rdf:li></rdf:Alt></dc:description>\n',
      )
      ..writeln('    </rdf:Description>');
  }

  final creator = metadata?.creator;
  final moment = at ?? DateTime(2026);

  buffer
    ..writeln(
      '    <rdf:Description rdf:about="" '
      'xmlns:xmp="http://ns.adobe.com/xap/1.0/">',
    )
    ..writeln('      <xmp:CreateDate>${xmpDate(moment)}</xmp:CreateDate>')
    ..writeln('      <xmp:ModifyDate>${xmpDate(moment)}</xmp:ModifyDate>')
    ..write(
      creator == null
          ? ''
          : '      <xmp:CreatorTool>${_escape(creator)}</xmp:CreatorTool>\n',
    )
    ..writeln('    </rdf:Description>');

  final keywords = metadata?.keywords;

  if (producer != null || keywords != null) {
    buffer
      ..writeln(
        '    <rdf:Description rdf:about="" '
        'xmlns:pdf="http://ns.adobe.com/pdf/1.3/">',
      )
      ..write(
        producer == null
            ? ''
            : '      <pdf:Producer>${_escape(producer)}</pdf:Producer>\n',
      )
      ..write(
        keywords == null
            ? ''
            : '      <pdf:Keywords>${_escape(keywords)}</pdf:Keywords>\n',
      )
      ..writeln('    </rdf:Description>');
  }

  buffer
    ..writeln('  </rdf:RDF>')
    ..writeln('</x:xmpmeta>')
    // The trailing padding is conventional: it leaves room for a tool to edit
    // the packet in place. 'w' means the packet may be written to.
    ..writeln('<?xpacket end="w"?>');

  return buffer.toString();
}

/// ISO 8601, which is what XMP dates are.
///
/// The offset is written as `+05:30` rather than `Z` unless the moment really
/// is UTC: a document created in Delhi and stamped Zulu is off by five and a
/// half hours forever.
String xmpDate(DateTime at) {
  final local = at.toLocal();
  final base =
      '${_pad(local.year, 4)}-${_pad(local.month, 2)}-${_pad(local.day, 2)}'
      'T${_pad(local.hour, 2)}:${_pad(local.minute, 2)}:'
      '${_pad(local.second, 2)}';

  final offset = local.timeZoneOffset;
  if (offset == Duration.zero) return '${base}Z';

  final sign = offset.isNegative ? '-' : '+';
  final minutes = offset.abs().inMinutes;
  return '$base$sign${_pad(minutes ~/ 60, 2)}:${_pad(minutes % 60, 2)}';
}

/// The same moment as a PDF `/Info` date, so the two agree.
String pdfDate(DateTime at) {
  final local = at.toLocal();
  final base =
      'D:${_pad(local.year, 4)}${_pad(local.month, 2)}${_pad(local.day, 2)}'
      '${_pad(local.hour, 2)}${_pad(local.minute, 2)}${_pad(local.second, 2)}';

  final offset = local.timeZoneOffset;
  if (offset == Duration.zero) return "${base}Z00'00'";

  final sign = offset.isNegative ? '-' : '+';
  final minutes = offset.abs().inMinutes;
  return "$base$sign${_pad(minutes ~/ 60, 2)}'${_pad(minutes % 60, 2)}'";
}

String _pad(int value, int width) => value.toString().padLeft(width, '0');

/// XML escaping. A title with an ampersand in it otherwise produces a packet
/// that is not XML, and a document that is not PDF/A.
String _escape(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
