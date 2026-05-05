class ItemModel {
  final int realIndex;
  String no;
  String displayNo; // ❗ 화면 표시용 가상 번호
  String itemCode;
  String quantity;
  bool complete;
  String complement; 
  String process;    
  String remarks;
  bool isSubheading;

  ItemModel({
    required this.realIndex,
    required this.no,
    this.displayNo = "",
    required this.itemCode,
    required this.quantity,
    this.complete = false,
    this.complement = "",
    this.process = "",
    this.remarks = "",
    this.isSubheading = false,
  });
}
