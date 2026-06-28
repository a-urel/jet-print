// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'jet_print_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Turkish (`tr`).
class JetPrintLocalizationsTr extends JetPrintLocalizations {
  JetPrintLocalizationsTr([String locale = 'tr']) : super(locale);

  @override
  String get reportTitlePlaceholder => 'Adsız rapor';

  @override
  String get actionPreview => 'Önizleme';

  @override
  String get actionPreviewTooltip => 'Raporu önizle';

  @override
  String get actionSave => 'Kaydet';

  @override
  String get actionSaveTooltip => 'Raporu kaydet';

  @override
  String get actionExport => 'Dışa Aktar';

  @override
  String get actionExportTooltip => 'Raporu dışa aktar';

  @override
  String get actionOpen => 'Aç';

  @override
  String get actionOpenTooltip => 'Rapor aç';

  @override
  String get actionUndoTooltip => 'Geri al';

  @override
  String get actionRedoTooltip => 'Yinele';

  @override
  String get actionZoomInTooltip => 'Yakınlaştır';

  @override
  String get actionZoomOutTooltip => 'Uzaklaştır';

  @override
  String get actionZoomFieldTooltip =>
      'Yakınlaştırma düzeyi — yüzde girin ya da hazır değer veya sığdırma seçin';

  @override
  String get actionZoomFitTooltip => 'Genişliğe sığdır';

  @override
  String get menuZoomFitWidth => 'Genişliğe sığdır';

  @override
  String get menuZoomFitPage => 'Sayfaya sığdır';

  @override
  String get toggleGridTooltip => 'Izgarayı göster';

  @override
  String get toggleRulerTooltip => 'Cetvelleri göster';

  @override
  String get toggleSnapTooltip => 'Izgaraya hizala';

  @override
  String get actionCutTooltip => 'Kes';

  @override
  String get actionCopyTooltip => 'Kopyala';

  @override
  String get actionPasteTooltip => 'Yapıştır';

  @override
  String get menuDuplicate => 'Çoğalt';

  @override
  String get menuDelete => 'Sil';

  @override
  String get tabDataSource => 'Veri Kaynağı';

  @override
  String get tabOutline => 'Anahat';

  @override
  String get tabProperties => 'Özellikler';

  @override
  String get dataSourceEmpty => 'Veri kaynağı bağlı değil.';

  @override
  String get dataSourceSelect => 'Veri kaynağı seç';

  @override
  String get toolboxTextEntry => 'Metin';

  @override
  String get toolboxShapeEntry => 'Şekil';

  @override
  String get toolboxTableEntry => 'Tablo';

  @override
  String get toolboxImageEntry => 'Resim';

  @override
  String get toolboxChartEntry => 'Grafik';

  @override
  String get toolboxBarcodeEntry => 'Barkod';

  @override
  String get surfaceEmptyHint =>
      'Başlamak için araç kutusundan öğeleri sayfaya sürükleyin.';

  @override
  String get bandTypeTitle => 'Rapor Başlığı';

  @override
  String get bandTypePageHeader => 'Sayfa Başlığı';

  @override
  String get bandTypeColumnHeader => 'Sütun Başlığı';

  @override
  String get bandTypeGroupHeader => 'Grup Başlığı';

  @override
  String get bandTypeDetail => 'Detay';

  @override
  String get bandTypeGroupFooter => 'Grup Alt Bilgisi';

  @override
  String get bandTypeColumnFooter => 'Sütun Alt Bilgisi';

  @override
  String get bandTypePageFooter => 'Sayfa Alt Bilgisi';

  @override
  String get bandTypeSummary => 'Rapor Altbilgisi';

  @override
  String get bandTypeBackground => 'Arka Plan';

  @override
  String get bandTypeNoData => 'Veri Yok';

  @override
  String get expandToolboxTooltip => 'Araç kutusunu genişlet';

  @override
  String get collapseToolboxTooltip => 'Araç kutusunu daralt';

  @override
  String get expandPanelTooltip => 'Paneli genişlet';

