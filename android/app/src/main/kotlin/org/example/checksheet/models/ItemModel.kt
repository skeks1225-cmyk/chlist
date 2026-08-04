package org.example.checksheet.models

data class ItemModel(
    val realIndex: Int,
    var no: String,
    var displayNo: String,
    var itemCode: String,
    var quantity: String,
    var complete: Boolean = false,
    var complement: String = "",
    var process: String = "",
    var remarks: String = "",
    var processTime: String = "",
    var complementTime: String = "",
    var completeTime: String = "",
    var isSubheading: Boolean = false,
    var subheadingTitle: String = ""
) {
    init {
        if (no.lowercase() == "null") no = ""
        if (displayNo.lowercase() == "null") displayNo = ""
        if (itemCode.lowercase() == "null") itemCode = ""
        if (quantity.lowercase() == "null") quantity = ""
        if (complement.lowercase() == "null") complement = ""
        if (process.lowercase() == "null") process = ""
        if (remarks.lowercase() == "null") remarks = ""
        if (processTime.lowercase() == "null") processTime = ""
        if (complementTime.lowercase() == "null") complementTime = ""
        if (completeTime.lowercase() == "null") completeTime = ""
        if (subheadingTitle.lowercase() == "null") subheadingTitle = ""
    }
}
