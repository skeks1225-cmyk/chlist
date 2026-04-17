from kivy.app import App
from kivy.uix.label import Label
from kivy.utils import platform
from kivy.clock import Clock
import os
import traceback

class TestApp(App):
    def build(self):
        # 화면에 진행 상태를 보여줄 라벨
        self.debug_label = Label(
            text="App Started\nChecking System...",
            halign="center",
            font_size="18sp"
        )
        return self.debug_label

    def update_status(self, text, color=(1, 1, 1, 1)):
        self.debug_label.text += f"\n{text}"
        self.debug_label.color = color

    def on_start(self):
        if platform == 'android':
            self.update_status("Platform: Android")
            from android.permissions import request_permissions, Permission
            request_permissions([
                Permission.READ_EXTERNAL_STORAGE, 
                Permission.WRITE_EXTERNAL_STORAGE,
                Permission.MANAGE_EXTERNAL_STORAGE
            ])
            # 권한 요청 후 잠시 대기했다가 PDF 열기 시도
            Clock.schedule_once(self.open_pdf, 2)
        else:
            self.update_status("Platform: Non-Android (Test Mode)")

    def open_pdf(self, dt):
        try:
            self.update_status("Step 1: Loading Jnius...")
            from jnius import autoclass
            from android.runnable import run_on_main_thread

            self.update_status("Step 2: Checking PDF File...")
            # 프로젝트 내부의 pdf 폴더 확인
            current_dir = os.path.dirname(__file__)
            pdf_path = os.path.join(current_dir, "pdf", "4000500638.pdf")
            
            if not os.path.exists(pdf_path):
                # 다른 경로도 시도 (pdfss 등)
                pdf_path = os.path.join(current_dir, "pdfss", "4000500638.pdf")
            
            if os.path.exists(pdf_path):
                self.update_status(f"File Found: {os.path.basename(pdf_path)}")
            else:
                self.update_status("Error: PDF File Not Found!", (1, 0, 0, 1))
                return

            @run_on_main_thread
            def run_native_viewer():
                try:
                    self.update_status("Step 3: Launching Native Viewer...")
                    PythonActivity = autoclass('org.kivy.android.PythonActivity')
                    mActivity = PythonActivity.mActivity
                    
                    # mhiew/barteksc 라이브러리의 클래스명
                    PDFView = autoclass('com.github.barteksc.pdfviewer.PDFView')
                    File = autoclass('java.io.File')
                    LayoutParams = autoclass('android.view.ViewGroup$LayoutParams')

                    # 뷰어 생성 및 배치
                    pdfView = PDFView(mActivity, None)
                    mActivity.addContentView(pdfView, LayoutParams(-1, -1))

                    # 파일 로드
                    file = File(pdf_path)
                    pdfView.fromFile(file)\
                        .enableSwipe(True)\
                        .swipeHorizontal(False)\
                        .enableDoubletap(True)\
                        .defaultPage(0)\
                        .load()
                    
                    self.update_status("SUCCESS: PDF should be visible now!", (0, 1, 0, 1))
                except Exception as e:
                    error_msg = f"Native Error: {str(e)}\n{traceback.format_exc()}"
                    print(error_msg)
                    self.update_status("Native Crash!", (1, 0, 0, 1))
                    # 에러 내용을 라벨에 상세히 표시
                    self.debug_label.text = error_msg

            run_native_viewer()

        except Exception as e:
            error_msg = f"Pyjnius Error: {str(e)}"
            self.update_status(error_msg, (1, 0, 0, 1))
            self.debug_label.text = error_msg + "\n" + traceback.format_exc()

if __name__ == '__main__':
    TestApp().run()
