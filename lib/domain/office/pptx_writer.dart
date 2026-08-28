import 'dart:convert';
import 'dart:typed_data';

import 'package:folio/domain/office/docx_writer.dart' show OfficePage;
import 'package:folio/domain/office/ooxml.dart';
import 'package:folio/domain/office/zip_writer.dart';

/// English Metric Units per point: PowerPoint measures in 914400ths of an
/// inch, and there are 72 points to the inch.
const _emuPerPoint = 12700;

/// A presentation with one slide per page.
///
/// The weakest of the three conversions, and deliberately modest because of
/// it: each slide carries the page's text in a single box. Anything resembling
/// the original design is not attempted, because a PDF does not record one.
Uint8List writePptx(List<OfficePage> pages) {
  final size = pages.isEmpty
      ? (width: 595.0, height: 842.0)
      : (width: pages.first.size.width, height: pages.first.size.height);

  final slideIds = StringBuffer();
  final presentationRels = StringBuffer(
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org'
    '/officeDocument/2006/relationships/slideMaster" '
    'Target="slideMasters/slideMaster1.xml"/>',
  );
  final overrides = StringBuffer();
  final parts = <ZipEntry>[];

  for (var i = 0; i < pages.length; i++) {
    final number = i + 1;
    // Slide identifiers must be at least 256; anything below is reserved.
    slideIds.write('<p:sldId id="${255 + number}" r:id="rId${number + 1}"/>');
    presentationRels.write(
      '<Relationship Id="rId${number + 1}" '
      'Type="http://schemas.openxmlformats.org/officeDocument/2006'
      '/relationships/slide" Target="slides/slide$number.xml"/>',
    );
    overrides.write(
      '<Override PartName="/ppt/slides/slide$number.xml" '
      'ContentType="application/vnd.openxmlformats-officedocument'
      '.presentationml.slide+xml"/>',
    );

    parts
      ..add(
        ZipEntry(
          name: 'ppt/slides/slide$number.xml',
          bytes: utf8.encode(_slide(pages[i], size)),
        ),
      )
      ..add(
        ZipEntry(
          name: 'ppt/slides/_rels/slide$number.xml.rels',
          bytes: utf8.encode(
            '$xmlHeader'
            '<Relationships xmlns="http://schemas.openxmlformats.org'
            '/package/2006/relationships">'
            '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org'
            '/officeDocument/2006/relationships/slideLayout" '
            'Target="../slideLayouts/slideLayout1.xml"/>'
            '</Relationships>',
          ),
        ),
      );
  }

  return writeZip([
    ZipEntry(
      name: '[Content_Types].xml',
      bytes: utf8.encode(
        '$xmlHeader'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006'
        '/content-types">'
        '<Default Extension="rels" ContentType="application/vnd'
        '.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/ppt/presentation.xml" ContentType="application'
        '/vnd.openxmlformats-officedocument.presentationml.presentation'
        '.main+xml"/>'
        '<Override PartName="/ppt/slideMasters/slideMaster1.xml" '
        'ContentType="application/vnd.openxmlformats-officedocument'
        '.presentationml.slideMaster+xml"/>'
        '<Override PartName="/ppt/slideLayouts/slideLayout1.xml" '
        'ContentType="application/vnd.openxmlformats-officedocument'
        '.presentationml.slideLayout+xml"/>'
        '<Override PartName="/ppt/theme/theme1.xml" ContentType="application'
        '/vnd.openxmlformats-officedocument.theme+xml"/>'
        '$overrides</Types>',
      ),
    ),
    ZipEntry(
      name: '_rels/.rels',
      bytes: utf8.encode(
        packageRelationships('officeDocument', 'ppt/presentation.xml'),
      ),
    ),
    ZipEntry(
      name: 'ppt/presentation.xml',
      bytes: utf8.encode(
        '$xmlHeader'
        '<p:presentation xmlns:a="http://schemas.openxmlformats.org'
        '/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org'
        '/officeDocument/2006/relationships" '
        'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">'
        '<p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/>'
        '</p:sldMasterIdLst>'
        '<p:sldIdLst>$slideIds</p:sldIdLst>'
        '<p:sldSz cx="${(size.width * _emuPerPoint).round()}" '
        'cy="${(size.height * _emuPerPoint).round()}"/>'
        '<p:notesSz cx="${(size.width * _emuPerPoint).round()}" '
        'cy="${(size.height * _emuPerPoint).round()}"/>'
        '</p:presentation>',
      ),
    ),
    ZipEntry(
      name: 'ppt/_rels/presentation.xml.rels',
      bytes: utf8.encode(
        '$xmlHeader'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006'
        '/relationships">$presentationRels</Relationships>',
      ),
    ),
    ZipEntry(
      name: 'ppt/slideMasters/slideMaster1.xml',
      bytes: utf8.encode(_slideMaster()),
    ),
    ZipEntry(
      name: 'ppt/slideMasters/_rels/slideMaster1.xml.rels',
      bytes: utf8.encode(
        '$xmlHeader'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006'
        '/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org'
        '/officeDocument/2006/relationships/slideLayout" '
        'Target="../slideLayouts/slideLayout1.xml"/>'
        '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org'
        '/officeDocument/2006/relationships/theme" '
        'Target="../theme/theme1.xml"/>'
        '</Relationships>',
      ),
    ),
    ZipEntry(
      name: 'ppt/slideLayouts/slideLayout1.xml',
      bytes: utf8.encode(_slideLayout()),
    ),
    ZipEntry(
      name: 'ppt/slideLayouts/_rels/slideLayout1.xml.rels',
      bytes: utf8.encode(
        '$xmlHeader'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006'
        '/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org'
        '/officeDocument/2006/relationships/slideMaster" '
        'Target="../slideMasters/slideMaster1.xml"/>'
        '</Relationships>',
      ),
    ),
    ZipEntry(name: 'ppt/theme/theme1.xml', bytes: utf8.encode(_theme())),
    ...parts,
  ]);
}

