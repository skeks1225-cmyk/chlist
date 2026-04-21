class ItemModel {
  final int realIndex;
  String no;
  String itemCode;
  String quantity;
  bool complete;
  bool shortage;
  bool rework;
  String remarks;

  ItemModel({
    required this.realIndex,
    required this.no,
    required this.itemCode,
    required this.quantity,
    this.complete = false,
    this.shortage = false,
    this.rework = false,
    this.remarks = "",
  });
}
