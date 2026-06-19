// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'jet_print_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class JetPrintLocalizationsDe extends JetPrintLocalizations {
  JetPrintLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get reportTitlePlaceholder => 'Unbenannter Bericht';

  @override
  String get actionPreview => 'Vorschau';

  @override
  String get actionPreviewTooltip => 'Bericht in der Vorschau anzeigen';

  @override
  String get actionSave => 'Speichern';

  @override
  String get actionSaveTooltip => 'Bericht speichern';

  @override
  String get actionExport => 'Exportieren';

  @override
  String get actionExportTooltip => 'Bericht exportieren';

  @override
  String get actionOpen => 'Öffnen';

  @override
  String get actionOpenTooltip => 'Bericht öffnen';

  @override
  String get actionUndoTooltip => 'Rückgängig';

  @override
  String get actionRedoTooltip => 'Wiederholen';

  @override
  String get actionZoomInTooltip => 'Vergrößern';

  @override
  String get actionZoomOutTooltip => 'Verkleinern';

  @override
  String get actionZoomFieldTooltip =>
      'Zoomstufe – Prozentwert eingeben oder Voreinstellung bzw. Anpassung wählen';

  @override
  String get menuZoomFitWidth => 'An Breite anpassen';

  @override
  String get menuZoomFitPage => 'An Seite anpassen';

  @override
  String get toggleGridTooltip => 'Raster anzeigen';

  @override
  String get toggleRulerTooltip => 'Lineale anzeigen';

  @override
  String get toggleSnapTooltip => 'Am Raster ausrichten';

  @override
  String get actionCutTooltip => 'Ausschneiden';

  @override
  String get actionCopyTooltip => 'Kopieren';

  @override
  String get actionPasteTooltip => 'Einfügen';

  @override
  String get menuDuplicate => 'Duplizieren';

  @override
  String get menuDelete => 'Löschen';

  @override
  String get tabDataSource => 'Datenquelle';

  @override
  String get tabOutline => 'Gliederung';

  @override
  String get tabProperties => 'Eigenschaften';

  @override
  String get dataSourceEmpty => 'Keine Datenquelle verbunden.';

  @override
  String get toolboxTextEntry => 'Text';

  @override
  String get toolboxShapeEntry => 'Form';

  @override
  String get toolboxTableEntry => 'Tabelle';

  @override
  String get toolboxImageEntry => 'Bild';

  @override
  String get toolboxChartEntry => 'Diagramm';

  @override
  String get toolboxBarcodeEntry => 'Barcode';

  @override
  String get surfaceEmptyHint =>
      'Ziehen Sie Elemente aus dem Werkzeugkasten auf die Seite, um zu beginnen.';

  @override
  String get bandTypeTitle => 'Titel';

  @override
  String get bandTypePageHeader => 'Seitenkopf';

  @override
  String get bandTypeColumnHeader => 'Spaltenkopf';

  @override
  String get bandTypeGroupHeader => 'Gruppenkopf';

  @override
  String get bandTypeDetail => 'Detail';

  @override
  String get bandTypeGroupFooter => 'Gruppenfuß';

  @override
  String get bandTypeColumnFooter => 'Spaltenfuß';

  @override
  String get bandTypePageFooter => 'Seitenfuß';

  @override
  String get bandTypeSummary => 'Zusammenfassung';

  @override
  String get bandTypeBackground => 'Hintergrund';

  @override
  String get bandTypeNoData => 'Keine Daten';

  @override
  String get expandToolboxTooltip => 'Werkzeugkasten einblenden';

  @override
  String get collapseToolboxTooltip => 'Werkzeugkasten ausblenden';

  @override
  String get expandPanelTooltip => 'Bereich einblenden';

  @override
  String get collapsePanelTooltip => 'Bereich ausblenden';

  @override
  String get actionArrangeTooltip => 'Anordnen';

  @override
  String get arrangeAlignLeft => 'Linksbündig ausrichten';

  @override
  String get arrangeAlignCenter => 'Horizontal zentrieren';

  @override
  String get arrangeAlignRight => 'Rechtsbündig ausrichten';

  @override
  String get arrangeAlignTop => 'Oben ausrichten';

  @override
  String get arrangeAlignMiddle => 'Vertikal zentrieren';

  @override
  String get arrangeAlignBottom => 'Unten ausrichten';

  @override
  String get arrangeDistributeHorizontally => 'Horizontal verteilen';

  @override
  String get arrangeDistributeVertically => 'Vertikal verteilen';

  @override
  String get arrangeBringToFront => 'In den Vordergrund';

  @override
  String get arrangeBringForward => 'Eine Ebene nach vorne';

  @override
  String get arrangeSendBackward => 'Eine Ebene nach hinten';

  @override
  String get arrangeSendToBack => 'In den Hintergrund';

  @override
  String get propertiesPosition => 'Position';

  @override
  String get propertiesSize => 'Größe';

  @override
  String get propertiesText => 'Text';

  @override
  String get propertiesValue => 'Wert';

  @override
  String get valueFieldHint => '[Feld] oder Text';

  @override
  String get valueFieldPickerTooltip => 'Datenfeld einfügen';

  @override
  String get valueFieldFxTooltip => 'Ausdruck erstellen';

  @override
  String get exprEditorTitle => 'Ausdruck';

  @override
  String get exprEditorFieldsLabel => 'Felder';

  @override
  String get exprEditorFunctionsLabel => 'Funktionen';

  @override
  String get exprGroupString => 'Text';

  @override
  String get exprGroupMath => 'Mathe';

  @override
  String get exprGroupLogic => 'Logik';

  @override
  String get exprGroupAggregate => 'Aggregat';

  @override
  String get exprStatusValid => 'Gültig';

  @override
  String get exprStatusSyntaxError =>
      'Unvollständiger oder ungültiger Ausdruck';

  @override
  String exprStatusUnresolved(String name) {
    return 'Feld nicht in der Datenquelle: $name';
  }

  @override
  String get exprEditorCancel => 'Abbrechen';

  @override
  String get exprEditorInsert => 'Einfügen';

  @override
  String get propertiesFormat => 'Format';

  @override
  String get formatHint => 'z. B. #,##0.00';

  @override
  String get formatPresetPickerTooltip => 'Formatvorlage wählen';

  @override
  String get formatPresetNone => 'Keine';

  @override
  String get formatPresetInteger => 'Ganzzahl';

  @override
  String get formatPresetDecimal => 'Dezimal';

  @override
  String get formatPresetCurrency => 'Währung';

  @override
  String get formatPresetPercent => 'Prozent';

  @override
  String get formatPresetDate => 'Datum';

  @override
  String get formatPresetDateTime => 'Datum & Uhrzeit';

  @override
  String get errorUnresolvedToken => '#FEHLER';

  @override
  String get propertiesBinding => 'Bindung';

  @override
  String get propertiesGroup => 'Gruppe';

  @override
  String get propertiesGroupName => 'Gruppenname';

  @override
  String get propertiesGroupNewPage => 'Auf neuer Seite beginnen';

  @override
  String get propertiesGroupKey => 'Gruppenschlüssel';

  @override
  String get propertiesGroupKeepTogether => 'Zusammenhalten';

  @override
  String get propertiesGroupReprintHeader => 'Kopf auf jeder Seite wiederholen';

  @override
  String get propertiesGroupOnHeaderHint =>
      'Seiten- und Gruppeneinstellungen am Gruppenkopf-Band bearbeiten.';

  @override
  String get propertiesScope => 'Bereich';

  @override
  String get outlineMoveUp => 'Nach oben';

  @override
  String get outlineMoveDown => 'Nach unten';

  @override
  String get outlineRemove => 'Band entfernen';

  @override
  String get outlineRetype => 'Bandtyp ändern';

  @override
  String get outlineAddBand => 'Band hinzufügen';

  @override
  String get outlineAddList => 'Liste hinzufügen';

  @override
  String get outlineAddGroup => 'Gruppe hinzufügen';

  @override
  String get outlineAddHeader => 'Kopf hinzufügen';

  @override
  String get outlineAddFooter => 'Fuß hinzufügen';

  @override
  String get bindingExpressionHint => 'Feld oder Ausdruck';

  @override
  String get bindingImageFieldHint => 'Feldname';

  @override
  String get bindingClearTooltip => 'Bindung entfernen';

  @override
  String get bindingCollectionHint => 'Sammlungsfeld';

  @override
  String get bindingFieldPickerTooltip => 'Feld auswählen';

  @override
  String get bindingUnresolved => 'Feld nicht in der Datenquelle gefunden';

  @override
  String get propertiesHeight => 'Höhe';

  @override
  String get propertiesPage => 'Seite';

  @override
  String get propertiesMargins => 'Ränder';

  @override
  String get propertiesPaper => 'Papier';

  @override
  String get propertiesCustom => 'Benutzerdefiniert';

  @override
  String get propertiesWidth => 'Breite';

  @override
  String get paperPickerTooltip => 'Papierformat wählen';

  @override
  String get orientationPortrait => 'Hochformat';

  @override
  String get orientationLandscape => 'Querformat';

  @override
  String get marginPresetNormal => 'Normal';

  @override
  String get marginPresetNarrow => 'Schmal';

  @override
  String get marginPresetWide => 'Breit';

  @override
  String get marginPresetNone => 'Keine';

  @override
  String get marginPickerTooltip => 'Ränder wählen';

  @override
  String get propertiesMarginLeft => 'Links';

  @override
  String get propertiesMarginTop => 'Oben';

  @override
  String get propertiesMarginRight => 'Rechts';

  @override
  String get propertiesMarginBottom => 'Unten';

  @override
  String get reportLabel => 'Bericht';

  @override
  String get propertiesName => 'Name';

  @override
  String get reportNameHint => 'Berichtsname';

  @override
  String get propertiesEmptyHint =>
      'Wählen Sie ein Objekt, um seine Eigenschaften zu bearbeiten.';

  @override
  String propertiesMultiSelected(int count) {
    return '$count Elemente ausgewählt';
  }

  @override
  String get elementTypeText => 'Text';

  @override
  String get elementTypeShape => 'Form';

  @override
  String get elementTypeImage => 'Bild';

  @override
  String get elementTypeBarcode => 'Barcode';

  @override
  String get elementTypeGeneric => 'Element';

  @override
  String elementSemanticLabel(String type, String id) {
    return '$type-Element $id';
  }

  @override
  String get resizeHandleTopLeft => 'Größe ändern, obere linke Ecke';

  @override
  String get resizeHandleTop => 'Größe ändern, obere Kante';

  @override
  String get resizeHandleTopRight => 'Größe ändern, obere rechte Ecke';

  @override
  String get resizeHandleRight => 'Größe ändern, rechte Kante';

  @override
  String get resizeHandleBottomRight => 'Größe ändern, untere rechte Ecke';

  @override
  String get resizeHandleBottom => 'Größe ändern, untere Kante';

  @override
  String get resizeHandleBottomLeft => 'Größe ändern, untere linke Ecke';

  @override
  String get resizeHandleLeft => 'Größe ändern, linke Kante';

  @override
  String get resizeBandHandle => 'Bandhöhe ändern';

  @override
  String get previewBack => 'Zurück';

  @override
  String get previewPreviousPage => 'Vorherige Seite';

  @override
  String get previewNextPage => 'Nächste Seite';

  @override
  String previewPageIndicator(int current, int total) {
    return 'Seite $current von $total';
  }

  @override
  String get previewFitToWidth => 'An Breite anpassen';

  @override
  String get previewExport => 'Als PDF exportieren';

  @override
  String get previewPrint => 'Drucken';

  @override
  String get modeDesigner => 'Designer';

  @override
  String get modePreview => 'Vorschau';

  @override
  String get actionRenameTooltip => 'Bericht umbenennen';

  @override
  String get renameFieldLabel => 'Berichtsname';

  @override
  String get propertiesShape => 'Form';

  @override
  String get shapeFormLine => 'Linie';

  @override
  String get shapeFormRectangle => 'Rechteck';

  @override
  String get shapeFormEllipse => 'Ellipse';

  @override
  String get shapeFormTriangle => 'Dreieck';

  @override
  String get shapeFormDiamond => 'Raute';

  @override
  String get shapeFormPentagon => 'Fünfeck';

  @override
  String get shapeFormHexagon => 'Sechseck';

  @override
  String get shapeFormStar => 'Stern';

  @override
  String get propertiesFont => 'Schrift';

  @override
  String get fontFamilyLabel => 'Schriftart';

  @override
  String get fontFamilyPickerTooltip => 'Schriftart wählen';

  @override
  String get fontFamilyDefault => 'Standard';

  @override
  String fontFamilyUnavailable(String family) {
    return '$family (nicht verfügbar)';
  }

  @override
  String get fontSizeLabel => 'Größe';

  @override
  String get fontBoldTooltip => 'Fett';

  @override
  String get fontItalicTooltip => 'Kursiv';

  @override
  String get fontUnderlineTooltip => 'Unterstrichen';

  @override
  String get alignLeftTooltip => 'Linksbündig';

  @override
  String get alignCenterTooltip => 'Zentriert';

  @override
  String get alignRightTooltip => 'Rechtsbündig';

  @override
  String get propertiesColor => 'Farbe';

  @override
  String get colorPickerTooltip => 'Farbe wählen';

  @override
  String get colorHexLabel => 'Hex';

  @override
  String get colorNone => 'Keine';

  @override
  String get swatchBlack => 'Schwarz';

  @override
  String get swatchWhite => 'Weiß';

  @override
  String get swatchGray => 'Grau';

  @override
  String get swatchSilver => 'Silber';

  @override
  String get swatchRed => 'Rot';

  @override
  String get swatchOrange => 'Orange';

  @override
  String get swatchAmber => 'Bernstein';

  @override
  String get swatchYellow => 'Gelb';

  @override
  String get swatchGreen => 'Grün';

  @override
  String get swatchEmerald => 'Smaragd';

  @override
  String get swatchTeal => 'Petrol';

  @override
  String get swatchCyan => 'Cyan';

  @override
  String get swatchBlue => 'Blau';

  @override
  String get swatchIndigo => 'Indigo';

  @override
  String get swatchViolet => 'Violett';

  @override
  String get swatchPink => 'Rosa';

  @override
  String get propertiesAppearance => 'Darstellung';

  @override
  String get propertiesFill => 'Füllung';

  @override
  String get propertiesOutline => 'Kontur';

  @override
  String get propertiesOutlineWidth => 'Breite';

  @override
  String get propertiesList => 'Liste';

  @override
  String get propertiesListRootSource => 'Hauptdatensatz (Stamm)';

  @override
  String get bindingCollectionMissing =>
      'Liste ist an kein Sammlungsfeld gebunden';

  @override
  String get dataSourceAddList => 'Als Liste hinzufügen';

  @override
  String get dataSourceAddGroup => 'Als Gruppe hinzufügen';

  @override
  String outlineListLabel(String field) {
    return 'Liste: $field';
  }

  @override
  String get outlineListUnbound => 'Liste (ungebunden)';

  @override
  String get exprEditorDeeperFieldHint =>
      'Nachgeordnetes Feld – nur innerhalb eines Aggregats wie SUM(…) gültig';

  @override
  String get propertiesColumnLayout => 'Spaltenlayout';

  @override
  String get propertiesColumnLayoutAdd => 'Spaltenlayout hinzufügen';

  @override
  String get propertiesColumnLayoutAddDisabled =>
      'Erfordert ein einzelnes Detailband ohne Titel, Zusammenfassung, Gruppen oder Fußzeile.';

  @override
  String get propertiesColumnLayoutRemove => 'Spaltenlayout entfernen';

  @override
  String get propertiesColumnCount => 'Spalten';

  @override
  String get propertiesColumnWidth => 'Spaltenbreite';

  @override
  String get propertiesColumnSpacing => 'Spaltenabstand';

  @override
  String get propertiesRowSpacing => 'Zeilenabstand';

  @override
  String get propertiesColumnLayoutInactive =>
      'Spaltenlayout ist inaktiv: Der Bericht ist kein einzelnes Detailband.';

  @override
  String get propertiesColumnErrTooFew => 'Mindestens eine Spalte hinzufügen.';

  @override
  String get propertiesColumnErrDimensions =>
      'Die Spaltenbreite muss größer als null sein, und Abstände dürfen nicht negativ sein.';

  @override
  String get propertiesColumnErrGridTooWide =>
      'Die Spalten passen nicht auf die Seitenbreite — Spaltenanzahl oder -breite verringern.';

  @override
  String get propertiesColumnErrLabelTooTall =>
      'Das Etikett ist höher als die Seite — Bandhöhe verringern, damit eine Zeile passt.';

  @override
  String propertiesColumnElementsClipped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count Elemente ragen über die Spalte hinaus und werden abgeschnitten.',
      one: '1 Element ragt über die Spalte hinaus und wird abgeschnitten.',
    );
    return '$_temp0';
  }

  @override
  String get propertiesBarcode => 'Barcode';

  @override
  String get propertiesSymbology => 'Symbologie';

  @override
  String get barcodeSymbologyAuto => 'Automatisch';

  @override
  String get propertiesBarcodeData => 'Daten';

  @override
  String get barcodeDataLiteral => 'Literal';

  @override
  String get barcodeDataField => 'Feld';

  @override
  String get barcodeShowText => 'Text anzeigen';

  @override
  String get barcodeQuietZone => 'Ruhezone';

  @override
  String get barcodeEccLevel => 'Fehlerkorrektur';

  @override
  String get barcodeInvalidValue => 'Wert ist für diese Symbologie ungültig';

  @override
  String barcodeAutoInferred(String symbology) {
    return 'Auto → $symbology';
  }
}
