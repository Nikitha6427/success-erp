import '../../core/repository/base_repository.dart';
import 'models/customer.dart';

class CustomerRepository extends BaseRepository<Customer> {
  CustomerRepository(super.store);

  @override
  String get tableName => 'Customers';

  @override
  Customer fromMap(Map<String, String> row) => Customer.fromMap(row);

  @override
  Map<String, String> toMap(Customer item) => item.toMap();

  @override
  String getId(Customer item) => item.id;
}