/// One slide: a text box holding the page's paragraphs.
String _slide(OfficePage page, ({double width, double height}) size) {
  final body = StringBuffer();

  for (final paragraph in page.paragraphs) {
    body.write(
      '<a:p><a:r><a:rPr lang="en" dirty="0"/><a:t>'
      '${escapeXml(paragraph.text)}</a:t></a:r></a:p>',
    );
  }
  // A slide with no text still needs one paragraph, or PowerPoint reports the
  // shape as damaged rather than empty.
  if (page.paragraphs.isEmpty) body.write('<a:p/>');

  final margin = 36 * _emuPerPoint;

  return '$xmlHeader'
      '<p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006'
      '/relationships" xmlns:p="http://schemas.openxmlformats.org'
      '/presentationml/2006/main">'
      '<p:cSld><p:spTree>'
      '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/>'
      '</p:nvGrpSpPr>'
      '<p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/>'
      '<a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>'
      '<p:sp>'
      '<p:nvSpPr><p:cNvPr id="2" name="Text"/>'
      '<p:cNvSpPr txBox="1"/><p:nvPr/></p:nvSpPr>'
      '<p:spPr><a:xfrm><a:off x="$margin" y="$margin"/>'
      '<a:ext cx="${(size.width * _emuPerPoint).round() - margin * 2}" '
      'cy="${(size.height * _emuPerPoint).round() - margin * 2}"/></a:xfrm>'
      '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr>'
      '<p:txBody><a:bodyPr wrap="square"><a:normAutofit/></a:bodyPr>'
      '<a:lstStyle/>$body</p:txBody>'
      '</p:sp>'
      '</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>'
      '</p:sld>';
}