  @override
  String get collapsePanelTooltip => 'Paneli daralt';

  @override
  String get actionArrangeTooltip => 'Düzen';

  @override
  String get arrangeAlignLeft => 'Sola hizala';

  @override
  String get arrangeAlignCenter => 'Yatayda ortala';

  @override
  String get arrangeAlignRight => 'Sağa hizala';

  @override
  String get arrangeAlignTop => 'Üste hizala';

  @override
  String get arrangeAlignMiddle => 'Dikeyde ortala';

  @override
  String get arrangeAlignBottom => 'Alta hizala';

  @override
  String get arrangeDistributeHorizontally => 'Yatayda dağıt';

  @override
  String get arrangeDistributeVertically => 'Dikeyde dağıt';

  @override
  String get arrangeBringToFront => 'Öne getir';

  @override
  String get arrangeBringForward => 'Bir öne getir';

  @override
  String get arrangeSendBackward => 'Bir arkaya gönder';

  @override
  String get arrangeSendToBack => 'Arkaya gönder';

  @override
  String get propertiesPosition => 'Konum';

  @override
  String get propertiesSize => 'Boyut';

  @override
  String get propertiesText => 'Metin';

  @override
  String get propertiesValue => 'Değer';

  @override
  String get valueFieldHint => '[alan] veya metin';

  @override
  String get valueFieldPickerTooltip => 'Veri alanı ekle';

  @override
  String get valueFieldFxTooltip => 'İfade oluştur';

  @override
  String get exprEditorTitle => 'İfade';

  @override
  String get exprEditorFieldsLabel => 'Alanlar';

  @override
  String get exprEditorFunctionsLabel => 'Fonksiyonlar';

  @override
  String get exprGroupString => 'Metin';

  @override
  String get exprGroupMath => 'Matematik';

  @override
  String get exprGroupLogic => 'Mantık';

  @override
  String get exprGroupAggregate => 'Toplam';

  @override
  String get exprStatusValid => 'Geçerli';

  @override
  String get exprStatusSyntaxError => 'Eksik veya geçersiz ifade';

  @override
  String exprStatusUnresolved(String name) {
    return 'Alan veri kaynağında yok: $name';
  }

  @override
  String get exprEditorCancel => 'İptal';

  @override
  String get exprEditorInsert => 'Ekle';

  @override
  String get propertiesFormat => 'Biçim';

  @override
  String get formatHint => 'örn. #,##0.00';

  @override
  String get formatPresetPickerTooltip => 'Biçim ön ayarı seç';

  @override
  String get formatPresetNone => 'Yok';

  @override
  String get formatPresetInteger => 'Tam sayı';

  @override
  String get formatPresetDecimal => 'Ondalık';

  @override
  String get formatPresetCurrency => 'Para birimi';

  @override
  String get formatPresetPercent => 'Yüzde';

  @override
  String get formatPresetDate => 'Tarih';

  @override
  String get formatPresetDateTime => 'Tarih ve saat';

  @override
  String get errorUnresolvedToken => '#HATA';

  @override
  String get propertiesBinding => 'Bağlantı';

  @override
  String get propertiesGroup => 'Grup';

  @override
  String get propertiesGroupName => 'Grup adı';

  @override
  String get propertiesGroupNewPage => 'Yeni sayfa başlat';

  @override
  String get propertiesGroupKey => 'Grup anahtarı';

  @override
  String get propertiesGroupKeepTogether => 'Birlikte tut';

  @override
  String get propertiesGroupReprintHeader => 'Başlığı her sayfada yinele';

  @override
  String get propertiesGroupOnHeaderHint =>
      'Sayfa ve grup ayarlarını grup başlığı bandında düzenleyin.';

  @override
  String get propertiesScope => 'Kapsam';

  @override
  String get outlineMoveUp => 'Yukarı taşı';

  @override
  String get outlineMoveDown => 'Aşağı taşı';

  @override
  String get outlineRemove => 'Bandı kaldır';

  @override
  String get outlineRetype => 'Bant türünü değiştir';

  @override
  String get outlineAddBand => 'Bant ekle';

