import 'package:flutter/material.dart';
import '../../core/api/medcore_api_client.dart';
import '../../core/localization/medcore_strings_ar.dart';
import '../../core/localization/medcore_localizations.dart';
import '../../core/state/medcore_app_controller.dart';

class DefinitionDomainInfo {
  final String type;
  final String nameAr;
  final String nameEn;
  final String group;
  final IconData icon;

  const DefinitionDomainInfo({
    required this.type,
    required this.nameAr,
    required this.nameEn,
    required this.group,
    required this.icon,
  });
}

class DefinitionsWorkspaceScreen extends StatefulWidget {
  final MedCoreAppController controller;

  const DefinitionsWorkspaceScreen({
    super.key,
    required this.controller,
  });

  @override
  State<DefinitionsWorkspaceScreen> createState() => _DefinitionsWorkspaceScreenState();
}

class _DefinitionsWorkspaceScreenState extends State<DefinitionsWorkspaceScreen> {
  static const List<DefinitionDomainInfo> allDomains = [
    // Finance & Insurance
    DefinitionDomainInfo(
      type: 'financial_categories',
      nameAr: 'التصنيفات المالية',
      nameEn: 'Financial Categories',
      group: 'المالية والتأمين',
      icon: Icons.account_balance_outlined,
    ),
    DefinitionDomainInfo(
      type: 'payment_methods',
      nameAr: 'طرق الدفع والتحصيل',
      nameEn: 'Payment Methods',
      group: 'المالية والتأمين',
      icon: Icons.payment_outlined,
    ),
    DefinitionDomainInfo(
      type: 'expense_types',
      nameAr: 'بنود المصروفات',
      nameEn: 'Expense Types',
      group: 'المالية والتأمين',
      icon: Icons.money_off_outlined,
    ),
    DefinitionDomainInfo(
      type: 'revenue_types',
      nameAr: 'بنود الإيرادات',
      nameEn: 'Revenue Types',
      group: 'المالية والتأمين',
      icon: Icons.attach_money_outlined,
    ),
    DefinitionDomainInfo(
      type: 'tax_settings',
      nameAr: 'إعدادات الضرائب والرسوم',
      nameEn: 'Tax Settings',
      group: 'المالية والتأمين',
      icon: Icons.receipt_long_outlined,
    ),
    DefinitionDomainInfo(
      type: 'insurance_providers',
      nameAr: 'شركات التأمين الصحي',
      nameEn: 'Insurance Providers',
      group: 'المالية والتأمين',
      icon: Icons.health_and_safety_outlined,
    ),
    DefinitionDomainInfo(
      type: 'insurance_classes',
      nameAr: 'فئات وباقات التأمين',
      nameEn: 'Insurance Classes',
      group: 'المالية والتأمين',
      icon: Icons.card_membership_outlined,
    ),

    // Services & Consumables
    DefinitionDomainInfo(
      type: 'service_categories',
      nameAr: 'تصنيفات الخدمات الطبية',
      nameEn: 'Service Categories',
      group: 'الخدمات والمستلزمات',
      icon: Icons.category_outlined,
    ),
    DefinitionDomainInfo(
      type: 'services',
      nameAr: 'دليل الخدمات والتسعير',
      nameEn: 'Services Catalog',
      group: 'الخدمات والمستلزمات',
      icon: Icons.medical_services_outlined,
    ),
    DefinitionDomainInfo(
      type: 'consumable_categories',
      nameAr: 'تصنيفات المستلزمات الطبية',
      nameEn: 'Consumable Categories',
      group: 'الخدمات والمستلزمات',
      icon: Icons.inventory_2_outlined,
    ),
    DefinitionDomainInfo(
      type: 'consumables',
      nameAr: 'دليل المستلزمات والتسعير',
      nameEn: 'Consumables Catalog',
      group: 'الخدمات والمستلزمات',
      icon: Icons.vaccines_outlined,
    ),

    // Diagnostics
    DefinitionDomainInfo(
      type: 'lab_tests',
      nameAr: 'دليل التحاليل المخبرية',
      nameEn: 'Laboratory Tests',
      group: 'المختبر والأشعة',
      icon: Icons.biotech_outlined,
    ),
    DefinitionDomainInfo(
      type: 'radiology_procedures',
      nameAr: 'دليل الفحوصات الإشعاعية',
      nameEn: 'Radiology Procedures',
      group: 'المختبر والأشعة',
      icon: Icons.monitor_heart_outlined,
    ),

    // Pharmacy & Inventory
    DefinitionDomainInfo(
      type: 'medication_categories',
      nameAr: 'تصنيفات الأدوية',
      nameEn: 'Medication Categories',
      group: 'الصيدلية والمخازن',
      icon: Icons.local_pharmacy_outlined,
    ),
    DefinitionDomainInfo(
      type: 'medications',
      nameAr: 'دليل الأدوية والصيدلية',
      nameEn: 'Medications Catalog',
      group: 'الصيدلية والمخازن',
      icon: Icons.medication_outlined,
    ),
    DefinitionDomainInfo(
      type: 'inventory_locations',
      nameAr: 'المخازن ومواقع التخزين',
      nameEn: 'Inventory Locations',
      group: 'الصيدلية والمخازن',
      icon: Icons.warehouse_outlined,
    ),
    DefinitionDomainInfo(
      type: 'supplier_categories',
      nameAr: 'تصنيفات الموردين',
      nameEn: 'Supplier Categories',
      group: 'الصيدلية والمخازن',
      icon: Icons.people_outline,
    ),
    DefinitionDomainInfo(
      type: 'suppliers',
      nameAr: 'دليل الموردين وجهات التوريد',
      nameEn: 'Suppliers Directory',
      group: 'الصيدلية والمخازن',
      icon: Icons.local_shipping_outlined,
    ),

    // HR & Payroll
    DefinitionDomainInfo(
      type: 'leave_types',
      nameAr: 'أنواع الإجازات',
      nameEn: 'Leave Types',
      group: 'الموارد البشرية والرواتب',
      icon: Icons.event_busy_outlined,
    ),
    DefinitionDomainInfo(
      type: 'payroll_allowances',
      nameAr: 'البدلات والمزايا المالية',
      nameEn: 'Payroll Allowances',
      group: 'الموارد البشرية والرواتب',
      icon: Icons.trending_up_outlined,
    ),
    DefinitionDomainInfo(
      type: 'payroll_deductions',
      nameAr: 'الاستقطاعات والخصومات',
      nameEn: 'Payroll Deductions',
      group: 'الموارد البشرية والرواتب',
      icon: Icons.trending_down_outlined,
    ),
  ];

