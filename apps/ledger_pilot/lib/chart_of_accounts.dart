/// The pilot's chart of accounts: a trimmed Turkish Tek Düzen Hesap Planı
/// (TDHP).
///
/// TDHP codes nest by prefix — `1` (class) → `10` (group) → `100` (main
/// account) → `100.01` (posting account) — so the whole hierarchy is
/// recoverable from a posting account's code alone. That is why the ledger
/// rows this chart produces carry no parent keys: the report takes its group
/// keys from the code with `SUBSTRING`, and the Dart side derives the same
/// prefixes with `String.substring`, so the two agree by construction.
///
/// Three levels are modelled — class, main account, posting account. The
/// two-digit group level is real TDHP but adds a fourth band to every page
/// without adding anything the pilot is trying to learn.
///
/// Account names are Turkish because they are the report's own user-visible
/// strings. Everything else here is English.
library;

/// One posting account: the leaf a ledger movement is booked to.
class PostingAccount {
  /// Creates a posting account with its full TDHP [code] and Turkish [name].
  const PostingAccount(this.code, this.name);

  /// The full TDHP code, always `NNN.NN` — three digits, a dot, two digits.
  /// Fixed width is what makes a plain string sort the chart correctly.
  final String code;

  /// The account's Turkish name, as it prints in the report.
  final String name;

  /// The one-digit account class this account belongs to (`'1'`).
  String get classCode => code.substring(0, 1);

  /// The three-digit main account this account belongs to (`'100'`).
  String get mainAccountCode => code.substring(0, 3);
}

/// The Turkish name of each TDHP account class, keyed by its single digit.
///
/// Classes 4 (Uzun Vadeli Yabancı Kaynaklar), 8 (serbest) and 9 (Nazım
/// Hesaplar) exist in TDHP but carry no balance in this pilot's data, so they
/// are not listed: a class with no posting account never breaks a group and
/// would never print.
const Map<String, String> accountClassNames = <String, String>{
  '1': 'Dönen Varlıklar',
  '2': 'Duran Varlıklar',
  '3': 'Kısa Vadeli Yabancı Kaynaklar',
  '5': 'Özkaynaklar',
  '6': 'Gelir Tablosu Hesapları',
  '7': 'Maliyet Hesapları',
};

/// The Turkish name of each main account, keyed by its three digits.
///
/// `632` and `770` deliberately share a name: TDHP carries general
/// administrative expenses on both the income-statement side and the cost
/// side, and a mizan prints both.
const Map<String, String> mainAccountNames = <String, String>{
  '100': 'KASA',
  '101': 'ALINAN ÇEKLER',
  '102': 'BANKALAR',
  '108': 'DİĞER HAZIR DEĞERLER',
  '120': 'ALICILAR',
  '121': 'ALACAK SENETLERİ',
  '128': 'ŞÜPHELİ TİCARİ ALACAKLAR',
  '153': 'TİCARİ MALLAR',
  '159': 'VERİLEN SİPARİŞ AVANSLARI',
  '180': 'GELECEK AYLARA AİT GİDERLER',
  '191': 'İNDİRİLECEK KDV',
  '252': 'BİNALAR',
  '253': 'TESİS, MAKİNE VE CİHAZLAR',
  '254': 'TAŞITLAR',
  '255': 'DEMİRBAŞLAR',
  '257': 'BİRİKMİŞ AMORTİSMANLAR',
  '260': 'HAKLAR',
  '300': 'BANKA KREDİLERİ',
  '320': 'SATICILAR',
  '321': 'BORÇ SENETLERİ',
  '335': 'PERSONELE BORÇLAR',
  '340': 'ALINAN SİPARİŞ AVANSLARI',
  '360': 'ÖDENECEK VERGİ VE FONLAR',
  '361': 'ÖDENECEK SOSYAL GÜVENLİK KESİNTİLERİ',
  '381': 'GİDER TAHAKKUKLARI',
  '391': 'HESAPLANAN KDV',
  '500': 'SERMAYE',
  '570': 'GEÇMİŞ YILLAR KÂRLARI',
  '600': 'YURTİÇİ SATIŞLAR',
  '601': 'YURTDIŞI SATIŞLAR',
  '610': 'SATIŞTAN İADELER',
  '621': 'SATILAN TİCARİ MALLAR MALİYETİ',
  '632': 'GENEL YÖNETİM GİDERLERİ',
  '642': 'FAİZ GELİRLERİ',
  '649': 'DİĞER OLAĞAN GELİR VE KÂRLAR',
  '656': 'KAMBİYO ZARARLARI',
  '760': 'PAZARLAMA, SATIŞ VE DAĞITIM GİDERLERİ',
  '770': 'GENEL YÖNETİM GİDERLERİ',
  '780': 'FİNANSMAN GİDERLERİ',
};

