// Binding data: rows from JSON or from your own objects, grouped by region
// with a subtotal per group, a grand total, and page numbers.
import 'package:jet_print/jet_print.dart';

/// The shape of one row. Declaring it lets `validate` check every binding.
const JetDataSchema salesSchema = JetDataSchema(
  name: 'Orders',
  fields: <FieldDef>[
    FieldDef('region', type: JetFieldType.string),
    FieldDef('customer', type: JetFieldType.string),
    FieldDef('amount', type: JetFieldType.double),
  ],
);

/// Rows straight from JSON. Groups break when the key changes, so the rows
/// arrive sorted by region.
final JetDataSource ordersFromJson = JetJsonDataSource.parse(
  '''
  [
    {"region": "North", "customer": "Ada", "amount": 120.5},
    {"region": "North", "customer": "Grace", "amount": 80},
    {"region": "South", "customer": "Linus", "amount": 42.25}
  ]
  ''',
  fields: salesSchema.fields,
);

/// The same rows from your own classes.
class Order {
  /// Creates an order.
  const Order(this.region, this.customer, this.amount);

  /// The sales region; the report groups on it.
  final String region;

  /// Who placed the order.
  final String customer;

  /// The order total.
  final double amount;
}

/// Maps each [Order] to a row lazily, as the report reads it.
final JetDataSource ordersFromObjects = JetObjectDataSource<Order>(
  const <Order>[
    Order('North', 'Ada', 120.5),
    Order('North', 'Grace', 80),
    Order('South', 'Linus', 42.25),
  ],
  fields: salesSchema.fields,
  row: (Order o) => <String, Object?>{
    'region': o.region,
    'customer': o.customer,
    'amount': o.amount,
  },
);

/// One group per region, each closed by a subtotal, then a grand total.
const ReportDefinition salesByRegion = ReportDefinition(
  name: 'Sales by region',
  page: PageFormat.a4Portrait,
  furniture: PageFurniture(
    pageFooter: Band(
      id: 'pageFooter',
      type: BandType.pageFooter,
      height: 20,
      elements: <ReportElement>[
        TextElement(
          id: 'pageNumber',
          bounds: JetRect(x: 0, y: 0, width: 200, height: 16),
          text: '',
          expression: r'"Page " + $V{PAGE_NUMBER} + " of " + $V{PAGE_COUNT}',
        ),
      ],
    ),
  ),
  body: ReportBody(
    root: DetailScope(
      id: 'root',
      groups: <GroupLevel>[
        GroupLevel(
          id: 'region',
          name: 'Region',
          key: r'$F{region}',
          header: Band(
            id: 'regionHeader',
            type: BandType.groupHeader,
            height: 24,
            elements: <ReportElement>[
              TextElement(
                id: 'regionName',
                bounds: JetRect(x: 0, y: 0, width: 200, height: 20),
                text: '',
                expression: r'$F{region}',
                style: JetTextStyle(weight: JetFontWeight.bold),
              ),
            ],
          ),
          footer: Band(
            id: 'regionFooter',
            type: BandType.groupFooter,
            height: 24,
            elements: <ReportElement>[
              TextElement(
                id: 'subtotal',
                bounds: JetRect(x: 300, y: 0, width: 100, height: 20),
                text: '',
                expression: r'SUM($F{amount})',
                format: '#,##0.00',
              ),
            ],
          ),
        ),
      ],
      children: <ScopeNode>[
        BandNode(Band(
          id: 'detail',
          type: BandType.detail,
          height: 20,
          elements: <ReportElement>[
            TextElement(
              id: 'customer',
              bounds: JetRect(x: 16, y: 0, width: 200, height: 16),
              text: '',
              expression: r'$F{customer}',
            ),
            TextElement(
              id: 'amount',
              bounds: JetRect(x: 300, y: 0, width: 100, height: 16),
              text: '',
              expression: r'$F{amount}',
              format: '#,##0.00',
            ),
          ],
        )),
      ],
    ),
    summary: Band(
      id: 'summary',
      type: BandType.summary,
      height: 24,
      elements: <ReportElement>[
        TextElement(
          id: 'grandTotal',
          bounds: JetRect(x: 300, y: 0, width: 100, height: 20),
          text: '',
          expression: r'SUM($F{amount})',
          format: '#,##0.00',
          style: JetTextStyle(weight: JetFontWeight.bold),
        ),
      ],
    ),
  ),
);

/// Fills [salesByRegion] from any of the sources above.
RenderedReport renderSales(JetDataSource source) =>
    const JetReportEngine().renderDefinition(salesByRegion, source);
