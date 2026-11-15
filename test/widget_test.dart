import 'package:flutter_test/flutter_test.dart';
import 'package:janki_jwellers/models.dart';

void main() {
  test('gold item is priced by purity and making charge', () {
    final bill = BillData(
      goldRate: '70000',
      goldMaking: '10',
      items: [ItemData(weight: '10', goldPurity: 24)],
    );
    expect(bill.jewelleryTotal, 70000);
    expect(bill.makingTotal, 7000);
    expect(bill.grandTotal, 77000);
  });

  test('bill survives a JSON round trip', () {
    final bill = BillData(customerName: 'Test', items: [ItemData(name: 'Ring', weight: '5')]);
    final copy = BillData.fromJson(bill.toJson());
    expect(copy.customerName, 'Test');
    expect(copy.items.single.name, 'Ring');
  });
}