/// Every posting account in the pilot's chart, in TDHP code order.
///
/// 68 accounts across six classes and 39 main accounts — enough that the
/// rendered mizan runs to several pages, which is the point: a trial balance
/// that fits on one page tests nothing about repeated headers, group
/// continuation, or where a subtotal lands when its group straddles a break.
///
/// The order here is the order the report needs (see `ledger_data.dart`), but
/// nothing depends on it being written correctly: the rows are sorted by code
/// before they reach the engine.
const List<PostingAccount> postingAccounts = <PostingAccount>[
  // --- 1 Dönen Varlıklar ---
  PostingAccount('100.01', 'Merkez Kasa TL'),
  PostingAccount('100.02', 'Şube Kasa TL'),
  PostingAccount('100.03', 'Döviz Kasası'),
  PostingAccount('101.01', 'Portföydeki Çekler'),
  PostingAccount('101.02', 'Tahsildeki Çekler'),
  PostingAccount('102.01', 'Ziraat Bankası Vadesiz'),
  PostingAccount('102.02', 'İş Bankası Vadesiz'),
  PostingAccount('102.03', 'Garanti BBVA Vadesiz'),
  PostingAccount('102.04', 'Vadeli Mevduat'),
  PostingAccount('102.05', 'Yapı Kredi Vadesiz'),
  PostingAccount('108.01', 'Kredi Kartı Slipleri'),
  PostingAccount('120.01', 'Yurtiçi Alıcılar'),
  PostingAccount('120.02', 'Yurtdışı Alıcılar'),
  PostingAccount('120.03', 'Grup Şirketleri'),
  PostingAccount('121.01', 'Cüzdandaki Senetler'),
  PostingAccount('128.01', 'Şüpheli Ticari Alacaklar'),
  PostingAccount('153.01', 'Ticari Mallar'),
  PostingAccount('159.01', 'Verilen Sipariş Avansları'),
  PostingAccount('180.01', 'Peşin Ödenen Sigorta'),
  PostingAccount('191.01', 'İndirilecek KDV %20'),
  PostingAccount('191.02', 'İndirilecek KDV %10'),
  // --- 2 Duran Varlıklar ---
  PostingAccount('252.01', 'İdari Bina'),
  PostingAccount('253.01', 'Üretim Makineleri'),
  PostingAccount('253.02', 'Laboratuvar Cihazları'),
  PostingAccount('254.01', 'Binek Araçlar'),
  PostingAccount('254.02', 'Nakliye Araçları'),
  PostingAccount('255.01', 'Büro Demirbaşları'),
  PostingAccount('255.02', 'Bilgisayar ve Donanım'),
  PostingAccount('257.01', 'Binalar Amortismanı'),
  PostingAccount('257.02', 'Taşıtlar Amortismanı'),
  PostingAccount('257.03', 'Demirbaşlar Amortismanı'),
  PostingAccount('260.01', 'Yazılım Lisansları'),
  // --- 3 Kısa Vadeli Yabancı Kaynaklar ---
  PostingAccount('300.01', 'Spot Kredi'),
  PostingAccount('300.02', 'Rotatif Kredi'),
  PostingAccount('320.01', 'Yurtiçi Satıcılar'),
  PostingAccount('320.02', 'Yurtdışı Satıcılar'),
  PostingAccount('321.01', 'Borç Senetleri'),
  PostingAccount('335.01', 'Personele Borçlar'),
  PostingAccount('340.01', 'Alınan Sipariş Avansları'),
  PostingAccount('360.01', 'Ödenecek Gelir Vergisi Stopajı'),
  PostingAccount('360.02', 'Ödenecek Damga Vergisi'),
  PostingAccount('361.01', 'SGK Primleri'),
  PostingAccount('381.01', 'Gider Tahakkukları'),
  PostingAccount('391.01', 'Hesaplanan KDV %20'),
  PostingAccount('391.02', 'Hesaplanan KDV %10'),
  // --- 5 Özkaynaklar ---
  PostingAccount('500.01', 'Ödenmiş Sermaye'),
  PostingAccount('570.01', 'Geçmiş Yıllar Kârları'),
  // --- 6 Gelir Tablosu Hesapları ---
  PostingAccount('600.01', 'Mamul Satışları'),
  PostingAccount('600.02', 'Ticari Mal Satışları'),
  PostingAccount('600.03', 'Hizmet Satışları'),
  PostingAccount('601.01', 'İhracat Satışları'),
  PostingAccount('610.01', 'Satıştan İadeler'),
  PostingAccount('621.01', 'Satılan Ticari Mallar Maliyeti'),
  PostingAccount('632.01', 'Genel Yönetim Giderleri'),
  PostingAccount('642.01', 'Mevduat Faiz Gelirleri'),
  PostingAccount('649.01', 'Kur Farkı Gelirleri'),
  PostingAccount('656.01', 'Kambiyo Zararları'),
  // --- 7 Maliyet Hesapları ---
  PostingAccount('760.01', 'Reklam ve Tanıtım Giderleri'),
  PostingAccount('760.02', 'Nakliye Giderleri'),
  PostingAccount('770.01', 'Personel Ücretleri'),
  PostingAccount('770.02', 'Kira Giderleri'),
  PostingAccount('770.03', 'Elektrik, Su ve Doğalgaz'),
  PostingAccount('770.04', 'Haberleşme Giderleri'),
  PostingAccount('770.05', 'Amortisman Giderleri'),
  PostingAccount('770.06', 'Denetim ve Müşavirlik'),
  PostingAccount('770.07', 'Vergi, Resim ve Harçlar'),
  PostingAccount('780.01', 'Kredi Faizleri'),
  PostingAccount('780.02', 'Banka Masrafları'),
];
