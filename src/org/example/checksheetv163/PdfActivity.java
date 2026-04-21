package org.example.checksheetv163;

import android.os.Bundle;
import android.widget.*;
import android.view.*;
import android.graphics.Color;
import android.content.Intent;

import com.github.barteksc.pdfviewer.PDFView;

import java.io.File;
import java.util.ArrayList;

import org.kivy.android.PythonActivity;

public class PdfActivity extends android.app.Activity {

    static ArrayList<String> fileList;
    static int currentIndex = 0;

    // Python에서 호출할 정적 메서드
    public static void open(ArrayList<String> files, int index) {
        fileList = files;
        currentIndex = index;

        PythonActivity.mActivity.runOnUiThread(new Runnable() {
            @Override
            public void run() {
                Intent intent = new Intent(PythonActivity.mActivity, PdfActivity.class);
                PythonActivity.mActivity.startActivity(intent);
            }
        });
    }

    PDFView pdfView;
    TextView titleView;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(Color.BLACK);

        titleView = new TextView(this);
        titleView.setTextColor(Color.WHITE);
        titleView.setPadding(20, 20, 20, 20);
        titleView.setTextSize(16);
        root.addView(titleView);

        pdfView = new PDFView(this, null);

        LinearLayout btnLayout = new LinearLayout(this);
        btnLayout.setOrientation(LinearLayout.HORIZONTAL);
        btnLayout.setGravity(Gravity.CENTER);
        btnLayout.setPadding(10, 10, 10, 10);

        Button btnPrev = new Button(this); btnPrev.setText("이전");
        Button btnNext = new Button(this); btnNext.setText("다음");
        Button btnDone = new Button(this); btnDone.setText("완료");
        btnDone.setBackgroundColor(Color.parseColor("#2E7D32")); btnDone.setTextColor(Color.WHITE);
        
        Button btnShort = new Button(this); btnShort.setText("부족");
        btnShort.setBackgroundColor(Color.parseColor("#FBC02D"));
        
        Button btnRework = new Button(this); btnRework.setText("재작업");
        btnRework.setBackgroundColor(Color.parseColor("#C62828")); btnRework.setTextColor(Color.WHITE);

        btnLayout.addView(btnPrev, new LinearLayout.LayoutParams(0, -2, 1));
        btnLayout.addView(btnNext, new LinearLayout.LayoutParams(0, -2, 1));
        btnLayout.addView(btnDone, new LinearLayout.LayoutParams(0, -2, 1.2f));
        btnLayout.addView(btnShort, new LinearLayout.LayoutParams(0, -2, 1.2f));
        btnLayout.addView(btnRework, new LinearLayout.LayoutParams(0, -2, 1.2f));

        root.addView(pdfView, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1));
        root.addView(btnLayout);

        setContentView(root);
        loadPdf();

        btnPrev.setOnClickListener(v -> { if (currentIndex > 0) { currentIndex--; loadPdf(); } });
        btnNext.setOnClickListener(v -> { if (currentIndex < fileList.size() - 1) { currentIndex++; loadPdf(); } });
        
        btnDone.setOnClickListener(v -> sendStatus("complete"));
        btnShort.setOnClickListener(v -> sendStatus("shortage"));
        btnRework.setOnClickListener(v -> sendStatus("rework"));
    }

    private void loadPdf() {
        try {
            if (fileList == null || fileList.isEmpty()) {
                Toast.makeText(this, "표시할 파일이 없습니다.", Toast.LENGTH_SHORT).show();
                return;
            }
            String path = fileList.get(currentIndex);
            File file = new File(path);
            
            if (!file.exists()) {
                titleView.setText("파일 없음: " + file.getName());
                return;
            }

            titleView.setText("[" + (currentIndex + 1) + "/" + fileList.size() + "] " + file.getName());

            pdfView.fromFile(file)
                    .enableSwipe(true)
                    .swipeHorizontal(false) // 세로 스크롤이 더 안정적임
                    .enableDoubletap(true)
                    .defaultPage(0)
                    .load();
        } catch (Exception e) {
            Toast.makeText(this, "PDF 로드 실패: " + e.getMessage(), Toast.LENGTH_SHORT).show();
        }
    }

    private void sendStatus(String status) {
        try {
            String filePath = fileList.get(currentIndex);
            String fileName = new File(filePath).getName();
            String itemCode = fileName.replace(".pdf", "");

            // Python 콜백 호출
            PythonUtil.callPythonFunction("update_status_from_java", itemCode, status);
            Toast.makeText(this, itemCode + ": " + status + " 반영됨", Toast.LENGTH_SHORT).show();
            
            // '완료'인 경우 자동으로 다음 파일로 이동 (편의성)
            if (status.equals("complete") && currentIndex < fileList.size() - 1) {
                currentIndex++;
                loadPdf();
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
    }
}
