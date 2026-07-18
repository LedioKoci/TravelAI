import 'package:flutter/material.dart';

import '../results_screen.dart';
import '../services/travel_storage_service.dart';

/// A Claude/Gemini-style history sidebar listing travels the user has
/// manually saved. Tapping an entry reopens it from local storage — no
/// backend/Gemini call is made, so it costs no API tokens.
class TravelSidebar extends StatefulWidget {
  const TravelSidebar({Key? key}) : super(key: key);

  @override
  State<TravelSidebar> createState() => _TravelSidebarState();
}

class _TravelSidebarState extends State<TravelSidebar> {
  late Future<List<SavedTravel>> _future;

  @override
  void initState() {
    super.initState();
    _future = TravelStorageService.getAll();
  }

  void _refresh() {
    setState(() {
      _future = TravelStorageService.getAll();
    });
  }

  String _formatSavedAt(DateTime date) {
    final now = DateTime.now();
    final isToday = date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
    if (isToday) {
      final hour = date.hour.toString().padLeft(2, '0');
      final minute = date.minute.toString().padLeft(2, '0');
      return '$hour:$minute';
    }
    return '${date.month}/${date.day}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: const Color(0xFFF7FAFF),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Row(
                children: [
                  Icon(Icons.travel_explore, color: Colors.blue.shade700),
                  const SizedBox(width: 8),
                  Text(
                    'Saved Travels',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade800,
                    ),
                  ),
                ],
              ),
            ),
            Divider(color: Colors.blue.shade100, height: 1),
            Expanded(
              child: FutureBuilder<List<SavedTravel>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final travels = snapshot.data ?? [];
                  if (travels.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'No saved travels yet. Search a trip, then tap '
                        '"Save Travel" to keep it here.',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: travels.length,
                    separatorBuilder: (_, __) => Divider(
                      color: Colors.blue.shade50,
                      height: 1,
                    ),
                    itemBuilder: (context, index) {
                      final travel = travels[index];
                      return ListTile(
                        leading: Icon(Icons.flight_takeoff,
                            color: Colors.blue.shade400),
                        title: Text(
                          travel.destinationCity,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          travel.departureCity.isNotEmpty
                              ? 'From ${travel.departureCity} • Saved ${_formatSavedAt(travel.savedAt)}'
                              : 'Saved ${_formatSavedAt(travel.savedAt)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: Colors.grey.shade500, fontSize: 12),
                        ),
                        trailing: IconButton(
                          icon: Icon(Icons.delete_outline,
                              color: Colors.grey.shade400, size: 20),
                          tooltip: 'Remove',
                          onPressed: () async {
                            await TravelStorageService.delete(travel.id);
                            _refresh();
                          },
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ResultsScreen(
                                travelPlan: travel.travelPlan,
                                savedId: travel.id,
                              ),
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
