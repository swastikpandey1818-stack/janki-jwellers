import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

const _kStock = 'stock_v1';

/// One kind of item kept in the shop (e.g. "Gold chain 22K").
class StockItem {
  StockItem({
    required this.id,
    required this.name,
    required this.type,
    this.purity = '',
    this.weight = 0,
    this.pieces = 0,
    this.minPieces = 0,
    this.note = '',
    List<StockMove>? moves,
  }) : moves = moves ?? [];

  final String id;
  String name;
  ItemType type;
  String purity; // e.g. '22K', '92.5%'
  double weight; // total grams in stock
  int pieces;
  int minPieces; // alert when pieces fall to this number or below (0 = no alert)
  String note;
  final List<StockMove> moves; // newest first

  bool get low => minPieces > 0 && pieces <= minPieces;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.index,
        'purity': purity,
        'weight': weight,
        'pieces': pieces,
        'minPieces': minPieces,
        'note': note,
        'moves': moves.map((m) => m.toJson()).toList(),
      };

  factory StockItem.fromJson(Map<String, dynamic> j) {
    final t = j['type'];
    return StockItem(
      id: (j['id'] ?? '').toString(),
      name: (j['name'] ?? '').toString(),
      type: (t is int && t >= 0 && t < ItemType.values.length) ? ItemType.values[t] : ItemType.gold,
      purity: (j['purity'] ?? '').toString(),
      weight: (j['weight'] is num) ? (j['weight'] as num).toDouble() : 0,
      pieces: (j['pieces'] is num) ? (j['pieces'] as num).toInt() : 0,
      minPieces: (j['minPieces'] is num) ? (j['minPieces'] as num).toInt() : 0,
      note: (j['note'] ?? '').toString(),
      moves: (j['moves'] as List?)
              ?.map((e) => StockMove.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          <StockMove>[],
    );
  }
}

/// A stock in / stock out entry.
class StockMove {
  StockMove({required this.date, required this.isIn, required this.weight, required this.pieces, this.note = ''});

  final DateTime date;
  final bool isIn;
  final double weight;
  final int pieces;
  final String note;

  Map<String, dynamic> toJson() => {
        'date': date.toIso8601String(),
        'in': isIn,
        'weight': weight,
        'pieces': pieces,
        'note': note,
      };

  factory StockMove.fromJson(Map<String, dynamic> j) => StockMove(
        date: DateTime.tryParse((j['date'] ?? '').toString()) ?? DateTime.now(),
        isIn: j['in'] != false,
        weight: (j['weight'] is num) ? (j['weight'] as num).toDouble() : 0,
        pieces: (j['pieces'] is num) ? (j['pieces'] as num).toInt() : 0,
        note: (j['note'] ?? '').toString(),
      );
}

class StockStore extends ChangeNotifier {
  SharedPreferences? _p;
  List<StockItem> items = [];

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      _p = p;
      final raw = p.getString(_kStock);
      if (raw != null) _readList(jsonDecode(raw));
    } catch (_) {
      items = [];
    }
  }

  void _readList(dynamic decoded) {
    if (decoded is! List) return;
    final out = <StockItem>[];
    for (final e in decoded) {
      try {
        out.add(StockItem.fromJson(Map<String, dynamic>.from(e as Map)));
      } catch (_) {}
    }
    items = out;
  }

  Future<void> _save() async {
    notifyListeners();
    try {
      await _p?.setString(_kStock, jsonEncode(items.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }

  List<StockItem> get sorted {
    final l = List<StockItem>.of(items);
    l.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return l;
  }

  int get lowCount => items.where((e) => e.low).length;
  double weightOf(ItemType t) => items.where((e) => e.type == t).fold(0.0, (s, e) => s + e.weight);
  int get totalPieces => items.fold(0, (s, e) => s + e.pieces);

  Future<void> add(StockItem item) async {
    items.add(item);
    if (item.weight > 0 || item.pieces > 0) {
      item.moves.insert(0, StockMove(date: DateTime.now(), isIn: true, weight: item.weight, pieces: item.pieces, note: 'Opening stock'));
    }
    await _save();
  }

  Future<void> edit(StockItem item) => _save();

  Future<void> remove(String id) async {
    items.removeWhere((e) => e.id == id);
    await _save();
  }

  /// Returns an error message, or null when done.
  Future<String?> move(StockItem item, {required bool isIn, required double weight, required int pieces, String note = ''}) async {
    if (weight < 0 || pieces < 0) return 'Weight and pieces cannot be negative.';
    if (weight == 0 && pieces == 0) return 'Enter a weight or number of pieces.';
    if (!isIn && (weight > item.weight + 0.0005 || pieces > item.pieces)) {
      return 'Not enough stock. Available: ${item.weight.toStringAsFixed(3)} g, ${item.pieces} pcs.';
    }
    item.weight = isIn ? item.weight + weight : item.weight - weight;
    item.pieces = isIn ? item.pieces + pieces : item.pieces - pieces;
    if (item.weight < 0) item.weight = 0;
    item.moves.insert(0, StockMove(date: DateTime.now(), isIn: isIn, weight: weight, pieces: pieces, note: note));
    await _save();
    return null;
  }

  // ---- backup ----
  List<Map<String, dynamic>> toJsonList() => items.map((e) => e.toJson()).toList();

  Future<void> restore(dynamic list, {required bool replace}) async {
    if (list is! List) return;
    if (replace) {
      _readList(list);
    } else {
      final known = items.map((e) => e.id).toSet();
      for (final e in list) {
        try {
          final it = StockItem.fromJson(Map<String, dynamic>.from(e as Map));
          if (!known.contains(it.id)) items.add(it);
        } catch (_) {}
      }
    }
    await _save();
  }
}

final StockStore stockStore = StockStore();