  @override
  String get outlineAddList => 'Liste ekle';

  @override
  String get outlineAddGroup => 'Grup ekle';

  @override
  String get outlineAddHeader => 'Başlık ekle';

  @override
  String get outlineAddFooter => 'Alt bilgi ekle';

  @override
  String get bindingExpressionHint => 'Alan veya ifade';

  @override
  String get bindingImageFieldHint => 'Alan adı';

  @override
  String get bindingClearTooltip => 'Bağlantıyı temizle';

  @override
  String get bindingCollectionHint => 'Koleksiyon alanı';

  @override
  String get bindingFieldPickerTooltip => 'Alan seç';

  @override
  String get bindingUnresolved => 'Alan veri kaynağında bulunamadı';

  @override
  String get propertiesHeight => 'Yükseklik';

  @override
  String get propertiesPage => 'Sayfa';

  @override
  String get propertiesMargins => 'Kenar boşlukları';

  @override
  String get propertiesPaper => 'Kağıt';

  @override
  String get propertiesCustom => 'Özel';

  @override
  String get propertiesWidth => 'Genişlik';

  @override
  String get paperPickerTooltip => 'Kağıt boyutu seçin';

  @override
  String get orientationPortrait => 'Dikey';

  @override
  String get orientationLandscape => 'Yatay';

  @override
  String get marginPresetNormal => 'Normal';

  @override
  String get marginPresetNarrow => 'Dar';

  @override
  String get marginPresetWide => 'Geniş';

  @override
  String get marginPresetNone => 'Yok';

  @override
  String get marginPickerTooltip => 'Kenar boşluklarını seçin';

  @override
  String get propertiesMarginLeft => 'Sol';

  @override
  String get propertiesMarginTop => 'Üst';

  @override
  String get propertiesMarginRight => 'Sağ';

  @override
  String get propertiesMarginBottom => 'Alt';

  @override
  String get reportLabel => 'Rapor';

  @override
  String get propertiesName => 'Ad';

  @override
  String get reportNameHint => 'Rapor adı';

  @override
  String get propertiesEmptyHint =>
      'Özelliklerini düzenlemek için bir nesne seçin.';

  @override
  String propertiesMultiSelected(int count) {
    return '$count öğe seçildi';
  }

  @override
  String get elementTypeText => 'Metin';

  @override
  String get elementTypeShape => 'Şekil';

  @override
  String get elementTypeImage => 'Görsel';

  @override
  String get elementTypeBarcode => 'Barkod';

  @override
  String get elementTypeGeneric => 'Öğe';

  @override
  String elementSemanticLabel(String type, String id) {
    return '$type öğesi $id';
  }

  @override
  String get resizeHandleTopLeft => 'Boyutlandır, sol üst köşe';

  @override
  String get resizeHandleTop => 'Boyutlandır, üst kenar';

  @override
  String get resizeHandleTopRight => 'Boyutlandır, sağ üst köşe';

  @override
  String get resizeHandleRight => 'Boyutlandır, sağ kenar';

  @override
  String get resizeHandleBottomRight => 'Boyutlandır, sağ alt köşe';

  @override
  String get resizeHandleBottom => 'Boyutlandır, alt kenar';

  @override
  String get resizeHandleBottomLeft => 'Boyutlandır, sol alt köşe';

  @override
  String get resizeHandleLeft => 'Boyutlandır, sol kenar';

  @override
  String get resizeBandHandle => 'Bant yüksekliğini değiştir';

  @override
  String get previewBack => 'Geri';

  @override
  String get previewPreviousPage => 'Önceki sayfa';

  @override
  String get previewNextPage => 'Sonraki sayfa';

  @override
  String previewPageIndicator(int current, int total) {
    return 'Sayfa $current / $total';
  }

  @override
  String get previewFirstPage => 'İlk sayfa';

  @override
  String get previewLastPage => 'Son sayfa';

  @override
  String get previewGoToPage => 'Sayfaya git';

  @override
  String get previewFitToWidth => 'Genişliğe sığdır';

