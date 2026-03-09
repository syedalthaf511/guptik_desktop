import 'package:flutter/material.dart';
import '../../services/external/postgres_service.dart';
import 'datatables_logic.dart';
import 'package:http/http.dart' as http;

class DatatablesScreen extends StatefulWidget {
  const DatatablesScreen({super.key});

  @override
  State<DatatablesScreen> createState() => _DatatablesScreenState();
}

class _DatatablesScreenState extends State<DatatablesScreen> {
  final PostgresService _postgres = PostgresService();
  final DatatablesLogic _logic = DatatablesLogic();

  String? _selectedTable;
  List<String> _tables = [];
  List<Map<String, dynamic>> _data = [];
  List<Map<String, dynamic>> _schema = [];
  String _searchQuery = "";

  final List<String> _defaultTables = [
    'vault_files',
    'trust_me_messages',
    'ollama_models',
    'ollama_chat_memory',
  ];

  // Scroll controllers for explicit scrollbars
  final ScrollController _horizontalScroll = ScrollController();
  final ScrollController _verticalScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadTables();
  }

  @override
  void dispose() {
    _horizontalScroll.dispose();
    _verticalScroll.dispose();
    super.dispose();
  }

  Future<void> _loadTables() async {
    final tables = await _postgres.getTableNames();
    if (mounted) {
      setState(() => _tables = tables);
      if (_tables.isNotEmpty && _selectedTable == null)
        _loadData(_tables.first);
    }
  }

  Future<void> _loadData(String tableName) async {
    final data = await _postgres.getTableData(tableName);
    final schema = await _postgres.getTableSchema(tableName);
    if (mounted) {
      setState(() {
        _selectedTable = tableName;
        _data = data;
        _schema = schema;
        _searchQuery = "";
      });
    }
  }

  // ============== ADVANCED TABLE CREATION ==============
  void _showAdvancedCreateTableDialog() {
    String tableName = '';
    List<Map<String, dynamic>> cols = [
      {
        'name': 'id',
        'type': 'UUID',
        'isPk': true,
        'isUnique': true,
        'isNullable': false,
        'defVal': 'gen_random_uuid()',
      },
    ];
    final types = [
      'TEXT',
      'INTEGER',
      'BIGINT',
      'BOOLEAN',
      'UUID',
      'JSONB',
      'TIMESTAMPTZ',
    ];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateBuilder) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            title: const Text(
              "Create Advanced Table",
              style: TextStyle(color: Colors.white),
            ),
            content: SizedBox(
              width: 900, // Slightly wider for better fit
              height: 500,
              child: Column(
                children: [
                  TextField(
                    onChanged: (v) => tableName = v.trim(),
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Table Name (No Spaces)',
                      labelStyle: TextStyle(color: Colors.cyanAccent),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: Text(
                          "Column Name",
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          "Type",
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                      Expanded(
                        child: Text("PK", style: TextStyle(color: Colors.grey)),
                      ),
                      Expanded(
                        child: Text(
                          "Unique",
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          "Null",
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          "Default",
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                      SizedBox(width: 40),
                    ],
                  ),
                  const Divider(color: Colors.grey),
                  Expanded(
                    child: ListView.builder(
                      itemCount: cols.length,
                      itemBuilder: (ctx, i) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4.0),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: TextFormField(
                                  initialValue: cols[i]['name'],
                                  style: const TextStyle(color: Colors.white),
                                  onChanged: (v) => cols[i]['name'] = v,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 2,
                                child: DropdownButton<String>(
                                  value: cols[i]['type'],
                                  isExpanded: true, // Fixes overflow issues
                                  dropdownColor: const Color(0xFF0F172A),
                                  style: const TextStyle(color: Colors.white),
                                  items: types
                                      .map(
                                        (t) => DropdownMenuItem(
                                          value: t,
                                          child: Text(t),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (v) => setStateBuilder(
                                    () => cols[i]['type'] = v!,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Checkbox(
                                  value: cols[i]['isPk'],
                                  activeColor: Colors.cyanAccent,
                                  onChanged: (v) => setStateBuilder(
                                    () => cols[i]['isPk'] = v,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Checkbox(
                                  value: cols[i]['isUnique'],
                                  activeColor: Colors.cyanAccent,
                                  onChanged: (v) => setStateBuilder(
                                    () => cols[i]['isUnique'] = v,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Checkbox(
                                  value: cols[i]['isNullable'],
                                  activeColor: Colors.cyanAccent,
                                  onChanged: (v) => setStateBuilder(
                                    () => cols[i]['isNullable'] = v,
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: TextFormField(
                                  initialValue: cols[i]['defVal'],
                                  style: const TextStyle(color: Colors.white),
                                  onChanged: (v) => cols[i]['defVal'] = v,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.remove_circle,
                                  color: Colors.redAccent,
                                ),
                                onPressed: () =>
                                    setStateBuilder(() => cols.removeAt(i)),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.add, color: Colors.cyanAccent),
                    label: const Text(
                      "Add Column",
                      style: TextStyle(color: Colors.cyanAccent),
                    ),
                    onPressed: () => setStateBuilder(
                      () => cols.add({
                        'name': '',
                        'type': 'TEXT',
                        'isPk': false,
                        'isUnique': false,
                        'isNullable': true,
                        'defVal': '',
                      }),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Cancel"),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.cyanAccent,
                  foregroundColor: Colors.black,
                ),
                onPressed: () async {
                  if (tableName.isEmpty) return;
                  try {
                    await _logic.createAdvancedTable(tableName, cols);
                    if (!context.mounted) return; // Safe check
                    Navigator.pop(context);
                    _loadTables();
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text("Error: $e"),
                          backgroundColor: Colors.redAccent,
                        ),
                      );
                    }
                  }
                },
                child: const Text("Create Table"),
              ),
            ],
          );
        },
      ),
    );
  }

  // ============== SMART ROW EDITOR ==============
  void _showRowDialog({Map<String, dynamic>? existingRow}) {
    if (_selectedTable == null || _schema.isEmpty) return;

    Map<String, dynamic> inputData = {};
    for (var col in _schema) {
      inputData[col['name']] = existingRow?[col['name']]?.toString() ?? '';
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateBuilder) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            title: Text(
              existingRow == null ? "Insert Row" : "Edit Row",
              style: const TextStyle(color: Colors.white),
            ),
            content: SizedBox(
              width: 500,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: _schema.map((col) {
                    final isBool = col['type']
                        .toString()
                        .toLowerCase()
                        .contains('bool');
                    final hint = col['default'] != null
                        ? "Default: ${col['default']}"
                        : "Type: ${col['type']}";

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12.0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 120,
                            child: Text(
                              col['name'],
                              style: const TextStyle(
                                color: Colors.cyanAccent,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Expanded(
                            child: isBool
                                ? DropdownButtonFormField<String>(
                                    value:
                                        inputData[col['name']]
                                            .toString()
                                            .isEmpty
                                        ? null
                                        : inputData[col['name']].toString(),
                                    dropdownColor: const Color(0xFF0F172A),
                                    style: const TextStyle(color: Colors.white),
                                    decoration: InputDecoration(
                                      hintText: "Select Boolean",
                                      hintStyle: const TextStyle(
                                        color: Colors.grey,
                                      ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    items: const [
                                      DropdownMenuItem(
                                        value: 'true',
                                        child: Text("TRUE"),
                                      ),
                                      DropdownMenuItem(
                                        value: 'false',
                                        child: Text("FALSE"),
                                      ),
                                    ],
                                    onChanged: (v) =>
                                        inputData[col['name']] = v,
                                  )
                                : TextFormField(
                                    initialValue: inputData[col['name']],
                                    style: const TextStyle(color: Colors.white),
                                    decoration: InputDecoration(
                                      hintText: hint,
                                      hintStyle: const TextStyle(
                                        color: Colors.grey,
                                        fontSize: 12,
                                      ),
                                      filled: true,
                                      fillColor: const Color(0xFF0F172A),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide.none,
                                      ),
                                    ),
                                    onChanged: (v) =>
                                        inputData[col['name']] = v,
                                  ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Cancel"),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.cyanAccent,
                  foregroundColor: Colors.black,
                ),
                onPressed: () async {
                  try {
                    if (existingRow == null) {
                      await _logic.insertRow(_selectedTable!, inputData);
                    } else {
                      // Fix: Use existingRow! to force non-null, safe because of the check
                      await _logic.updateRow(
                        _selectedTable!,
                        _schema.first['name'],
                        existingRow![_schema.first['name']].toString(),
                        inputData,
                      );
                    }
                    if (!context.mounted) return;
                    Navigator.pop(context);
                    _loadData(_selectedTable!);
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text("Error: $e"),
                          backgroundColor: Colors.redAccent,
                        ),
                      );
                    }
                  }
                },
                child: const Text("Save Data"),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredData = _searchQuery.isEmpty
        ? _data
        : _data.where((row) {
            return row.values.any(
              (val) => val.toString().toLowerCase().contains(
                _searchQuery.toLowerCase(),
              ),
            );
          }).toList();

    return Row(
      children: [
        // ============== LEFT SIDEBAR: TABLES ==============
        Container(
          width: 220,
          decoration: BoxDecoration(
            border: Border(
              right: BorderSide(color: Colors.white.withOpacity(0.1)),
            ),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.table_bar_outlined),
                  label: const Text("New Table"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.cyanAccent,
                    foregroundColor: Colors.black,
                    minimumSize: const Size(double.infinity, 45),
                  ),
                  onPressed: _showAdvancedCreateTableDialog,
                ),
              ),
              const Divider(color: Colors.grey, height: 1),
              Expanded(
                child: ListView.builder(
                  itemCount: _tables.length,
                  itemBuilder: (ctx, i) {
                    final t = _tables[i];
                    final isSelected = t == _selectedTable;
                    final isDefault = _defaultTables.contains(t);
                    return ListTile(
                      leading: Icon(
                        isDefault ? Icons.lock_outline : Icons.table_chart,
                        color: isSelected ? Colors.cyanAccent : Colors.grey,
                        size: 18,
                      ),
                      title: Text(
                        t,
                        style: TextStyle(
                          color: isSelected ? Colors.cyanAccent : Colors.white,
                          fontSize: 13,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                      tileColor: isSelected
                          ? Colors.white.withOpacity(0.05)
                          : Colors.transparent,
                      onTap: () => _loadData(t),
                    );
                  },
                ),
              ),
            ],
          ),
        ),

        // ============== RIGHT AREA: DATA & ACTIONS ==============
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // TOP ACTION BAR
              Container(
                padding: const EdgeInsets.all(16.0),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Colors.white.withOpacity(0.1)),
                  ),
                ),
                child: Row(
                  children: [
                    Text(
                      _selectedTable?.toUpperCase() ?? "NO TABLE SELECTED",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(width: 30),
                    if (_selectedTable != null) ...[
                      // SEARCH
                      Expanded(
                        child: TextField(
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            prefixIcon: const Icon(
                              Icons.search,
                              color: Colors.grey,
                            ),
                            hintText: "Search row data...",
                            hintStyle: const TextStyle(color: Colors.grey),
                            filled: true,
                            fillColor: const Color(0xFF1E293B),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          onChanged: (val) =>
                              setState(() => _searchQuery = val),
                        ),
                      ),
                      const SizedBox(width: 20),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.add),
                        label: const Text("Insert Row"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1E293B),
                          foregroundColor: Colors.cyanAccent,
                        ),
                        onPressed: () => _showRowDialog(),
                      ),
                      const SizedBox(width: 10),
                      IconButton(
                        icon: const Icon(Icons.refresh, color: Colors.white),
                        onPressed: () => _loadData(_selectedTable!),
                      ),
                      if (!_defaultTables.contains(_selectedTable)) ...[
                        const SizedBox(width: 10),
                        IconButton(
                          icon: const Icon(
                            Icons.delete_forever,
                            color: Colors.redAccent,
                          ),
                          tooltip: "Drop Table",
                          onPressed: () async {
                            await _logic.deleteTable(_selectedTable!);
                            if (mounted) {
                              setState(() {
                                _selectedTable = null;
                                _data = [];
                                _schema = [];
                              });
                              _loadTables();
                            }
                          },
                        ),
                      ],
                    ],
                  ],
                ),
              ),

              // TABLE BODY WITH ALWAYS-VISIBLE SCROLLBARS (TOP HORIZONTAL & RIGHT VERTICAL)
              if (_schema.isNotEmpty)
                Expanded(
                  child: Scrollbar(
                    controller: _horizontalScroll,
                    thumbVisibility: true,
                    scrollbarOrientation:
                        ScrollbarOrientation.top, // TOP HORIZONTAL SCROLLBAR
                    child: SingleChildScrollView(
                      controller: _horizontalScroll,
                      scrollDirection: Axis.horizontal,
                      child: Scrollbar(
                        controller: _verticalScroll,
                        thumbVisibility: true, // RIGHT VERTICAL SCROLLBAR
                        child: SingleChildScrollView(
                          controller: _verticalScroll,
                          scrollDirection: Axis.vertical,
                          child: DataTable(
                            headingRowColor: WidgetStateProperty.all(
                              const Color(0xFF1E293B),
                            ),
                            columns: [
                              ..._schema.map(
                                (col) => DataColumn(
                                  label: Row(
                                    children: [
                                      Text(
                                        col['name'],
                                        style: const TextStyle(
                                          color: Colors.cyanAccent,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(width: 5),
                                      Text(
                                        '(${col['type']})',
                                        style: const TextStyle(
                                          color: Colors.grey,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const DataColumn(
                                label: Text(
                                  'Actions',
                                  style: TextStyle(color: Colors.cyanAccent),
                                ),
                              ),
                            ],
                            rows: filteredData
                                .map(
                                  (row) => DataRow(
                                    cells: [
                                      ..._schema.map(
                                        (col) => DataCell(
                                          Text(
                                            row[col['name']]?.toString() ??
                                                'NULL',
                                            style: TextStyle(
                                              color: row[col['name']] == null
                                                  ? Colors.grey
                                                  : Colors.white,
                                            ),
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              icon: const Icon(
                                                Icons.edit,
                                                color: Colors.cyanAccent,
                                                size: 18,
                                              ),
                                              onPressed: () => _showRowDialog(
                                                existingRow: row,
                                              ),
                                            ),
                                            IconButton(
                                              icon: const Icon(
                                                Icons.delete,
                                                color: Colors.redAccent,
                                                size: 18,
                                              ),
                                              onPressed: () async {
                                                // 1. IS THIS THE VAULT FILES TABLE?
                                                if (_selectedTable ==
                                                    'vault_files') {
                                                  try {
                                                    final fileName =
                                                        row['file_name']
                                                            .toString(); // Grab the exact filename
                                                    print(
                                                      'Sending delete request to Gateway for: $fileName',
                                                    );

                                                    // Tell the Docker Gateway to delete the file AND the database row!
                                                    final response = await http
                                                        .delete(
                                                          Uri.parse(
                                                            'http://localhost:55000/vault/delete/$fileName',
                                                          ),
                                                        );

                                                    if (response.statusCode ==
                                                        200) {
                                                      print(
                                                        '✅ Full System Delete Successful',
                                                      );
                                                    } else {
                                                      print(
                                                        '❌ Gateway Error: ${response.body}',
                                                      );
                                                    }
                                                  } catch (e) {
                                                    print(
                                                      '❌ Network Error: Could not reach Docker Gateway to delete file: $e',
                                                    );
                                                  }
                                                }
                                                // 2. FOR ALL OTHER TABLES (Normal Database Delete)
                                                else if (_schema.isNotEmpty) {
                                                  await _logic.deleteRow(
                                                    _selectedTable!,
                                                    _schema.first['name'],
                                                    row[_schema.first['name']]
                                                        .toString(),
                                                  );
                                                }

                                                // 3. REFRESH THE SCREEN
                                                _loadData(_selectedTable!);
                                              },
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
