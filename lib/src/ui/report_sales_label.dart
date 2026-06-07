import '../application/application.dart';
import 'ui_strings.dart';

String reportSalesLabel(UiStrings strings) {
  return strings.language == AppLanguage.farsi ? strings.sell : strings.revenue;
}