  @override
  String get previewExport => 'PDF olarak dışa aktar';

  @override
  String get previewPrint => 'Yazdır';

  @override
  String get modeDesigner => 'Tasarım';

  @override
  String get modePreview => 'Önizleme';

  @override
  String get actionRenameTooltip => 'Raporu yeniden adlandır';

  @override
  String get renameFieldLabel => 'Rapor adı';

  @override
  String get propertiesShape => 'Şekil';

  @override
  String get shapeFormLine => 'Çizgi';

  @override
  String get shapeFormRectangle => 'Dikdörtgen';

  @override
  String get shapeFormEllipse => 'Elips';

  @override
  String get shapeFormTriangle => 'Üçgen';

  @override
  String get shapeFormDiamond => 'Eşkenar dörtgen';

  @override
  String get shapeFormPentagon => 'Beşgen';

  @override
  String get shapeFormHexagon => 'Altıgen';

  @override
  String get shapeFormStar => 'Yıldız';

  @override
  String get shapeFormArrowRight => 'Sağ ok';

  @override
  String get shapeFormArrowLeft => 'Sol ok';

  @override
  String get shapeFormArrowUp => 'Yukarı ok';

  @override
  String get shapeFormArrowDown => 'Aşağı ok';

  @override
  String get shapeFormArrowDouble => 'Çift ok';

  @override
  String get shapeFormChevron => 'Şerit ok';

  @override
  String get shapeFormRoundRect => 'Yuvarlatılmış dikdörtgen';

  @override
  String get propertiesFont => 'Yazı Tipi';

  @override
  String get fontFamilyLabel => 'Yazı tipi';

  @override
  String get fontFamilyPickerTooltip => 'Yazı tipi seç';

  @override
  String get fontFamilyDefault => 'Varsayılan';

  @override
  String fontFamilyUnavailable(String family) {
    return '$family (kullanılamıyor)';
  }

  @override
  String get fontSizeLabel => 'Boyut';

  @override
  String get fontBoldTooltip => 'Kalın';

  @override
  String get fontItalicTooltip => 'İtalik';

  @override
  String get fontUnderlineTooltip => 'Altı çizili';

  @override
  String get alignLeftTooltip => 'Sola hizala';

  @override
  String get alignCenterTooltip => 'Ortala';

  @override
  String get alignRightTooltip => 'Sağa hizala';

  @override
  String get propertiesColor => 'Renk';

  @override
  String get colorPickerTooltip => 'Renk seç';

  @override
  String get colorHexLabel => 'Onaltılık';

  @override
  String get colorNone => 'Yok';

  @override
  String get swatchBlack => 'Siyah';

  @override
  String get swatchWhite => 'Beyaz';

  @override
  String get swatchGray => 'Gri';

  @override
  String get swatchSilver => 'Gümüş';

  @override
  String get swatchRed => 'Kırmızı';

  @override
  String get swatchOrange => 'Turuncu';

  @override
  String get swatchAmber => 'Kehribar';

  @override
  String get swatchYellow => 'Sarı';

  @override
  String get swatchGreen => 'Yeşil';

  @override
  String get swatchEmerald => 'Zümrüt';

  @override
  String get swatchTeal => 'Petrol';

  @override
  String get swatchCyan => 'Camgöbeği';

  @override
  String get swatchBlue => 'Mavi';

  @override
  String get swatchIndigo => 'Çivit';

  @override
  String get swatchViolet => 'Mor';

  @override
  String get swatchPink => 'Pembe';

  @override
  String get propertiesAppearance => 'Görünüm';

  @override
  String get propertiesFill => 'Dolgu';

  @override
  String get propertiesOutline => 'Anahat';

  @override
  String get propertiesOutlineWidth => 'Genişlik';

  @override
  String get propertiesList => 'Liste';

  @override
  String get propertiesListRootSource => 'Ana veri kümesi (kök)';

  @override
  String get bindingCollectionMissing =>
      'Liste bir koleksiyon alanına bağlı değil';

  @override
  String get dataSourceAddList => 'Liste olarak ekle';