String _slideMaster() =>
    '$xmlHeader'
    '<p:sldMaster xmlns:a="http://schemas.openxmlformats.org/drawingml/2006'
    '/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006'
    '/relationships" xmlns:p="http://schemas.openxmlformats.org'
    '/presentationml/2006/main">'
    '<p:cSld><p:spTree>'
    '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/>'
    '</p:nvGrpSpPr>'
    '<p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/>'
    '<a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>'
    '</p:spTree></p:cSld>'
    '<p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" '
    'accent2="accent2" accent3="accent3" accent4="accent4" '
    'accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/>'
    '<p:sldLayoutIdLst><p:sldLayoutId id="2147483649" r:id="rId1"/>'
    '</p:sldLayoutIdLst>'
    '</p:sldMaster>';

String _slideLayout() =>
    '$xmlHeader'
    '<p:sldLayout xmlns:a="http://schemas.openxmlformats.org/drawingml/2006'
    '/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006'
    '/relationships" xmlns:p="http://schemas.openxmlformats.org'
    '/presentationml/2006/main" type="blank" preserve="1">'
    '<p:cSld name="Blank"><p:spTree>'
    '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/>'
    '</p:nvGrpSpPr>'
    '<p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/>'
    '<a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>'
    '</p:spTree></p:cSld>'
    '<p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>'
    '</p:sldLayout>';

/// The smallest theme PowerPoint accepts.
///
/// A slide master must reference one, and the reference must resolve: the
/// colour scheme, font scheme and format scheme are all required, however
/// little the presentation uses them.
String _theme() {
  const fonts =
      '<a:latin typeface="Calibri"/><a:ea typeface=""/><a:cs typeface=""/>';
  const fill = '<a:solidFill><a:schemeClr val="phClr"/></a:solidFill>';
  const line =
      '<a:ln w="9525" cap="flat" cmpd="sng" algn="ctr">$fill'
      '<a:prstDash val="solid"/></a:ln>';

  return '$xmlHeader'
      '<a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006'
      '/main" name="Folio">'
      '<a:themeElements>'
      '<a:clrScheme name="Folio">'
      '<a:dk1><a:sysClr val="windowText" lastClr="000000"/></a:dk1>'
      '<a:lt1><a:sysClr val="window" lastClr="FFFFFF"/></a:lt1>'
      '<a:dk2><a:srgbClr val="1E3D41"/></a:dk2>'
      '<a:lt2><a:srgbClr val="FAFAF7"/></a:lt2>'
      '<a:accent1><a:srgbClr val="2F5D62"/></a:accent1>'
      '<a:accent2><a:srgbClr val="4F7F84"/></a:accent2>'
      '<a:accent3><a:srgbClr val="C9D8D9"/></a:accent3>'
      '<a:accent4><a:srgbClr val="8FB0B3"/></a:accent4>'
      '<a:accent5><a:srgbClr val="6B9295"/></a:accent5>'
      '<a:accent6><a:srgbClr val="3E6B70"/></a:accent6>'
      '<a:hlink><a:srgbClr val="2F5D62"/></a:hlink>'
      '<a:folHlink><a:srgbClr val="1E3D41"/></a:folHlink>'
      '</a:clrScheme>'
      '<a:fontScheme name="Folio">'
      '<a:majorFont>$fonts</a:majorFont>'
      '<a:minorFont>$fonts</a:minorFont>'
      '</a:fontScheme>'
      '<a:fmtScheme name="Folio">'
      '<a:fillStyleLst>$fill$fill$fill</a:fillStyleLst>'
      '<a:lnStyleLst>$line$line$line</a:lnStyleLst>'
      '<a:effectStyleLst>'
      '<a:effectStyle><a:effectLst/></a:effectStyle>'
      '<a:effectStyle><a:effectLst/></a:effectStyle>'
      '<a:effectStyle><a:effectLst/></a:effectStyle>'
      '</a:effectStyleLst>'
      '<a:bgFillStyleLst>$fill$fill$fill</a:bgFillStyleLst>'
      '</a:fmtScheme>'
      '</a:themeElements>'
      '</a:theme>';
}
