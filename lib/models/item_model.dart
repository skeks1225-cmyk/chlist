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
  String processTime;      // ❗ 공정 기록 시간
  String complementTime;   // ❗ 보완 기록 시간
  bool isSubheading;
  String subheadingTitle; // ❗ 해당 항목이 속한 부분제목

  ItemModel({
    required this.realIndex,
    required this.no,
    required this.displayNo,
    required this.itemCode,
    required this.quantity,
    this.complete = false,
    this.complement = "",
    this.process = "",
    this.remarks = "",
    this.processTime = "",
    this.complementTime = "",
    this.isSubheading = false,
    this.subheadingTitle = "",
  }) {
    // ❗ "null" 문자열 방어 코드 (생성 시점에 빈값으로 치환)
    if (this.no.toLowerCase() == "null") this.no = "";
    if (this.displayNo.toLowerCase() == "null") this.displayNo = "";
    if (this.itemCode.toLowerCase() == "null") this.itemCode = "";
    if (this.quantity.toLowerCase() == "null") this.quantity = "";
    if (this.complement.toLowerCase() == "null") this.complement = "";
    if (this.process.toLowerCase() == "null") this.process = "";
    if (this.remarks.toLowerCase() == "null") this.remarks = "";
    if (this.processTime.toLowerCase() == "null") this.processTime = "";
    if (this.complementTime.toLowerCase() == "null") this.complementTime = "";
    if (this.subheadingTitle.toLowerCase() == "null") this.subheadingTitle = "";
  }
}
