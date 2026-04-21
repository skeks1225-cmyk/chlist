package org.example.checksheetv163;

import android.app.Activity;
import android.os.Bundle;
import android.widget.*;
import android.view.*;
import android.graphics.Color;
import android.content.Intent;

import com.github.barteksc.pdfviewer.PDFView;
import com.github.barteksc.pdfviewer.scroll.DefaultScrollHandle;

import java.io.File;
import java.util.ArrayList;

import org.kivy.android.PythonActivity;

public class PdfActivity extends Activity {

    static ArrayList<String> fileList;
    static int currentIndex = 0;

    public static void open(ArrayList<String> files, int index) {
        fileList = files;
        currentIndex = index;

        if (PythonActivity.mActivity != null) {
            PythonActivity.mActivity.runOnUiThread(() -> {
                Intent intent = new Intent(PythonActivity.mActivity, PdfActivity.class);
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                PythonActivity.mActivity.startActivity(intent);
            });
        }
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

        Button btnPrev = new Button(this); btnPrev.setText("이전");
        Button btnNext = new Button(this); btnNext.setText("다음");
        Button btnDone = new Button(this); btnDone.setText("완료");
        Button btnShort = new Button(this); btnShort.setText("부족");
        Button btnRework = new Button(this); btnRework.setText("재작업");

        btnLayout.addView(btnPrev);
        btnLayout.addView(btnNext);
        btnLayout.addView(btnDone);
        btnLayout.addView(btnShort);
        btnLayout.addView(btnRework);

        root.addView(pdfView, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, 0, 1));
        root.addView(btnLayout);

        setContentView(root);

        loadPdf();

        btnPrev.setOnClickListener(v -> {
            if (currentIndex > 0) {
                currentIndex--;
                loadPdf();
            }
        });

        btnNext.setOnClickListener(v -> {
            if (currentIndex < fileList.size() - 1) {
                currentIndex++;
                loadPdf();
            }
        });

        btnDone.setOnClickListener(v -> sendStatus("complete"));
        btnShort.setOnClickListener(v -> sendStatus("shortage"));
        btnRework.setOnClickListener(v -> sendStatus("rework"));
    }

    private void loadPdf() {
        try {
            if (fileList == null || fileList.size() == 0) return;

            String path = fileList.get(currentIndex);
            File file = new File(path);

            if (!file.exists()) {
                Toast.makeText(this, "파일 없음", Toast.LENGTH_SHORT).show();
                return;
            }

            titleView.setText(file.getName());

            pdfView.fromFile(file)
                    .enableSwipe(true)
                    .swipeHorizontal(false)
                    .enableDoubletap(true)
                    .defaultPage(0)
                    .enableAntialiasing(true)
                    .spacing(10)
                    .scrollHandle(new DefaultScrollHandle(this))
                    .load();

        } catch (Exception e) {
            Toast.makeText(this, "PDF 오류: " + e.getMessage(), Toast.LENGTH_LONG).show();
        }
    }

    private void sendStatus(String status) {
        try {
            String fileName = new File(fileList.get(currentIndex)).getName();
            String itemCode = fileName.replace(".pdf", "");

            // 전문가 조언대로 클래스로더 워밍업 (생략 없이 그대로 유지)
            org.kivy.android.PythonActivity.mActivity.runOnUiThread(() -> {
                try { Class.forName("org.kivy.android.PythonActivity"); } catch (Exception ignored) {}
            });

            // 🔥 실제 Python 호출 (수정본)
            PythonUtil.callPythonFunction("update_status_from_java", itemCode, status);
            Toast.makeText(this, itemCode + ": " + status + " 반영됨", Toast.LENGTH_SHORT).show();

            if (status.equals("complete") && currentIndex < fileList.size() - 1) {
                currentIndex++;
                loadPdf();
            }

        } catch (Exception e) {
            e.printStackTrace();
        }
    }
}
