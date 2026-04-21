class ChecklistItem {
  final int realIndex;
  final String no;
  final String itemCode;
  final String quantity;
  bool isComplete;
  bool isShortage;
  bool isRework;
  String remarks;

  ChecklistItem({
    required this.realIndex,
    required this.no,
    required this.itemCode,
    required this.quantity,
    this.isComplete = false,
    this.isShortage = false,
    this.isRework = false,
    this.remarks = "",
  });

  Map<String, dynamic> toMap() {
    return {
      'realIndex': realIndex,
      'no': no,
      'itemCode': itemCode,
      'quantity': quantity,
      'isComplete': isComplete,
      'isShortage': isShortage,
      'isRework': isRework,
      'remarks': remarks,
    };
  }
}
