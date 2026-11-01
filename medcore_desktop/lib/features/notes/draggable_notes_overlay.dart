import 'package:flutter/material.dart';
import '../../core/api/medcore_api_client.dart';
import '../../core/localization/medcore_strings_ar.dart';
import '../../core/state/medcore_app_controller.dart';

/// Draggable Floating Note FAB (`+`) and Scratchpad Overlay (Gate 15).
/// Persistent across all screens in MedCore Platinum Desktop.
/// Notes are persisted to MariaDB (`mc_internal_notes`) via `/api/v1/internal-notes`.
class DraggableNotesOverlay extends StatefulWidget {
  final MedCoreAppController controller;

  const DraggableNotesOverlay({
    super.key,
    required this.controller,
  });

  @override
  State<DraggableNotesOverlay> createState() => _DraggableNotesOverlayState();
}

class _DraggableNotesOverlayState extends State<DraggableNotesOverlay> {
  Offset _position = const Offset(24, 80);
  bool _isOpen = false;
  bool _isLoading = false;
  String? _error;
  List<Map<String, dynamic>> _notes = [];

  final TextEditingController _noteContentCtrl = TextEditingController();
  String _selectedPriority = 'NORMAL';

  @override
  void initState() {
    super.initState();
    _fetchNotes();
  }

  @override
  void dispose() {
    _noteContentCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchNotes() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final items = await widget.controller.api.getInternalNotes();
      if (mounted) {
        setState(() {
          _notes = items;
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

  Future<void> _saveNote() async {
    final text = _noteContentCtrl.text.trim();
    if (text.isEmpty) return;

    try {
      await widget.controller.api.createInternalNote(
        text,
        priority: _selectedPriority,
      );
      _noteContentCtrl.clear();
      await _fetchNotes();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حفظ الملاحظة الداخلية بنجاح.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل حفظ الملاحظة: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _togglePin(String publicId) async {
    try {
      await widget.controller.api.togglePinInternalNote(publicId);
      await _fetchNotes();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل تثبيت الملاحظة: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    return Positioned(
      left: widget.controller.isRtl ? _position.dx : null,
      right: widget.controller.isRtl ? null : _position.dx,
      bottom: _position.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            final newDx = _position.dx - (widget.controller.isRtl ? details.delta.dx : -details.delta.dx);
            final newDy = _position.dy - details.delta.dy;
            _position = Offset(
              newDx.clamp(16.0, screenSize.width - 80.0),
              newDy.clamp(16.0, screenSize.height - 80.0),
            );
          });
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: widget.controller.isRtl ? CrossAxisAlignment.start : CrossAxisAlignment.end,
          children: [
            if (_isOpen)
              Card(
                key: const Key('card_notes_scratchpad'),
                elevation: 8,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Container(
                  width: 360,
                  height: 440,
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header
                      Row(
                        children: [
                          const Icon(Icons.sticky_note_2, color: Color(0xFF0F766E), size: 22),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'الملاحظات والتذكيرات الداخلية',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ),
                          IconButton(
                            key: const Key('btn_close_notes'),
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () => setState(() => _isOpen = false),
                          ),
                        ],
                      ),
                      const Divider(height: 12),

                      // Input area
                      TextField(
                        key: const Key('input_quick_note_content'),
                        controller: _noteContentCtrl,
                        maxLines: 2,
                        decoration: InputDecoration(
                          hintText: 'اكتب ملاحظة سريعة أو تذكير داخلي...',
                          isDense: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          DropdownButton<String>(
                            value: _selectedPriority,
                            isDense: true,
                            items: const [
                              DropdownMenuItem(value: 'NORMAL', child: Text('عادي')),
                              DropdownMenuItem(value: 'IMPORTANT', child: Text('هام')),
                              DropdownMenuItem(value: 'URGENT', child: Text('عاجل')),
                            ],
                            onChanged: (val) {
                              if (val != null) setState(() => _selectedPriority = val);
                            },
                          ),
                          const Spacer(),
                          ElevatedButton.icon(
                            key: const Key('btn_save_quick_note'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0F766E),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                            icon: const Icon(Icons.send, size: 14),
                            label: const Text('حفظ'),
                            onPressed: _saveNote,
                          ),
                        ],
                      ),
                      const Divider(height: 16),

                      // Notes List
                      Expanded(
                        child: _isLoading
                            ? const Center(child: CircularProgressIndicator())
                            : _notes.isEmpty
                                ? Center(
                                    child: Text(
                                      'لا توجد ملاحظات داخلية محفوظة.',
                                      style: TextStyle(color: Colors.grey[500], fontSize: 12),
                                    ),
                                  )
                                : ListView.separated(
                                    itemCount: _notes.length,
                                    separatorBuilder: (_, __) => const Divider(height: 8),
                                    itemBuilder: (ctx, idx) {
                                      final note = _notes[idx];
                                      final isPinned = (note['is_pinned'] == 1 || note['isPinned'] == true);
                                      final content = (note['content'] ?? '').toString();
                                      final priority = (note['priority'] ?? 'NORMAL').toString();
                                      final publicId = (note['public_id'] ?? note['id']).toString();

                                      Color badgeColor = Colors.grey;
                                      if (priority == 'URGENT') badgeColor = Colors.red;
                                      if (priority == 'IMPORTANT') badgeColor = Colors.orange;

                                      return ListTile(
                                        dense: true,
                                        contentPadding: EdgeInsets.zero,
                                        title: Text(content, style: const TextStyle(fontSize: 12)),
                                        subtitle: Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                              decoration: BoxDecoration(
                                                color: badgeColor.withOpacity(0.15),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                priority,
                                                style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: badgeColor),
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              note['created_by']?.toString() ?? '',
                                              style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                                            ),
                                          ],
                                        ),
                                        trailing: IconButton(
                                          key: Key('btn_pin_note_$publicId'),
                                          icon: Icon(
                                            isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                                            size: 16,
                                            color: isPinned ? const Color(0xFF0F766E) : Colors.grey,
                                          ),
                                          onPressed: () => _togglePin(publicId),
                                        ),
                                      );
                                    },
                                  ),
                      ),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 8),

            // Draggable Floating Action Button
            FloatingActionButton(
              key: const Key('fab_quick_notes'),
              mini: true,
              backgroundColor: const Color(0xFF0F766E),
              foregroundColor: Colors.white,
              tooltip: 'مفكرة الملاحظات والتذكيرات الداخلية السريعة',
              onPressed: () {
                setState(() {
                  _isOpen = !_isOpen;
                });
                if (_isOpen) _fetchNotes();
              },
              child: Icon(_isOpen ? Icons.close : Icons.note_add_outlined, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}
