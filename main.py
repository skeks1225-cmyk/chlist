import os
import shutil
import traceback
from kivy.app import App
from kivy.uix.boxlayout import BoxLayout
from kivy.uix.button import Button
from kivy.uix.label import Label
from kivy.uix.filechooser import FileChooserListView
from kivy.uix.popup import Popup
from kivy.utils import platform
from kivy.clock import Clock

class PDFTestApp(App):
    def build(self):
        self.root_layout = BoxLayout(orientation='vertical', padding=20, spacing=20)
        
        # 상태 표시 레이블
        self.status_label = Label(text="PDF 테스트 앱: 버튼을 눌러 파일을 선택하세요", size_hint_y=None, height=200)
        self.root_layout.add_widget(self.status_label)
        
        # 파일 선택 버튼
        btn = Button(text="휴대폰에서 PDF 파일 선택", size_hint_y=None, height=150)
        btn.bind(on_release=self.open_file_chooser)
        self.root_layout.add_widget(btn)
        
        self.webview = None
        return self.root_layout

    def open_file_chooser(self, instance):
        # 파일 선택기 팝업
        path = "/storage/emulated/0" if platform == 'android' else os.getcwd()
        fc = FileChooserListView(path=path, filters=['*.pdf'])
        
        content = BoxLayout(orientation='vertical')
        content.add_widget(fc)
        
        select_btn = Button(text="선택한 파일 열기", size_hint_y=None, height=120)
        content.add_widget(select_btn)
        
        popup = Popup(title="PDF 선택", content=content, size_hint=(0.9, 0.9))
        
        def on_select(btn):
            if fc.selection:
                selected_file = fc.selection[0]
                popup.dismiss()
                self.start_pdf_process(selected_file)
        
        select_btn.bind(on_release=on_select)
        popup.open()

    def start_pdf_process(self, file_path):
        self.status_label.text = f"선택됨: {os.path.basename(file_path)}\n복사 중..."
        Clock.schedule_once(lambda dt: self.copy_and_show(file_path), 0.5)

    def copy_and_show(self, src_path):
        try:
            if platform != 'android':
                self.status_label.text = "윈도우는 WebView 출력을 지원하지 않습니다."
                return

            from jnius import autoclass
            mActivity = autoclass('org.kivy.android.PythonActivity').mActivity
            internal_dir = mActivity.getFilesDir().getAbsolutePath()
            
            # 1. 파일 복사 (temp.pdf)
            dest_path = os.path.join(internal_dir, "temp.pdf")
            if os.path.exists(dest_path): os.remove(dest_path)
            shutil.copy2(src_path, dest_path)
            
            # 2. pdfjs 엔진 복사 (없을 경우만)
            dest_pdfjs = os.path.join(internal_dir, "pdfjs")
            src_pdfjs = os.path.join(os.path.dirname(os.path.abspath(__file__)), "pdfjs")
            if not os.path.exists(dest_pdfjs):
                shutil.copytree(src_pdfjs, dest_pdfjs)
                self.status_label.text = "엔진 설치 완료"

            # 3. WebView 실행 (지연 실행으로 충돌 방지)
            self.status_label.text = "WebView 생성 중..."
            Clock.schedule_once(lambda dt: self.init_webview(dest_path), 1.0)

        except Exception as e:
            self.status_label.text = f"오류 발생:\n{str(e)}"
            print(traceback.format_exc())

    def init_webview(self, pdf_path):
        from android.runnable import run_on_main_thread
        
        @run_on_main_thread
        def _setup():
            try:
                from jnius import autoclass
                mActivity = autoclass('org.kivy.android.PythonActivity').mActivity
                
                if not self.webview:
                    WebView = autoclass('android.webkit.WebView')
                    self.webview = WebView(mActivity)
                    settings = self.webview.getSettings()
                    settings.setJavaScriptEnabled(True)
                    settings.setAllowFileAccess(True)
                    settings.setDomStorageEnabled(True)
                    
                    # 하드웨어 가속 문제 방지를 위해 소프트웨어 모드 설정
                    self.webview.setLayerType(1, None) # 1 = View.LAYER_TYPE_SOFTWARE
                    
                    # 전체 화면 레이아웃 설정
                    params = autoclass('android.view.ViewGroup$LayoutParams')
                    mActivity.getWindow().getDecorView().addView(self.webview, params(-1, -1))
                
                self.webview.setVisibility(0) # Visible
                self.webview.bringToFront()
                
                internal_dir = mActivity.getFilesDir().getAbsolutePath()
                url = f"file://{internal_dir}/pdfjs/web/viewer.html?file=file://{pdf_path}"
                self.webview.loadUrl(url)
                self.status_label.text = "WebView 로드 완료"
                
            except Exception as e:
                self.status_label.text = f"WebView 초기화 실패:\n{str(e)}"
        
        _setup()

if __name__ == '__main__':
    PDFTestApp().run()
