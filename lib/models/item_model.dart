class ItemModel {
  final int realIndex;
  String no;
  String itemCode;
  String quantity;
  bool complete;
  String complement; // ❗ 부족/재작업 -> 보완 (글자 저장)
  String process;    // ❗ 재작업 -> 공정 (글자 저장)
  String remarks;
  bool isSubheading;

  ItemModel({
    required this.realIndex,
    required this.no,
    required this.itemCode,
    required this.quantity,
    this.complete = false,
    this.complement = "",
    this.process = "",
    this.remarks = "",
    this.isSubheading = false,
  });
}
