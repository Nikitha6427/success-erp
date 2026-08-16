import '../../core/repository/base_repository.dart';
import 'models/product.dart';

class ProductRepository extends BaseRepository<Product> {
  ProductRepository(super.store);

  @override
  String get tableName => 'Products';

  @override
  Product fromMap(Map<String, String> row) => Product.fromMap(row);

  @override
  Map<String, String> toMap(Product item) => item.toMap();

  @override
  String getId(Product item) => item.id;
}