  @override
  String get dataSourceAddGroup => 'Grup olarak ekle';

  @override
  String outlineListLabel(String field) {
    return 'Liste: $field';
  }

  @override
  String get outlineListUnbound => 'Liste (bağsız)';

  @override
  String get exprEditorDeeperFieldHint =>
      'Alt alan – yalnızca SUM(…) gibi bir toplama içinde geçerlidir';

  @override
  String get propertiesColumnLayout => 'Sütun düzeni';

  @override
  String get propertiesColumnLayoutAdd => 'Sütun düzeni ekle';

  @override
  String get propertiesColumnLayoutAddDisabled =>
      'Başlık, özet, grup veya alt bilgi içermeyen tek bir ayrıntı bandı gerektirir.';

  @override
  String get propertiesColumnLayoutRemove => 'Sütun düzenini kaldır';

  @override
  String get propertiesColumnCount => 'Sütunlar';

  @override
  String get propertiesColumnWidth => 'Sütun genişliği';

  @override
  String get propertiesColumnSpacing => 'Sütun aralığı';

  @override
  String get propertiesRowSpacing => 'Satır aralığı';

  @override
  String get propertiesColumnLayoutInactive =>
      'Sütun düzeni etkin değil: rapor tek bir ayrıntı bandı değil.';

  @override
  String get propertiesColumnErrTooFew => 'En az bir sütun ekleyin.';

  @override
  String get propertiesColumnErrDimensions =>
      'Sütun genişliği sıfırdan büyük olmalı ve boşluklar negatif olamaz.';

  @override
  String get propertiesColumnErrGridTooWide =>
      'Sütunlar sayfa genişliğine sığmıyor — sütun sayısını veya genişliğini azaltın.';

  @override
  String get propertiesColumnErrLabelTooTall =>
      'Etiket sayfadan uzun — bir satır sığması için bant yüksekliğini azaltın.';

  @override
  String propertiesColumnElementsClipped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count öğe sütunun dışına taşıyor ve kırpılacak.',
      one: '1 öğe sütunun dışına taşıyor ve kırpılacak.',
    );
    return '$_temp0';
  }

  @override
  String get propertiesBarcode => 'Barkod';

  @override
  String get propertiesSymbology => 'Semboloji';

  @override
  String get barcodeSymbologyAuto => 'Otomatik';

  @override
  String get propertiesBarcodeData => 'Veri';

  @override
  String get barcodeDataLiteral => 'Değişmez';

  @override
  String get barcodeDataField => 'Alan';

  @override
  String get barcodeShowText => 'Metni göster';

  @override
  String get barcodeQuietZone => 'Sessiz bölge';

  @override
  String get barcodeEccLevel => 'Hata düzeltme';

  @override
  String get barcodeInvalidValue => 'Değer bu semboloji için geçersiz';

  @override
  String barcodeAutoInferred(String symbology) {
    return 'Otomatik → $symbology';
  }

  @override
  String get elementTypeChart => 'Grafik';

  @override
  String get propertiesChart => 'Grafik';

  @override
  String get propertiesChartType => 'Tür';

  @override
  String get chartTypeBar => 'Çubuk';

  @override
  String get chartTypeLine => 'Çizgi';

  @override
  String get chartTypePie => 'Pasta';

  @override
  String get propertiesChartCollection => 'Koleksiyon';

  @override
  String get propertiesChartValue => 'Değer';

  @override
  String get propertiesChartCategory => 'Kategori';

  @override
  String get propertiesChartTitle => 'Başlık';

  @override
  String get propertiesChartShowAxes => 'Eksenleri göster';

  @override
  String get propertiesChartShowValueLabels => 'Değer etiketleri';

  @override
  String get propertiesChartShowLegend => 'Açıklama';

  @override
  String get propertiesChartColor => 'Renk';

  @override
  String get propertiesVisible => 'Görünür';

  @override
  String get propertiesVisibleWhen => 'Görünür koşul';

  @override
  String get propertiesVisibleClear => 'Görünürlük ifadesini temizle';
}
