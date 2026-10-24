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
  String completeTime;     // ❗ 완료 기록 시간
  bool packed;             // ❗ 포장 완료 여부
  String packedTime;       // ❗ 포장 기록 시간
  bool isSubheading;
  String subheadingTitle; // ❗ 해당 항목이 속한 부분제목
  bool isMerged; // ❗ 동일 부분제목 내 중복 합산 항목 여부
  List<int> mergedRealIndices; // ❗ 합산된 원본 항목들의 realIndex 목록
  bool hasDifferentRemarks; // ❗ 중복 항목들 간 비고 내용 상이 여부
  bool isCrossDuplicate; // ❗ 서로 다른 부분제목에 동일 품목코드 존재 여부 (붉은색 경고용)

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
    this.completeTime = "",
    this.packed = false,
    this.packedTime = "",
    this.isSubheading = false,
    this.subheadingTitle = "",
    this.isMerged = false,
    List<int>? mergedRealIndices,
    this.hasDifferentRemarks = false,
    this.isCrossDuplicate = false,
  }) : mergedRealIndices = mergedRealIndices ?? [] {
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
    if (this.completeTime.toLowerCase() == "null") this.completeTime = "";
    if (this.packedTime.toLowerCase() == "null") this.packedTime = "";
    if (this.subheadingTitle.toLowerCase() == "null") this.subheadingTitle = "";
  }

  ItemModel copy({
    String? quantity,
    bool? isMerged,
    List<int>? mergedRealIndices,
    bool? hasDifferentRemarks,
    bool? isCrossDuplicate,
  }) {
    return ItemModel(
      realIndex: realIndex,
      no: no,
      displayNo: displayNo,
      itemCode: itemCode,
      quantity: quantity ?? this.quantity,
      complete: complete,
      complement: complement,
      process: process,
      remarks: remarks,
      processTime: processTime,
      complementTime: complementTime,
      completeTime: completeTime,
      packed: packed,
      packedTime: packedTime,
      isSubheading: isSubheading,
      subheadingTitle: subheadingTitle,
      isMerged: isMerged ?? this.isMerged,
      mergedRealIndices: mergedRealIndices ?? List.from(this.mergedRealIndices),
      hasDifferentRemarks: hasDifferentRemarks ?? this.hasDifferentRemarks,
      isCrossDuplicate: isCrossDuplicate ?? this.isCrossDuplicate,
    );
  }
}
