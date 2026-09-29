import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DatabaseHelper.instance.database;
  runApp(const TaksitTakipApp());
}

class TaksitTakipApp extends StatelessWidget {
  const TaksitTakipApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Taksit Takip',
      theme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.orange,
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class DatabaseHelper {
  DatabaseHelper._();
  static final DatabaseHelper instance = DatabaseHelper._();

  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;

    final path = join(
      await getDatabasesPath(),
      'taksit_takip.db',
    );

    _database = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE customers(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            phone TEXT,
            plate TEXT,
            total REAL NOT NULL,
            installment REAL NOT NULL,
            paymentDay INTEGER,
            note TEXT
          )
        ''');

        await db.execute('''
          CREATE TABLE payments(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            customerId INTEGER NOT NULL,
            amount REAL NOT NULL,
            date TEXT NOT NULL
          )
        ''');
      },
    );

    return _database!;
  }

  Future<List<Map<String, dynamic>>> customers() async {
    final db = await database;

    return db.rawQuery('''
      SELECT c.*,
      COALESCE(SUM(p.amount), 0) AS paid
      FROM customers c
      LEFT JOIN payments p ON c.id = p.customerId
      GROUP BY c.id
      ORDER BY c.name
    ''');
  }

  Future<int> addCustomer(Map<String, dynamic> data) async {
    final db = await database;
    return db.insert('customers', data);
  }

  Future<int> addPayment(
      int customerId,
      double amount,
      ) async {
    final db = await database;

    return db.insert('payments', {
      'customerId': customerId,
      'amount': amount,
      'date': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> payments(
      int customerId,
      ) async {
    final db = await database;

    return db.query(
      'payments',
      where: 'customerId = ?',
      whereArgs: [customerId],
      orderBy: 'date DESC',
    );
  }

  Future<void> deleteCustomer(int id) async {
    final db = await database;

    await db.delete(
      'payments',
      where: 'customerId = ?',
      whereArgs: [id],
    );

    await db.delete(
      'customers',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Map<String, dynamic>> customers = [];
  String search = '';

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    customers = await DatabaseHelper.instance.customers();

    if (mounted) {
      setState(() {});
    }
  }

  double get totalDebt {
    return customers.fold(
      0,
      (sum, c) => sum + (c['total'] as num).toDouble(),
    );
  }

  double get totalPaid {
    return customers.fold(
      0,
      (sum, c) => sum + (c['paid'] as num).toDouble(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = customers.where((c) {
      final q = search.toLowerCase();

      return c['name'].toString().toLowerCase().contains(q) ||
          (c['plate'] ?? '')
              .toString()
              .toLowerCase()
              .contains(q) ||
          (c['phone'] ?? '')
              .toString()
              .toLowerCase()
              .contains(q);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'TAKSİT TAKİP',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const AddCustomerPage(),
            ),
          );

          load();
        },
        icon: const Icon(Icons.person_add),
        label: const Text('Müşteri Ekle'),
      ),
      body: RefreshIndicator(
        onRefresh: load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(
                  child: SummaryCard(
                    title: 'Toplam Alacak',
                    value: totalDebt,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SummaryCard(
                    title: 'Tahsil Edilen',
                    value: totalPaid,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SummaryCard(
              title: 'Kalan Alacak',
              value: totalDebt - totalPaid,
            ),
            const SizedBox(height: 18),
            TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'İsim, plaka veya telefon ara',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                setState(() {
                  search = value;
                });
              },
            ),
            const SizedBox(height: 18),
            if (filtered.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 60),
                child: Center(
                  child: Text(
                    'Henüz müşteri bulunmuyor.',
                    style: TextStyle(fontSize: 17),
                  ),
                ),
              ),
            ...filtered.map((c) {
              final total =
                  (c['total'] as num).toDouble();

              final paid =
                  (c['paid'] as num).toDouble();

              final remaining = total - paid;

              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: CircleAvatar(
                    child: Text(
                      c['name']
                          .toString()
                          .substring(0, 1)
                          .toUpperCase(),
                    ),
                  ),
                  title: Text(
                    c['name'],
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Text(
                    '${c['plate'] ?? '-'}\n'
                    'Kalan: ${money(remaining)}',
                  ),
                  isThreeLine: true,
                  trailing:
                      const Icon(Icons.chevron_right),
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            CustomerPage(customer: c),
                      ),
                    );

                    load();
                  },
                ),
              );
            }),
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }
}

class SummaryCard extends StatelessWidget {
  final String title;
  final double value;

  const SummaryCard({
    super.key,
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 7),
            Text(
              money(value),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AddCustomerPage extends StatefulWidget {
  const AddCustomerPage({super.key});

  @override
  State<AddCustomerPage> createState() =>
      _AddCustomerPageState();
}

class _AddCustomerPageState
    extends State<AddCustomerPage> {
  final name = TextEditingController();
  final phone = TextEditingController();
  final plate = TextEditingController();
  final total = TextEditingController();
  final installment = TextEditingController();
  final paymentDay = TextEditingController();
  final note = TextEditingController();

  Future<void> save() async {
    if (name.text.trim().isEmpty ||
        double.tryParse(
              total.text.replaceAll(',', '.'),
            ) ==
            null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Ad Soyad ve toplam borç zorunludur.',
          ),
        ),
      );
      return;
    }

    await DatabaseHelper.instance.addCustomer({
      'name': name.text.trim(),
      'phone': phone.text.trim(),
      'plate': plate.text.trim().toUpperCase(),
      'total':
          double.parse(total.text.replaceAll(',', '.')),
      'installment':
          double.tryParse(
            installment.text.replaceAll(',', '.'),
          ) ??
          0,
      'paymentDay':
          int.tryParse(paymentDay.text.trim()),
      'note': note.text.trim(),
    });

    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar:
          AppBar(title: const Text('Yeni Müşteri')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          field(name, 'Ad Soyad', Icons.person),
          field(phone, 'Telefon', Icons.phone,
              keyboard: TextInputType.phone),
          field(plate, 'Araç Plakası',
              Icons.directions_car),
          field(
            total,
            'Toplam Borç',
            Icons.account_balance_wallet,
            keyboard:
                const TextInputType.numberWithOptions(
              decimal: true,
            ),
          ),
          field(
            installment,
            'Aylık Taksit',
            Icons.payments,
            keyboard:
                const TextInputType.numberWithOptions(
              decimal: true,
            ),
          ),
          field(
            paymentDay,
            'Ödeme Günü (1-31)',
            Icons.calendar_month,
            keyboard: TextInputType.number,
          ),
          TextField(
            controller: note,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Açıklama',
              prefixIcon: Icon(Icons.notes),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: save,
            icon: const Icon(Icons.save),
            label: const Padding(
              padding: EdgeInsets.all(14),
              child: Text('Müşteriyi Kaydet'),
            ),
          ),
        ],
      ),
    );
  }

  Widget field(
    TextEditingController controller,
    String label,
    IconData icon, {
    TextInputType? keyboard,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: keyboard,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}

class CustomerPage extends StatefulWidget {
  final Map<String, dynamic> customer;

  const CustomerPage({
    super.key,
    required this.customer,
  });

  @override
  State<CustomerPage> createState() =>
      _CustomerPageState();
}

class _CustomerPageState extends State<CustomerPage> {
  List<Map<String, dynamic>> paymentList = [];

  @override
  void initState() {
    super.initState();
    loadPayments();
  }

  Future<void> loadPayments() async {
    paymentList =
        await DatabaseHelper.instance.payments(
      widget.customer['id'],
    );

    if (mounted) {
      setState(() {});
    }
  }

  double get paid {
    return paymentList.fold(
      0,
      (sum, p) =>
          sum + (p['amount'] as num).toDouble(),
    );
  }

  Future<void> addPayment() async {
    final controller = TextEditingController();

    final amount = await showDialog<double>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Ödeme Ekle'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType:
                const TextInputType.numberWithOptions(
              decimal: true,
            ),
            decoration: const InputDecoration(
              labelText: 'Ödeme Tutarı',
              prefixText: '₺ ',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(context),
              child: const Text('İptal'),
            ),
            FilledButton(
              onPressed: () {
                final value = double.tryParse(
                  controller.text.replaceAll(',', '.'),
                );

                if (value != null && value > 0) {
                  Navigator.pop(context, value);
                }
              },
              child: const Text('Kaydet'),
            ),
          ],
        );
      },
    );

    if (amount != null) {
      await DatabaseHelper.instance.addPayment(
        widget.customer['id'],
        amount,
      );

      loadPayments();
    }
  }

  @override
  Widget build(BuildContext context) {
    final total =
        (widget.customer['total'] as num).toDouble();

    final remaining = total - paid;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.customer['name']),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              final delete = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title:
                      const Text('Müşteriyi Sil'),
                  content: const Text(
                    'Müşteri ve ödeme geçmişi silinecek. '
                    'Devam edilsin mi?',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () =>
                          Navigator.pop(
                              context, false),
                      child: const Text('İptal'),
                    ),
                    FilledButton(
                      onPressed: () =>
                          Navigator.pop(
                              context, true),
                      child: const Text('Sil'),
                    ),
                  ],
                ),
              );

              if (delete == true) {
                await DatabaseHelper.instance
                    .deleteCustomer(
                  widget.customer['id'],
                );

                if (mounted) {
                  Navigator.pop(context);
                }
              }
            },
          ),
        ],
      ),
      floatingActionButton:
          FloatingActionButton.extended(
        onPressed: addPayment,
        icon: const Icon(Icons.add_card),
        label: const Text('Ödeme Ekle'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            widget.customer['name'],
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Telefon: '
            '${widget.customer['phone'] ?? '-'}',
          ),
          Text(
            'Plaka: '
            '${widget.customer['plate'] ?? '-'}',
          ),
          Text(
            'Ödeme günü: '
            '${widget.customer['paymentDay'] ?? '-'}',
          ),
          const SizedBox(height: 18),
          SummaryCard(
            title: 'Toplam Borç',
            value: total,
          ),
          SummaryCard(
            title: 'Ödenen',
            value: paid,
          ),
          SummaryCard(
            title: 'Kalan',
            value: remaining,
          ),
          const SizedBox(height: 15),
          if ((widget.customer['note'] ?? '')
              .toString()
              .isNotEmpty) ...[
            const Text(
              'Açıklama',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 5),
            Text(widget.customer['note']),
            const SizedBox(height: 20),
          ],
          const Text(
            'Ödeme Geçmişi',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          if (paymentList.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(18),
                child: Text(
                  'Henüz ödeme kaydı yok.',
                ),
              ),
            ),
          ...paymentList.map((p) {
            final date =
                DateTime.parse(p['date']).toLocal();

            return Card(
              child: ListTile(
                leading:
                    const Icon(Icons.check_circle),
                title: Text(
                  money(
                    (p['amount'] as num).toDouble(),
                  ),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: Text(
                  '${date.day.toString().padLeft(2, '0')}.'
                  '${date.month.toString().padLeft(2, '0')}.'
                  '${date.year}',
                ),
              ),
            );
          }),
          const SizedBox(height: 100),
        ],
      ),
    );
  }
}

String money(double value) {
  return '₺${value.toStringAsFixed(2)}';
}
