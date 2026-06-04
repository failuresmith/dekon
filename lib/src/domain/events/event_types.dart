abstract final class EventTypes {
  static const productCreated = 'product.created';
  static const productFieldSet = 'product.field_set';
  static const productDeactivated = 'product.deactivated';
  static const inventoryPurchaseRecorded = 'inventory.purchase_recorded';
  static const inventorySaleRecorded = 'inventory.sale_recorded';
  static const inventoryAdjustmentRecorded = 'inventory.adjustment_recorded';
  static const saleVoided = 'sale.voided';
  static const purchaseCorrected = 'purchase.corrected';

  static const supported = <String>{
    productCreated,
    productFieldSet,
    productDeactivated,
    inventoryPurchaseRecorded,
    inventorySaleRecorded,
    inventoryAdjustmentRecorded,
    saleVoided,
    purchaseCorrected,
  };
}
