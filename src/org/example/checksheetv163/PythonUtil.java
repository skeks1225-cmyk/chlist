package org.example.checksheetv163;

import org.kivy.android.PythonActivity;

public class PythonUtil {
    /**
     * Java에서 Python의 global 함수를 호출합니다.
     * @param function 함수명
     * @param args 인자 (문자열로 전달됨)
     */
    public static void callPythonFunction(String function, String... args) {
        StringBuilder sb = new StringBuilder();
        sb.append("import main; main.").append(function).append("(");
        for (int i = 0; i < args.length; i++) {
            sb.append("'").append(args[i].replace("'", "\\'")).append("'");
            if (i < args.length - 1) sb.append(", ");
        }
        sb.append(")");
        
        final String pythonCode = sb.toString();
        
        PythonActivity.mActivity.runOnUiThread(new Runnable() {
            @Override
            public void run() {
                try {
                    // Kivy Python Interpreter를 통해 코드 실행
                    PythonActivity.mActivity.runPython(pythonCode);
                } catch (Exception e) {
                    e.printStackTrace();
                }
            }
        });
    }
}
