import '../../core/repository/base_repository.dart';
import '../../core/services/sheets_service.dart';
import 'models/product.dart';

class ProductRepository extends BaseRepository<Product> {
  ProductRepository(super.sheetsService);

  @override
  String get tabName => 'Products';

  @override
  List<String> get headers => SheetsService.tabHeaders['Products']!;

  @override
  Product fromRow(List<String> row) => Product.fromRow(row);

  @override
  List<String> toRow(Product item) => item.toRow();

  @override
  String getId(Product item) => item.id;

  @override
  int get updatedAtColumnIndex => 7;
}
