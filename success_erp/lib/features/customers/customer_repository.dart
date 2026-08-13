import '../../core/repository/base_repository.dart';
import '../../core/services/sheets_service.dart';
import 'models/customer.dart';

class CustomerRepository extends BaseRepository<Customer> {
  CustomerRepository(super.sheetsService);

  @override
  String get tabName => 'Customers';

  @override
  List<String> get headers => SheetsService.tabHeaders['Customers']!;

  @override
  Customer fromRow(List<String> row) => Customer.fromRow(row);

  @override
  List<String> toRow(Customer item) => item.toRow();

  @override
  String getId(Customer item) => item.id;

  @override
  int get updatedAtColumnIndex => 7;
}
