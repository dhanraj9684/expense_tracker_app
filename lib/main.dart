import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:telephony/telephony.dart';
import 'dart:convert';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  runApp(UrbanExpenseTracker());
}

class UrbanExpenseTracker extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Urban Expense Tracker',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Expense> _expenses = [];
  double _totalToday = 0;
  double _totalWeek = 0;
  int _selectedIndex = 0; // 0: List, 1: Chart
  
  // Budget variables
  double _weeklyBudget = 5000;
  bool _showBudgetAlert = false;
  String _alertMessage = '';
  
  // NEW: Track imported SMS to avoid duplicates
  Set<String> _importedSmsIds = {};

  @override
  void initState() {
    super.initState();
    _loadExpenses();
    _loadBudget();
  }

  Future<void> _loadBudget() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _weeklyBudget = prefs.getDouble('weeklyBudget') ?? 5000;
    });
  }

  Future<void> _saveBudget(double budget) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('weeklyBudget', budget);
  }

  void _checkBudgetAlert() {
    double spent = _totalWeek;
    double remaining = _weeklyBudget - spent;
    double percentage = (spent / _weeklyBudget) * 100;

    if (spent >= _weeklyBudget && _weeklyBudget > 0) {
      _showAlert(
        'Budget Exceeded! 🚨',
        'You have exceeded your weekly budget of ₹${_weeklyBudget.toStringAsFixed(2)}! Spent: ₹${spent.toStringAsFixed(2)}',
      );
      setState(() {
        _showBudgetAlert = true;
        _alertMessage = '⚠️ Budget exceeded! You spent ₹${spent.toStringAsFixed(2)} / ₹${_weeklyBudget.toStringAsFixed(2)}';
      });
    } else if (percentage >= 90 && _weeklyBudget > 0) {
      _showAlert(
        'Budget Alert! ⚠️',
        'You have used ${percentage.toStringAsFixed(0)}% of your weekly budget. Remaining: ₹${remaining.toStringAsFixed(2)}',
      );
      setState(() {
        _showBudgetAlert = true;
        _alertMessage = '⚠️ Budget alert! Used ${percentage.toStringAsFixed(0)}% of ₹${_weeklyBudget.toStringAsFixed(2)}';
      });
    } else if (percentage >= 75 && _weeklyBudget > 0) {
      _showAlert(
        'Budget Warning! 📊',
        'You have used ${percentage.toStringAsFixed(0)}% of your weekly budget. Remaining: ₹${remaining.toStringAsFixed(2)}',
      );
      setState(() {
        _showBudgetAlert = true;
        _alertMessage = '📊 Budget warning: Used ${percentage.toStringAsFixed(0)}%';
      });
    } else {
      setState(() {
        _showBudgetAlert = false;
        _alertMessage = '';
      });
    }
  }

  Future<void> _showAlert(String title, String body) async {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(body),
          backgroundColor: title.contains('Exceeded') ? Colors.red : Colors.orange,
          duration: Duration(seconds: 5),
          action: SnackBarAction(
            label: 'OK',
            onPressed: () {},
            textColor: Colors.white,
          ),
        ),
      );
    }
  }

  void _showSetBudgetDialog() {
    final TextEditingController _budgetController = 
        TextEditingController(text: _weeklyBudget.toString());

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Set Weekly Budget'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Current weekly spending: ₹${_totalWeek.toStringAsFixed(2)}'),
            SizedBox(height: 16),
            TextField(
              controller: _budgetController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Weekly Budget (₹)',
                prefixIcon: Icon(Icons.currency_rupee),
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              double newBudget = double.tryParse(_budgetController.text) ?? 5000;
              setState(() {
                _weeklyBudget = newBudget;
                _saveBudget(newBudget);
              });
              _checkBudgetAlert();
              Navigator.pop(context);
            },
            child: Text('Save'),
          ),
        ],
      ),
    );
  }

  // ==================== SMS AUTO-IMPORT ====================
  
  Future<void> _requestSmsPermission() async {
    if (kIsWeb) {
      _showAlert('Not Available', 'SMS import works only on Android devices');
      return;
    }
    
    var status = await Permission.sms.status;
    if (!status.isGranted) {
      status = await Permission.sms.request();
    }
    
    if (status.isGranted) {
      await _importFromSMS();
    } else {
      _showAlert('Permission Required', 'SMS permission is needed to auto-import expenses from bank messages');
    }
  }

  // NEW: Helper method to save SMS IDs
  Future<void> _saveSmsIds() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('importedSmsIds', json.encode(_importedSmsIds.toList()));
  }

 Future<void> _importFromSMS() async {
  // Show loading indicator
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Scanning today\'s SMS...'), duration: Duration(seconds: 1)),
  );
  
  try {
    final Telephony telephony = Telephony.instance;
    final List<SmsMessage> messages = await telephony.getInboxSms();
    
    // Get today's start time (12:00 AM)
    DateTime now = DateTime.now();
    DateTime todayStart = DateTime(now.year, now.month, now.day);
    
    // Keywords that indicate a transaction
    List<String> transactionKeywords = [
      'debited', 'credited', 'spent', 'paid', 'UPI', 'GPay',
      'PhonePe', 'Paytm', 'HDFC', 'SBI', 'ICICI', 'AXIS', 'PNB',
      'transaction', 'payment', 'received', 'sent'
    ];
    
    int importedCount = 0;
    int todaySmsCount = 0;
    
    for (var sms in messages) {
      // Check if SMS is from today
      DateTime smsDate = DateTime.fromMillisecondsSinceEpoch(sms.date ?? 0);
      if (smsDate.isBefore(todayStart)) {
        continue;  // Skip messages from yesterday or earlier
      }
      
      todaySmsCount++;
      
      String smsId = sms.id?.toString() ?? '';
      
      // Skip if already imported
      if (_importedSmsIds.contains(smsId)) {
        continue;
      }
      
      String body = sms.body?.toLowerCase() ?? '';
      
      // Check if this is a transaction SMS
      bool isTransaction = transactionKeywords.any((kw) => body.contains(kw.toLowerCase()));
      
      if (isTransaction) {
        // Extract amount using regex
        RegExp amountRegex = RegExp(r'(?:rs\.?|inr|₹)\s*(\d+(?:\.\d{1,2})?)', caseSensitive: false);
        Match? amountMatch = amountRegex.firstMatch(body);
        double amount = amountMatch != null ? double.tryParse(amountMatch.group(1)!) ?? 0 : 0;
        
        // If amount not found, try alternative pattern
        if (amount == 0) {
          RegExp altRegex = RegExp(r'(\d+(?:\.\d{1,2})?)\s*(?:rs\.?|inr|₹)', caseSensitive: false);
          Match? altMatch = altRegex.firstMatch(body);
          amount = altMatch != null ? double.tryParse(altMatch.group(1)!) ?? 0 : 0;
        }
        
        if (amount > 0) {
          // Extract merchant name
          String merchant = 'Unknown';
          if (body.contains('to ')) {
            int toIndex = body.indexOf('to ');
            int endIndex = body.indexOf(' ', toIndex + 3);
            merchant = body.substring(toIndex + 3, endIndex > 0 ? endIndex : body.length);
          } else if (body.contains('at ')) {
            int atIndex = body.indexOf('at ');
            int endIndex = body.indexOf(' ', atIndex + 3);
            merchant = body.substring(atIndex + 3, endIndex > 0 ? endIndex : body.length);
          } else if (body.contains('from ')) {
            int fromIndex = body.indexOf('from ');
            int endIndex = body.indexOf(' ', fromIndex + 5);
            merchant = body.substring(fromIndex + 5, endIndex > 0 ? endIndex : body.length);
          }
          
          merchant = merchant.substring(0, merchant.length > 20 ? 20 : merchant.length);
          
          _addExpense(Expense(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            description: merchant,
            amount: amount,
            category: _categorizeMerchant(merchant),
            date: DateTime.now(),
          ));
          
          // Mark this SMS as imported
          _importedSmsIds.add(smsId);
          importedCount++;
        }
      }
    }
    
    // Save the updated SMS IDs
    await _saveSmsIds();
    
    _showAlert('Import Complete', 
      'Found ${todaySmsCount} SMS from today\n'
      'Imported $importedCount new expenses');
    
  } catch (e) {
    _showAlert('Error', 'Failed to read SMS: $e');
  }
}

  String _categorizeMerchant(String merchant) {
    String lower = merchant.toLowerCase();
    
    Map<String, List<String>> keywords = {
      'Food': ['zomato', 'swiggy', 'restaurant', 'cafe', 'starbucks', 'dominos', 'pizza', 'kfc', 'mcdonalds', 'food'],
      'Transport': ['uber', 'ola', 'metro', 'bus', 'petrol', 'fuel', 'rapido', 'taxi', 'railway'],
      'Shopping': ['amazon', 'flipkart', 'myntra', 'ajio', 'nykaa', 'shopping', 'mall'],
      'Entertainment': ['netflix', 'prime', 'hotstar', 'bookmyshow', 'cinema', 'movie'],
      'Bills': ['electricity', 'water', 'broadband', 'recharge', 'mobile', 'wifi', 'bill'],
      'Parking': ['parking', 'toll'],
    };
    
    for (var entry in keywords.entries) {
      if (entry.value.any((kw) => lower.contains(kw))) {
        return entry.key;
      }
    }
    return 'Other';
  }

  // ==================== EXISTING EXPENSE METHODS ====================

  void _loadExpenses() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    
    // Load expenses
    String? expensesJson = prefs.getString('expenses');
    if (expensesJson != null) {
      List<dynamic> decoded = json.decode(expensesJson);
      setState(() {
        _expenses = decoded.map((e) => Expense.fromJson(e)).toList();
        _calculateTotals();
      });
    }
    
    // NEW: Load imported SMS IDs
    String? smsIdsJson = prefs.getString('importedSmsIds');
    if (smsIdsJson != null) {
      List<String> decodedIds = List<String>.from(json.decode(smsIdsJson));
      setState(() {
        _importedSmsIds = decodedIds.toSet();
      });
    }
  }

  void _saveExpenses() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    
    // Save expenses
    List<Map<String, dynamic>> jsonList = _expenses.map((e) => e.toJson()).toList();
    await prefs.setString('expenses', json.encode(jsonList));
    
    // NEW: Save imported SMS IDs along with expenses
    await prefs.setString('importedSmsIds', json.encode(_importedSmsIds.toList()));
    
    _calculateTotals();
  }

  void _calculateTotals() {
    DateTime now = DateTime.now();
    DateTime today = DateTime(now.year, now.month, now.day);
    DateTime weekAgo = today.subtract(Duration(days: 7));

    _totalToday = _expenses
        .where((e) => e.date.isAfter(today) || e.date.isAtSameMomentAs(today))
        .fold(0, (sum, e) => sum + e.amount);

    double newTotalWeek = _expenses
        .where((e) => e.date.isAfter(weekAgo))
        .fold(0, (sum, e) => sum + e.amount);
    
    if ((newTotalWeek - _totalWeek).abs() > 0.01) {
      _totalWeek = newTotalWeek;
      _checkBudgetAlert();
    } else {
      _totalWeek = newTotalWeek;
    }
  }

  void _addExpense(Expense expense) {
    setState(() {
      _expenses.add(expense);
      _saveExpenses();
    });
  }

  void _deleteExpense(int index) {
    setState(() {
      _expenses.removeAt(index);
      _saveExpenses();
    });
  }

  void _showEditExpenseDialog(Expense expense, int index) {
    String _newCategory = expense.category;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit Expense'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Merchant: ${expense.description}'),
            Text('Amount: ₹${expense.amount.toStringAsFixed(2)}'),
            SizedBox(height: 16),
            DropdownButtonFormField(
              value: _newCategory,
              items: ['Transport', 'Food', 'Shopping', 'Parking', 'Entertainment', 'Bills', 'Other']
                  .map((cat) => DropdownMenuItem(value: cat, child: Text(cat)))
                  .toList(),
              onChanged: (value) => _newCategory = value!,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _expenses[index] = Expense(
                  id: expense.id,
                  description: expense.description,
                  amount: expense.amount,
                  category: _newCategory,
                  date: expense.date,
                );
                _saveExpenses();
              });
              Navigator.pop(context);
            },
            child: Text('Save'),
          ),
        ],
      ),
    );
  }

  List<WeeklyExpense> _getWeeklyExpenses() {
    List<WeeklyExpense> weeklyData = [];
    DateTime now = DateTime.now();
    
    for (int i = 6; i >= 0; i--) {
      DateTime day = DateTime(now.year, now.month, now.day - i);
      double dailyTotal = _expenses
          .where((e) => 
              e.date.year == day.year && 
              e.date.month == day.month && 
              e.date.day == day.day)
          .fold(0, (sum, e) => sum + e.amount);
      
      weeklyData.add(WeeklyExpense(
        day: day,
        amount: dailyTotal,
        dayName: DateFormat('EEE').format(day),
      ));
    }
    return weeklyData;
  }

  // ==================== UI BUILD ====================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Urban Expense Tracker'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(Icons.sms),
            onPressed: _requestSmsPermission,
            tooltip: 'Import from SMS',
          ),
          IconButton(
            icon: Icon(Icons.attach_money),
            onPressed: _showSetBudgetDialog,
            tooltip: 'Set Weekly Budget',
          ),
          IconButton(
            icon: Icon(_selectedIndex == 0 ? Icons.bar_chart : Icons.list),
            onPressed: () {
              setState(() {
                _selectedIndex = _selectedIndex == 0 ? 1 : 0;
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Budget Progress Bar
          Container(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Card(
              elevation: 4,
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Weekly Budget', style: TextStyle(fontWeight: FontWeight.bold)),
                        Text(
                          '₹${_totalWeek.toStringAsFixed(2)} / ₹${_weeklyBudget.toStringAsFixed(2)}',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: _weeklyBudget > 0 ? (_totalWeek / _weeklyBudget).clamp(0.0, 1.0) : 0.0,
                      backgroundColor: Colors.grey.shade200,
                      color: _totalWeek >= _weeklyBudget 
                          ? Colors.red 
                          : (_totalWeek / _weeklyBudget) >= 0.9 
                              ? Colors.orange 
                              : Colors.green,
                      minHeight: 10,
                    ),
                    if (_showBudgetAlert) ...[
                      SizedBox(height: 8),
                      Text(_alertMessage, style: TextStyle(color: Colors.red, fontSize: 12)),
                    ],
                  ],
                ),
              ),
            ),
          ),
          // Stats Cards
          Container(
            padding: EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Card(
                    color: Colors.blue.shade50,
                    elevation: 4,
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Text('Today', style: TextStyle(color: Colors.grey[600])),
                          SizedBox(height: 8),
                          Text(
                            '₹${_totalToday.toStringAsFixed(2)}',
                            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.blue.shade700),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: Card(
                    color: _totalWeek >= _weeklyBudget && _weeklyBudget > 0 ? Colors.red.shade50 : Colors.green.shade50,
                    elevation: 4,
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Text('Remaining', style: TextStyle(color: Colors.grey[600])),
                          SizedBox(height: 8),
                          Text(
                            '₹${(_weeklyBudget - _totalWeek).clamp(0.0, double.infinity).toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: (_totalWeek >= _weeklyBudget && _weeklyBudget > 0) ? Colors.red.shade700 : Colors.green.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Main content
          Expanded(
            child: _selectedIndex == 0 ? _buildExpenseList() : _buildChart(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddExpenseDialog(),
        child: Icon(Icons.add),
      ),
    );
  }

  Widget _buildExpenseList() {
    return _expenses.isEmpty
        ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.receipt_long, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text('No expenses yet', style: TextStyle(color: Colors.grey, fontSize: 16)),
                SizedBox(height: 8),
                Text('Tap + or use SMS import', style: TextStyle(color: Colors.grey)),
              ],
            ),
          )
        : ListView.builder(
            itemCount: _expenses.length,
            itemBuilder: (context, index) {
              final expense = _expenses[index];
              return Dismissible(
                key: Key(expense.id),
                background: Container(
                  color: Colors.red,
                  alignment: Alignment.centerRight,
                  padding: EdgeInsets.only(right: 20),
                  child: Icon(Icons.delete, color: Colors.white),
                ),
                onDismissed: (_) => _deleteExpense(index),
                child: Card(
                  margin: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: _getColorForCategory(expense.category),
                      child: Icon(_getIconForCategory(expense.category), color: Colors.white),
                    ),
                    title: Text(expense.description, style: TextStyle(fontWeight: FontWeight.w500)),
                    subtitle: Text('${DateFormat('MMM dd, yyyy').format(expense.date)} • ${expense.category}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(Icons.edit, size: 20),
                          onPressed: () => _showEditExpenseDialog(expense, index),
                        ),
                        Text(
                          '₹${expense.amount.toStringAsFixed(2)}',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue.shade700),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
  }

  Widget _buildChart() {
  List<WeeklyExpense> weeklyData = _getWeeklyExpenses();
  if (weeklyData.isEmpty) {
    return Center(child: Text('No data to display'));
  }
  
  double maxAmount = weeklyData.map((e) => e.amount).reduce((a, b) => a > b ? a : b);
  double safeMaxY = maxAmount == 0 ? 1000 : maxAmount * 1.3; // Add 30% headroom
  
  return Padding(
    padding: EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          elevation: 4,
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Weekly Expenditure', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade100,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text('Last 7 Days', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                    ),
                  ],
                ),
                SizedBox(height: 24),
                SizedBox(
                  height: 300,
                  child: BarChart(
                    BarChartData(
                      alignment: BarChartAlignment.spaceAround,
                      maxY: safeMaxY,  // FIXED: More headroom
                      minY: 0,  // FIXED: Explicit min
                      barTouchData: BarTouchData(
                        enabled: true,
                        touchTooltipData: BarTouchTooltipData(
                          getTooltipItem: (group, groupIndex, rod, rodIndex) {
                            return BarTooltipItem(
                              '₹${rod.toY.toStringAsFixed(2)}',
                              TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            );
                          },
                        ),
                      ),
                      titlesData: FlTitlesData(
                        show: true,
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (double value, TitleMeta meta) {
                              int index = value.toInt();
                              if (index >= 0 && index < weeklyData.length) {
                                return Padding(
                                  padding: EdgeInsets.only(top: 8),
                                  child: Text(weeklyData[index].dayName, style: TextStyle(fontSize: 12)),
                                );
                              }
                              return Text('');
                            },
                            reservedSize: 30,
                          ),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (double value, TitleMeta meta) {
                              return Text('₹${value.toInt()}', style: TextStyle(fontSize: 10));
                            },
                            reservedSize: 50,  // FIXED: Increased from 40
                          ),
                        ),
                        topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      ),
                      borderData: FlBorderData(show: false),
                      gridData: FlGridData(
                        show: true,
                        drawHorizontalLine: true,
                        drawVerticalLine: false,
                        horizontalInterval: safeMaxY / 5,  // FIXED: Use safeMaxY
                      ),
                      barGroups: List.generate(weeklyData.length, (index) {
                        return BarChartGroupData(
                          x: index,
                          barRods: [
                            BarChartRodData(
                              toY: weeklyData[index].amount,
                              color: _getChartColor(weeklyData[index].amount, maxAmount),
                              width: 35,  // FIXED: Slightly wider
                              borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
                              backDrawRodData: BackgroundBarChartRodData(
                                show: true,
                                toY: safeMaxY,
                                color: Colors.grey.shade200,
                              ),
                            ),
                          ],
                        );
                      }),
                    ),
                  ),
                ),
                SizedBox(height: 16),
                Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildChartLegend('Low', Colors.green),
                    _buildChartLegend('Medium', Colors.orange),
                    _buildChartLegend('High', Colors.red),
                  ],
                ),
              ],
            ),
          ),
        ),
        // ... rest of your code
      ],
    ),
  );
}
  void _showAddExpenseDialog() {
    final _formKey = GlobalKey<FormState>();
    String _description = '';
    double _amount = 0;
    String _category = 'Transport';
    DateTime _date = DateTime.now();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Add Expense'),
        content: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                decoration: InputDecoration(labelText: 'Description', prefixIcon: Icon(Icons.description), border: OutlineInputBorder()),
                onChanged: (value) => _description = value,
                validator: (value) => value!.isEmpty ? 'Required' : null,
              ),
              SizedBox(height: 12),
              TextFormField(
                decoration: InputDecoration(labelText: 'Amount (₹)', prefixIcon: Icon(Icons.currency_rupee), border: OutlineInputBorder()),
                keyboardType: TextInputType.number,
                onChanged: (value) => _amount = double.tryParse(value) ?? 0,
                validator: (value) => value!.isEmpty ? 'Required' : null,
              ),
              SizedBox(height: 12),
              DropdownButtonFormField(
                value: _category,
                decoration: InputDecoration(labelText: 'Category', prefixIcon: Icon(Icons.category), border: OutlineInputBorder()),
                items: ['Transport', 'Food', 'Shopping', 'Parking', 'Entertainment', 'Bills', 'Other'].map((cat) => DropdownMenuItem(value: cat, child: Text(cat))).toList(),
                onChanged: (value) => _category = value!,
              ),
              SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Date'),
                subtitle: Text(DateFormat('MMM dd, yyyy').format(_date)),
                trailing: Icon(Icons.calendar_today),
                onTap: () async {
                  DateTime? picked = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(2024), lastDate: DateTime.now());
                  if (picked != null) _date = picked;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (_formKey.currentState!.validate()) {
                _addExpense(Expense(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  description: _description,
                  amount: _amount,
                  category: _category,
                  date: _date,
                ));
                Navigator.pop(context);
              }
            },
            child: Text('Save'),
          ),
        ],
      ),
    );
  }

  Widget _buildChartLegend(String label, Color color) {
    return Row(children: [Container(width: 16, height: 16, color: color), SizedBox(width: 4), Text(label, style: TextStyle(fontSize: 12))]);
  }

  Color _getChartColor(double amount, double maxAmount) {
    if (maxAmount == 0) return Colors.blue;
    double ratio = amount / maxAmount;
    if (ratio < 0.33) return Colors.green;
    if (ratio < 0.66) return Colors.orange;
    return Colors.red;
  }

  IconData _getIconForCategory(String category) {
    switch (category) {
      case 'Transport': return Icons.directions_bus;
      case 'Food': return Icons.restaurant;
      case 'Shopping': return Icons.shopping_bag;
      case 'Parking': return Icons.local_parking;
      case 'Entertainment': return Icons.movie;
      case 'Bills': return Icons.receipt;
      default: return Icons.attach_money;
    }
  }

  Color _getColorForCategory(String category) {
    switch (category) {
      case 'Transport': return Colors.blue;
      case 'Food': return Colors.orange;
      case 'Shopping': return Colors.purple;
      case 'Parking': return Colors.red;
      case 'Entertainment': return Colors.deepPurple;
      case 'Bills': return Colors.teal;
      default: return Colors.grey;
    }
  }
}

// ==================== DATA MODELS ====================

class Expense {
  String id;
  String description;
  double amount;
  String category;
  DateTime date;

  Expense({
    required this.id,
    required this.description,
    required this.amount,
    required this.category,
    required this.date,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'description': description,
    'amount': amount,
    'category': category,
    'date': date.toIso8601String(),
  };

  factory Expense.fromJson(Map<String, dynamic> json) => Expense(
    id: json['id'],
    description: json['description'],
    amount: json['amount'],
    category: json['category'],
    date: DateTime.parse(json['date']),
  );
}

class WeeklyExpense {
  final DateTime day;
  final double amount;
  final String dayName;
  WeeklyExpense({required this.day, required this.amount, required this.dayName});
}