  late DefinitionDomainInfo _selectedDomain;
  bool _isLoading = false;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  String _itemSearchQuery = '';
  String _domainSearchQuery = '';

  @override
  void initState() {
    super.initState();
    _selectedDomain = allDomains.first;
    _fetchItems();
  }

  Future<void> _fetchItems() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final items = await widget.controller.api.getDefinitions(_selectedDomain.type);
      if (mounted) {
        setState(() {
          _items = items;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  List<DefinitionDomainInfo> get _filteredDomains {
    if (_domainSearchQuery.trim().isEmpty) return allDomains;
    final q = _domainSearchQuery.trim().toLowerCase();
    return allDomains.where((d) {
      return d.nameAr.toLowerCase().contains(q) ||
          d.nameEn.toLowerCase().contains(q) ||
          d.type.toLowerCase().contains(q) ||
          d.group.toLowerCase().contains(q);
    }).toList();
  }

  List<Map<String, dynamic>> get _filteredItems {
    if (_itemSearchQuery.trim().isEmpty) return _items;
    final q = _itemSearchQuery.trim().toLowerCase();
    return _items.where((item) {
      final code = (item['code'] ?? '').toString().toLowerCase();
      final nameAr = (item['name_ar'] ?? '').toString().toLowerCase();
      final nameEn = (item['name_en'] ?? '').toString().toLowerCase();
      final desc = (item['description'] ?? '').toString().toLowerCase();
      return code.contains(q) || nameAr.contains(q) || nameEn.contains(q) || desc.contains(q);
    }).toList();
  }

  void _showAddEditDialog([Map<String, dynamic>? existing]) {
    final isEdit = existing != null;
    final codeCtrl = TextEditingController(text: existing?['code']?.toString() ?? '');
    final nameArCtrl = TextEditingController(text: existing?['name_ar']?.toString() ?? '');
    final nameEnCtrl = TextEditingController(text: existing?['name_en']?.toString() ?? '');
    final descCtrl = TextEditingController(text: existing?['description']?.toString() ?? '');
    bool isActive = (existing?['is_active'] == 1 || existing?['is_active'] == true || existing == null);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(isEdit ? Icons.edit_note : Icons.add_circle_outline, color: const Color(0xFF0F766E)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isEdit ? 'تعديل عنصر التعريف' : 'إضافة عنصر جديد في ${_selectedDomain.nameAr}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    key: const Key('input_def_code'),
                    controller: codeCtrl,
                    decoration: const InputDecoration(
                      labelText: 'الكود التعريفي (Code) *',
                      hintText: 'مثال: CAT-001',
                      border: OutlineInputBorder(),
                    ),
                    textDirection: TextDirection.ltr,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('input_def_name_ar'),
                    controller: nameArCtrl,
                    decoration: const InputDecoration(
                      labelText: 'الاسم بالعربية *',
                      hintText: 'الاسم الكامل للتعريف',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('input_def_name_en'),
                    controller: nameEnCtrl,
                    decoration: const InputDecoration(
                      labelText: 'الاسم بالإنجليزية',
                      hintText: 'Name in English',
                      border: OutlineInputBorder(),
                    ),
                    textDirection: TextDirection.ltr,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('input_def_description'),
                    controller: descCtrl,
                    decoration: const InputDecoration(
                      labelText: 'الوصف أو الملاحظات',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    key: const Key('switch_def_is_active'),
                    title: const Text('الحالة نشطة'),
                    subtitle: Text(isActive ? 'العنصر متاح ومفعل في النظام' : 'العنصر معطل مؤقتاً'),
                    value: isActive,
                    onChanged: (val) {
                      setDialogState(() => isActive = val);
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              key: const Key('btn_save_definition'),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F766E), foregroundColor: Colors.white),
              onPressed: () async {
                final code = codeCtrl.text.trim();
                final nameAr = nameArCtrl.text.trim();
                if (code.isEmpty || nameAr.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('يرجى ملء الكود والاسم بالعربية.')),
                  );
                  return;
                }

                Navigator.pop(ctx);
                final payload = <String, dynamic>{
                  'code': code,
                  'name_ar': nameAr,
                  'name_en': nameEnCtrl.text.trim(),
                  'description': descCtrl.text.trim(),
                  'is_active': isActive ? 1 : 0,
                };

                try {
                  if (isEdit) {
                    final publicId = (existing['public_id'] ?? existing['id']).toString();
                    await widget.controller.api.updateDefinition(publicId, payload);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('تم تحديث عنصر التعريف بنجاح.')),
                      );
                    }
                  } else {
                    await widget.controller.api.createDefinition(_selectedDomain.type, payload);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('تمت إضافة عنصر التعريف بنجاح.')),
                      );
                    }
                  }
                  _fetchItems();
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('خطأ أثناء الحفظ: $e'), backgroundColor: Colors.red),
                    );
                  }
                }
              },
              child: Text(isEdit ? 'حفظ التعديلات' : 'إضافة التعريف'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(Map<String, dynamic> item) {
    final publicId = (item['public_id'] ?? item['id']).toString();
    final name = item['name_ar'] ?? item['code'] ?? '';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text('تأكيد الحذف'),
          ],
        ),
        content: Text('هل أنت متأكد من رغبتك في حذف عنصر التعريف "$name"؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            key: const Key('btn_confirm_delete_definition'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await widget.controller.api.deleteDefinition(publicId);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم حذف عنصر التعريف بنجاح.')),
                  );
                }
                _fetchItems();
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('فشل الحذف: $e'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('حذف نهائي'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left Sidebar: 21 Definition Domains
          SizedBox(
            width: 280,
            child: Card(
              margin: const EdgeInsets.all(12),
              elevation: 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: const BoxDecoration(
                      color: Color(0xFF0F766E),
                      borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: const [
                            Icon(Icons.folder_special, color: Colors.white, size: 20),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'دليل التعريفات الشاملة',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          '21 مجالاً موحداً لإعدادات المستشفى',
                          style: TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: TextField(
                      key: const Key('input_domain_search'),
                      onChanged: (val) => setState(() => _domainSearchQuery = val),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search, size: 18),
                        hintText: 'بحث في مجالات التعريفات...',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _filteredDomains.length,
                      itemBuilder: (context, idx) {
                        final domain = _filteredDomains[idx];
                        final isSelected = domain.type == _selectedDomain.type;
                        return ListTile(
                          dense: true,
                          selected: isSelected,
                          selectedTileColor: const Color(0xFF0F766E).withOpacity(0.1),
                          leading: Icon(
                            domain.icon,
                            color: isSelected ? const Color(0xFF0F766E) : Colors.grey[700],
                            size: 18,
                          ),
                          title: Text(
                            domain.nameAr,
                            style: TextStyle(
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                              color: isSelected ? const Color(0xFF0F766E) : Colors.black87,
                              fontSize: 12,
                            ),
                          ),
                          subtitle: Text(
                            domain.type,
                            style: TextStyle(
                              fontSize: 10,
                              fontFamily: 'Consolas',
                              color: Colors.grey[600],
                            ),
                          ),
                          onTap: () {
                            if (_selectedDomain.type != domain.type) {
                              setState(() {
                                _selectedDomain = domain;
                              });
                              _fetchItems();
                            }
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Main Area: Active Domain Items Table
          Expanded(
            child: Card(
              margin: const EdgeInsets.fromLTRB(0, 12, 12, 12),
              elevation: 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header Bar (Horizontal Scrollable for responsiveness)
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_selectedDomain.icon, color: const Color(0xFF0F766E), size: 26),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _selectedDomain.nameAr,
                                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.teal.shade50,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: Colors.teal.shade200),
                                    ),
                                    child: Text(
                                      _selectedDomain.group,
                                      style: TextStyle(fontSize: 11, color: Colors.teal.shade800),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              TechnicalLtrField(
                                '${_selectedDomain.type} (${_items.length} عنصر مسجل)',
                                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                              ),
                            ],
                          ),
                          const SizedBox(width: 24),
                          SizedBox(
                            width: 200,
                            child: TextField(
                              key: const Key('input_search_definitions'),
                              onChanged: (val) => setState(() => _itemSearchQuery = val),
                              decoration: InputDecoration(
                                prefixIcon: const Icon(Icons.search, size: 18),
                                hintText: 'بحث في عناصر الدليل...',
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            key: const Key('btn_refresh_definitions'),
                            icon: const Icon(Icons.refresh),
                            tooltip: 'تحديث',
                            onPressed: _fetchItems,
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            key: const Key('btn_add_definition'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0F766E),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('إضافة عنصر جديد'),
                            onPressed: () => _showAddEditDialog(),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 20),

                    // Body
                    if (_isLoading)
                      const Expanded(
                        child: Center(
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else if (_error != null)
                      Expanded(
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.error_outline, color: Colors.red, size: 40),
                              const SizedBox(height: 8),
                              Text('تعذر تحميل البيانات: $_error', style: const TextStyle(color: Colors.red)),
                              const SizedBox(height: 12),
                              ElevatedButton(
                                onPressed: _fetchItems,
                                child: const Text('إعادة المحاولة'),
                              ),
                            ],
                          ),
                        ),
                      )
                    else if (_filteredItems.isEmpty)
                      Expanded(
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.inbox_outlined, size: 48, color: Colors.grey[400]),
                              const SizedBox(height: 12),
                              Text(
                                _itemSearchQuery.isNotEmpty
                                    ? 'لا توجد نتائج مطابقة لبحثك'
                                    : 'لا توجد عناصر مسجلة في هذا الدليل بعد',
                                style: TextStyle(color: Colors.grey[600], fontSize: 15),
                              ),
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                icon: const Icon(Icons.add),
                                label: const Text('إضافة العنصر الأول الآن'),
                                onPressed: () => _showAddEditDialog(),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      Expanded(
                        child: SingleChildScrollView(
                          child: Table(
                            columnWidths: const {
                              0: FlexColumnWidth(1.2), // Code
                              1: FlexColumnWidth(2.0), // Name Ar
                              2: FlexColumnWidth(2.0), // Name En
                              3: FlexColumnWidth(2.5), // Description
                              4: FlexColumnWidth(1.0), // Status
                              5: FlexColumnWidth(1.2), // Actions
                            },
                            border: TableBorder(
                              horizontalInside: BorderSide(color: Colors.grey.shade200),
                            ),
                            children: [
                              TableRow(
                                decoration: BoxDecoration(color: Colors.grey.shade100),
                                children: const [
                                  Padding(
                                    padding: EdgeInsets.all(10),
                                    child: Text('الكود', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                  ),
                                  Padding(
                                    padding: EdgeInsets.all(10),
                                    child: Text('الاسم بالعربية', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                  ),
                                  Padding(
                                    padding: EdgeInsets.all(10),
                                    child: Text('الاسم بالإنجليزية', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                  ),
                                  Padding(
                                    padding: EdgeInsets.all(10),
                                    child: Text('الوصف / الملاحظات', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                  ),
                                  Padding(
                                    padding: EdgeInsets.all(10),
                                    child: Text('الحالة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                  ),
                                  Padding(
                                    padding: EdgeInsets.all(10),
                                    child: Text('الإجراءات', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                  ),
                                ],
                              ),
                              ..._filteredItems.map((item) {
                                final code = (item['code'] ?? '').toString();
                                final nameAr = (item['name_ar'] ?? '').toString();
                                final nameEn = (item['name_en'] ?? '').toString();
                                final desc = (item['description'] ?? '').toString();
                                final isActive = (item['is_active'] == 1 || item['is_active'] == true);

                                return TableRow(
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.all(10),
                                      child: Text(
                                        code,
                                        key: Key('cell_code_$code'),
                                        style: const TextStyle(fontFamily: 'Consolas', fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.all(10),
                                      child: Text(nameAr, style: const TextStyle(fontWeight: FontWeight.w500)),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.all(10),
                                      child: Text(nameEn.isEmpty ? '-' : nameEn, textDirection: TextDirection.ltr),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.all(10),
                                      child: Text(desc.isEmpty ? '-' : desc, style: TextStyle(color: Colors.grey[700], fontSize: 12)),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.all(10),
                                      child: Align(
                                        alignment: Alignment.centerRight,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: isActive ? Colors.green.shade50 : Colors.red.shade50,
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: isActive ? Colors.green.shade200 : Colors.red.shade200),
                                          ),
                                          child: Text(
                                            isActive ? 'نشط' : 'معطل',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: isActive ? Colors.green.shade800 : Colors.red.shade800,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.all(6),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            key: Key('btn_edit_$code'),
                                            icon: const Icon(Icons.edit_outlined, size: 18),
                                            tooltip: 'تعديل',
                                            onPressed: () => _showAddEditDialog(item),
                                          ),
                                          IconButton(
                                            key: Key('btn_delete_$code'),
                                            icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                                            tooltip: 'حذف',
                                            onPressed: () => _confirmDelete(item),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                );
                              }),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
